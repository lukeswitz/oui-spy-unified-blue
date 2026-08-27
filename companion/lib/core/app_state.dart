import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';

/// App-wide state that survives navigation. Single source of truth.
/// All screens read from here instead of creating their own subscriptions.
class AppState extends ChangeNotifier {
  AppState(this._ble, this._gps, this._ignoreList, this._geofenceFilter, this._notificationService, this._liveActivity) {
    _init();
  }

  final BleManager _ble;
  final GpsProvider _gps;
  final IgnoreListState _ignoreList;
  final GeofenceFilter _geofenceFilter;
  final NotificationService _notificationService;
  final LiveActivityService _liveActivity;
  final List<StreamSubscription<dynamic>> _subs = [];

  // Connection
  NodeConnectionState connectionState = NodeConnectionState.disconnected;
  bool get isConnected => connectionState == NodeConnectionState.ready;
  bool get isManagerConnected => isConnected && _ble.isManagerConnected;
  String nodeId = '';

  // Engine states
  int availableEngines = 0;
  int activeEngines = 0;
  List<EngineState> engineStates = List.filled(Engine.values.length, EngineState.disabled);

  // Per-engine radio config: 0x01=WiFi, 0x02=BLE, 0x03=both
  final Map<Engine, int> engineRadio = {
    Engine.detector: 0x03,
    Engine.foxhunter: 0x03,
    Engine.wardrive: 0x03,
    Engine.skySpy: 0x03,
  };

  void setEngineRadio(Engine engine, int radio) {
    engineRadio[engine] = radio;
    if (isEngineActive(engine)) {
      _ble.sendEngineConfig(engine, Uint8List.fromList([radio]));
    }
    notifyListeners();
  }

  // Session timing
  DateTime? sessionStartTime;
  Duration get sessionUptime =>
      sessionStartTime != null ? DateTime.now().difference(sessionStartTime!) : Duration.zero;

  // Detection counts per engine — unique MACs, not raw event count
  final Map<Engine, Set<String>> _uniqueMacsPerEngine = {};
  int get totalDetections => _uniqueMacsPerEngine.values.fold(0, (a, b) => a + b.length);

  // Per-engine last detection time
  final Map<Engine, DateTime> lastDetectionTime = {};

  // Per-engine detection rate (events in last 60s)
  final Map<Engine, List<DateTime>> _recentDetectionTimes = {};
  int detectionRate(Engine engine) {
    final times = _recentDetectionTimes[engine];
    if (times == null || times.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    times.removeWhere((t) => t.isBefore(cutoff));
    return times.length;
  }

  int get totalRate {
    int sum = 0;
    for (final engine in Engine.values) {
      sum += detectionRate(engine);
    }
    return sum;
  }

  // Recent detections ring buffer (feed), deduped by MAC+engine
  final List<Detection> recentDetections = [];

  static const int _maxTrackPoints = 500;
  final Map<String, List<LatLng>> _droneTracks = {};
  final Map<String, List<LatLng>> _pilotTracks = {};
  List<LatLng>? droneTrack(String mac) => _droneTracks[mac];
  List<LatLng>? pilotTrack(String mac) => _pilotTracks[mac];
  final Map<String, int> _dedupeIndex = {}; // "mac|engine" → index in list
  static const int maxRecentDetections = 500;

  // Foxhunter
  int foxhunterRssi = -100;
  int foxhunterIntervalMs = 3000;
  String? foxhunterTarget;
  String? foxhunterTargetNodeId;

  int foxhunterChannel = 0;

  void setFoxhunterTarget(String mac, {int channel = 0, String? nodeId}) {
    if (OuiLookupService.isLawEnforcement(mac)) return;
    final effective = nodeId
        ?? foxhunterTargetNodeId
        ?? (isManagerConnected && knownNodes.isNotEmpty
            ? knownNodes.first
            : null);
    foxhunterTarget = mac;
    foxhunterChannel = channel;
    foxhunterTargetNodeId = effective;
    if (!isEngineActive(Engine.foxhunter)) {
      _ble.enableEngine(
        Engine.foxhunter,
        radio: engineRadio[Engine.foxhunter] ?? 0x03,
        targetNodeId: effective,
      );
    }
    _ble.setFoxhunterTarget(mac, channel: channel, nodeId: effective);
    notifyListeners();
  }

  void setFoxhunterTargetNode(String? nodeId) {
    if (foxhunterTargetNodeId == nodeId) return;
    final wasActive = foxhunterTarget != null && isEngineActive(Engine.foxhunter);
    if (wasActive && foxhunterTargetNodeId != null) {
      _ble.disableEngine(Engine.foxhunter, targetNodeId: foxhunterTargetNodeId);
    }
    foxhunterTargetNodeId = nodeId;
    if (wasActive && foxhunterTarget != null) {
      _ble.enableEngine(
        Engine.foxhunter,
        radio: engineRadio[Engine.foxhunter] ?? 0x03,
        targetNodeId: nodeId,
      );
      _ble.setFoxhunterTarget(foxhunterTarget!,
          channel: foxhunterChannel, nodeId: nodeId);
    }
    notifyListeners();
  }

  void clearFoxhunterTarget() {
    final nodeId = foxhunterTargetNodeId;
    foxhunterTarget = null;
    foxhunterChannel = 0;
    foxhunterTargetNodeId = null;
    foxhunterRssi = -100;
    foxhunterIntervalMs = 3000;
    _ble.disableEngine(Engine.foxhunter, targetNodeId: nodeId);
    notifyListeners();
  }

  // Mesh
  bool meshEnabled = false;
  bool meshEncryption = true;
  int meshPeerCount = 0;
  int meshConnectedPeers = 0;
  int meshRxCount = 0;
  int meshTxCount = 0;
  Uint8List? _meshKey;
  Uint8List? get meshKey => _meshKey;
  String get meshKeyFingerprint {
    final k = _meshKey;
    if (k == null || k.length < 4) return '';
    return k
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  Set<String> get meshSourceNodes {
    final nodes = <String>{};
    for (final d in recentDetections) {
      if (d.sourceNodeId.isNotEmpty) nodes.add(d.sourceNodeId);
    }
    return nodes;
  }

  Map<String, int> get detectionsPerSourceNode {
    final m = <String, int>{};
    final selfBucket = nodeId.isNotEmpty ? nodeId : 'LOCAL';
    for (final d in recentDetections) {
      final k = d.sourceNodeId.isEmpty ? selfBucket : d.sourceNodeId;
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  static String canonicalNodeId(String raw) {
    if (raw.isEmpty) return '';
    if (raw == 'LOCAL') return 'LOCAL';
    var s = raw.toUpperCase();
    const pfx = 'OUISPY-';
    if (s.startsWith(pfx)) s = s.substring(pfx.length);
    if (s.length < 4) return '';
    s = s.substring(s.length - 4);
    final ok = RegExp(r'^[0-9A-F]{4}$').hasMatch(s);
    return ok ? s : '';
  }

  String labelForNode(String id) {
    final canon = canonicalNodeId(id);
    final stored = _nodeLabels[canon];
    if (stored != null && stored.isNotEmpty) return stored;
    if (canon.isEmpty || id == 'LOCAL') return 'LOCAL';
    return 'OUISPY-$canon';
  }

  final Map<String, String> _nodeLabels = {};
  final Set<String> _seenNodes = {};
  final Map<String, int> _nodeLastSeenMs = {};
  final Map<String, int> _nodeFwVersion = {};
  final Set<String> _meshLiveNodeIds = {};
  final Set<String> _meshManagerNodeIds = {};
  bool isManagerNode(String id) =>
      _meshManagerNodeIds.contains(canonicalNodeId(id));

  String? nodeFwVersion(String id) {
    final v = _nodeFwVersion[canonicalNodeId(id)];
    if (v == null || v == 0) return null;
    return '${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }
  static const int _seenNodeTtlMs = 7 * 24 * 60 * 60 * 1000;
  static const int _liveNodeTtlMs = 30 * 1000;
  final Map<String, int> _nodeWardriveRadio = {};
  Map<String, String> get nodeLabels => Map.unmodifiable(_nodeLabels);
  Map<String, int> get nodeWardriveRadio => Map.unmodifiable(_nodeWardriveRadio);
  int wardriveRadioForNode(String id) =>
      _nodeWardriveRadio[canonicalNodeId(id)] ?? 0x03;

  Future<void> _persistNodeWardriveRadio() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      'nodeWardriveRadio',
      _nodeWardriveRadio.entries.map((e) => '${e.key}=${e.value}').toList(),
    );
  }

  Future<void> _pushNodeRadioRoles() async {
    try {
      await _ble.setNodeRadioRoles(_nodeWardriveRadio);
    } on Exception catch (e) {
      DebugLog.log('AppState: setNodeRadioRoles error: $e');
    }
  }

  Future<void> setWardriveRadioForNode(String id, int mask) async {
    final canon = canonicalNodeId(id);
    final m = (mask & 0x03) == 0 ? 0x03 : (mask & 0x03);
    _nodeWardriveRadio[canon] = m;
    await _persistNodeWardriveRadio();
    await _pushNodeRadioRoles();
    notifyListeners();
  }

  Future<void> applyNodeRadioRoles(Map<String, int> roles) async {
    roles.forEach((id, mask) {
      final canon = canonicalNodeId(id);
      if (canon.isEmpty) return;
      _nodeWardriveRadio[canon] = (mask & 0x03) == 0 ? 0x03 : (mask & 0x03);
    });
    await _persistNodeWardriveRadio();
    await _pushNodeRadioRoles();
    notifyListeners();
  }
  Set<String> get liveKnownNodes {
    final s = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in _meshLiveNodeIds) {
      final last = _nodeLastSeenMs[id] ?? 0;
      if ((now - last) <= _liveNodeTtlMs) s.add(id);
    }
    final selfCanon = canonicalNodeId(nodeId);
    if (isConnected && selfCanon.isNotEmpty && selfCanon != 'LOCAL') {
      s.add(selfCanon);
    }
    return s;
  }

  Set<String> get knownNodes {
    final s = <String>{};
    for (final k in detectionsPerSourceNode.keys) {
      final c = canonicalNodeId(k);
      if (c.isNotEmpty && c != 'LOCAL') s.add(c);
    }
    for (final k in _nodeLabels.keys) {
      if (k.isNotEmpty && k != 'LOCAL') s.add(k);
    }
    s.addAll(_seenNodes);
    final selfCanon = canonicalNodeId(nodeId);
    if (selfCanon.isNotEmpty && selfCanon != 'LOCAL') s.add(selfCanon);
    s.remove('LOCAL');
    return s;
  }
  void _recordSeenNode(String id) {
    final canon = canonicalNodeId(id);
    if (canon.isEmpty || canon == 'LOCAL') return;
    final added = _seenNodes.add(canon);
    _nodeLastSeenMs[canon] = DateTime.now().millisecondsSinceEpoch;
    if (added) {
      _persistSeenNodes();
      notifyListeners();
    }
  }

  void _persistSeenNodes() {
    SharedPreferences.getInstance().then((p) {
      p.setStringList('seenNodes', _seenNodes.toList());
      p.setStringList('nodeLastSeenMs',
          _nodeLastSeenMs.entries.map((e) => '${e.key}=${e.value}').toList());
    });
  }

  void _evictStaleSeenNodes() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <String>[];
    for (final id in _seenNodes) {
      final last = _nodeLastSeenMs[id] ?? 0;
      if (last == 0 || (now - last) > _seenNodeTtlMs) stale.add(id);
    }
    if (stale.isEmpty) return;
    for (final id in stale) {
      if (_nodeLabels.containsKey(id)) continue;
      _seenNodes.remove(id);
      _nodeLastSeenMs.remove(id);
    }
    _persistSeenNodes();
  }
  void forgetNode(String id) {
    final canon = canonicalNodeId(id);
    if (canon.isEmpty) return;
    var changed = false;
    if (_seenNodes.remove(canon)) changed = true;
    if (_nodeLabels.remove(canon) != null) changed = true;
    if (!changed) return;
    SharedPreferences.getInstance().then((p) {
      p.setStringList('seenNodes', _seenNodes.toList());
      p.setStringList(
        'nodeLabels',
        _nodeLabels.entries.map((e) => '${e.key}=${e.value}').toList(),
      );
    });
    notifyListeners();
  }
  void setNodeLabel(String id, String label) {
    final canon = canonicalNodeId(id);
    if (canon.isEmpty) return;
    if (label.isEmpty) {
      _nodeLabels.remove(canon);
    } else {
      _nodeLabels[canon] = label;
    }
    SharedPreferences.getInstance().then((p) {
      final entries = _nodeLabels.entries
          .map((e) => '${e.key}=${e.value}')
          .toList();
      p.setStringList('nodeLabels', entries);
    });
    notifyListeners();
  }

  void _loadNodeLabels(SharedPreferences p) {
    bool migrated = false;
    final entries = p.getStringList('nodeLabels') ?? const [];
    for (final e in entries) {
      final i = e.indexOf('=');
      if (i <= 0) continue;
      final rawKey = e.substring(0, i);
      final label = e.substring(i + 1);
      final canon = canonicalNodeId(rawKey);
      if (canon.isEmpty) { migrated = true; continue; }
      if (canon != rawKey) migrated = true;
      _nodeLabels[canon] = label;
    }
    for (final raw in p.getStringList('seenNodes') ?? const []) {
      final canon = canonicalNodeId(raw);
      if (canon.isEmpty || canon == 'LOCAL') { migrated = true; continue; }
      if (canon != raw) migrated = true;
      _seenNodes.add(canon);
    }
    for (final e in p.getStringList('nodeLastSeenMs') ?? const []) {
      final i = e.indexOf('=');
      if (i <= 0) continue;
      final canon = canonicalNodeId(e.substring(0, i));
      final ts = int.tryParse(e.substring(i + 1));
      if (canon.isEmpty || ts == null) continue;
      _nodeLastSeenMs[canon] = ts;
    }
    _evictStaleSeenNodes();
    for (final e in p.getStringList('nodeWardriveRadio') ?? const []) {
      final i = e.indexOf('=');
      if (i <= 0) continue;
      final rawKey = e.substring(0, i);
      final canon = canonicalNodeId(rawKey);
      if (canon.isEmpty) { migrated = true; continue; }
      if (canon != rawKey) migrated = true;
      final v = int.tryParse(e.substring(i + 1));
      if (v != null) _nodeWardriveRadio[canon] = v;
    }
    if (migrated) {
      p.setStringList('seenNodes', _seenNodes.toList());
      p.setStringList('nodeLabels',
          _nodeLabels.entries.map((e) => '${e.key}=${e.value}').toList());
      p.setStringList('nodeWardriveRadio',
          _nodeWardriveRadio.entries.map((e) => '${e.key}=${e.value}').toList());
      DebugLog.log('AppState: migrated node-id storage to canonical form');
    }
  }

  void _init() {
    SharedPreferences.getInstance().then((p) {
      _loadNodeLabels(p);
      notifyListeners();
    });
    loadMeshKey().then((_) {
      if (_meshKey != null) notifyListeners();
    });
    // Connection state
    connectionState = _ble.currentConnectionState;

    _subs.add(_ble.connectionState.listen((state) {
      connectionState = state;
      if (state == NodeConnectionState.ready) {
        nodeId = canonicalNodeId(_ble.nodeId);
        if (nodeId.isNotEmpty) _recordSeenNode(nodeId);
        sessionStartTime = DateTime.now();
        _ble.setIgnoreList(_ignoreList.serializeForFirmware());
        _gps.start().catchError((e) {
          DebugLog.log('GPS: start failed from BLE connect: $e');
          return false;
        });
        if (_nodeWardriveRadio.isNotEmpty) {
          DebugLog.log('AppState: connection ready — pushing saved node radio roles');
          _pushNodeRadioRoles();
        }
        _restoreHardwareConfig();
      }
      if (state == NodeConnectionState.disconnected ||
          state == NodeConnectionState.reconnecting) {
        // Reset engine UI to all-disabled — firmware state unknown until next read
        activeEngines = 0;
        engineStates = List.filled(Engine.values.length, EngineState.disabled);
        sessionStartTime = null;
      }
      notifyListeners();
    }));

    // Engine states
    _subs.add(_ble.engineStates.listen((status) {
      availableEngines = status.available;
      activeEngines = status.active;
      engineStates = List.from(status.states);
      while (engineStates.length < Engine.values.length) {
        engineStates.add(EngineState.disabled);
      }
      notifyListeners();
    }));

    // Detections — track unique MACs per engine + deduplicated ring buffer
    _subs.add(_ble.detections.listen((det) {
      final isBle = det.isBleDetection;
      if (_ignoreList.shouldSuppress(
        mac: det.macAddress,
        ssid: det.ssid.isNotEmpty ? det.ssid : det.deviceName,
        isBle: isBle,
      )) {
        return;
      }
      if (det.sourceNodeId.isNotEmpty) _recordSeenNode(det.sourceNodeId);
      if (_geofenceFilter.isExcludedNullable(det.latitude, det.longitude)) {
        return;
      }
      final isNewMac = !(_uniqueMacsPerEngine[det.engine]?.contains(det.macAddress) ?? false);
      (_uniqueMacsPerEngine[det.engine] ??= {}).add(det.macAddress);
      lastDetectionTime[det.engine] = DateTime.now();
      final rt = (_recentDetectionTimes[det.engine] ??= [])..add(DateTime.now());
      if (rt.length > 2000) rt.removeRange(0, rt.length - 2000);
      _upsertDetection(det);
      _recordDroneTrack(det);

      if (isNewMac &&
          !_geofenceFilter.isExcludedNullable(det.latitude, det.longitude)) {
        _notificationService.onDetection(det);
      }

      notifyListeners();
    }));

    _subs.add(_ble.importedDetections.listen(_ingestOfflineDetection));
    _subs.add(_ble.awayLiveDetections.listen(_ingestOfflineDetection));

    // Foxhunter RSSI
    _subs.add(_ble.foxhunterRssi.listen((data) {
      final previousRssi = foxhunterRssi;
      foxhunterRssi = data.rssi;
      foxhunterIntervalMs = data.intervalMs;

      if (foxhunterTarget != null) {
        _notificationService.onFoxhuntProximity(
          mac: foxhunterTarget!,
          rssi: data.rssi,
          previousRssi: previousRssi,
        );
        _liveActivity.update(
          primaryMode: 'foxhunter',
          allowStart: true,
          uniqueCount: totalDetections,
          targetMac: foxhunterTarget!,
          rssi: data.rssi,
          intervalMs: data.intervalMs,
        );
      }

      notifyListeners();
    }));

    _subs.add(_ble.meshStatusUpdates.listen((data) {
      meshEnabled = data.enabled;
      meshPeerCount = data.peerCount;
      meshConnectedPeers = data.connectedPeers;
      meshRxCount = data.rxCount;
      meshTxCount = data.txCount;
      final now = DateTime.now().millisecondsSinceEpoch;
      final live = <String>{};
      final managers = <String>{};
      for (final entry in data.liveNodes) {
        final canon = canonicalNodeId(entry.id);
        if (canon.isEmpty) continue;
        live.add(canon);
        if (entry.role == 1) managers.add(canon);
        _nodeLastSeenMs[canon] = now;
        if (entry.fwVersion != 0) _nodeFwVersion[canon] = entry.fwVersion;
      }
      _meshLiveNodeIds
        ..clear()
        ..addAll(live);
      _meshManagerNodeIds
        ..clear()
        ..addAll(managers);
      notifyListeners();
    }));

    DebugLog.log('AppState: initialized');
  }

  bool isEngineActive(Engine engine) {
    return (activeEngines & engine.bitmask) != 0;
  }

  EngineState getEngineState(Engine engine) {
    return engine.index < engineStates.length
        ? engineStates[engine.index]
        : EngineState.disabled;
  }

  int countForEngine(Engine engine) => _uniqueMacsPerEngine[engine]?.length ?? 0;

  List<Detection> detectionsForEngine(Engine engine) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    return recentDetections
        .where((d) => d.engine == engine && d.appTimestamp.isAfter(cutoff))
        .toList();
  }

  void clearDetectionsForEngine(Engine engine) {
    recentDetections.removeWhere((d) => d.engine == engine);
    _dedupeIndex.clear();
    for (int i = 0; i < recentDetections.length; i++) {
      _dedupeIndex['${recentDetections[i].macAddress}|${recentDetections[i].engine.name}'] = i;
    }
    notifyListeners();
  }


  void _ingestOfflineDetection(Detection det) {
    if (det.sourceNodeId.isNotEmpty) _recordSeenNode(det.sourceNodeId);
    (_uniqueMacsPerEngine[det.engine] ??= {}).add(det.macAddress);
    lastDetectionTime[det.engine] = DateTime.now();
    _upsertDetection(det);
    _recordDroneTrack(det);
    notifyListeners();
  }

  void _upsertDetection(Detection det) {
    final key = '${det.macAddress}|${det.engine.name}';
    final existingIdx = _dedupeIndex[key];

    if (existingIdx != null && existingIdx < recentDetections.length) {
      final existing = recentDetections[existingIdx];
      WardriveExtension? mergedWardrive = det.wardrive ?? existing.wardrive;
      if (det.wardrive != null && existing.wardrive != null) {
        final newAuth = det.wardrive!.authMode;
        final oldAuth = existing.wardrive!.authMode;
        mergedWardrive = det.wardrive!.copyWith(
          authMode: newAuth > 0 ? newAuth : oldAuth,
          ssid: det.wardrive!.ssid.isNotEmpty
              ? det.wardrive!.ssid
              : existing.wardrive!.ssid,
          deviceName: det.wardrive!.deviceName.isNotEmpty
              ? det.wardrive!.deviceName
              : existing.wardrive!.deviceName,
        );
      }
      final merged = det.copyWith(
        count: existing.count + 1,
        rssi: det.rssi > existing.rssi ? det.rssi : existing.rssi,
        wardrive: mergedWardrive,
      );
      recentDetections.removeAt(existingIdx);
      for (final entry in _dedupeIndex.entries) {
        if (entry.value > existingIdx) {
          _dedupeIndex[entry.key] = entry.value - 1;
        }
      }
      // Insert at front
      recentDetections.insert(0, merged);
      // Update all indices (shifted right by 1)
      for (final entry in _dedupeIndex.entries) {
        if (entry.key != key) {
          _dedupeIndex[entry.key] = entry.value + 1;
        }
      }
      _dedupeIndex[key] = 0;
    } else {
      // New entry
      recentDetections.insert(0, det);
      // Shift all existing indices
      for (final entry in _dedupeIndex.entries) {
        _dedupeIndex[entry.key] = entry.value + 1;
      }
      _dedupeIndex[key] = 0;

      if (recentDetections.length > maxRecentDetections) {
        int evictIdx = recentDetections.length - 1;
        // Scan backwards for a wardrive entry to evict first
        for (int i = recentDetections.length - 1; i >= maxRecentDetections ~/ 2; i--) {
          if (recentDetections[i].engine == Engine.wardrive) {
            evictIdx = i;
            break;
          }
        }
        final removed = recentDetections.removeAt(evictIdx);
        final removedKey = '${removed.macAddress}|${removed.engine.name}';
        _dedupeIndex.remove(removedKey);
        // Fix indices after removal
        for (final entry in _dedupeIndex.entries) {
          if (entry.value > evictIdx) {
            _dedupeIndex[entry.key] = entry.value - 1;
          }
        }
      }
    }
  }

  /// Remove a detection from the feed by its ID.
  void removeDetection(String id) {
    final idx = recentDetections.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    final removed = recentDetections.removeAt(idx);
    final key = '${removed.macAddress}|${removed.engine.name}';
    _dedupeIndex.remove(key);
    // Fix indices after removal
    for (final entry in _dedupeIndex.entries) {
      if (entry.value > idx) {
        _dedupeIndex[entry.key] = entry.value - 1;
      }
    }
    notifyListeners();
  }

  void removeDetectionGroup(Detection d) {
    final uav = d.odid?.uavId;
    final byUav = uav != null && uav.isNotEmpty;
    final macs = <String>{};
    recentDetections.removeWhere((x) {
      final match =
          byUav ? (x.odid?.uavId == uav) : (x.macAddress == d.macAddress);
      if (match) macs.add(x.macAddress);
      return match;
    });
    if (byUav) {
      _droneTracks.remove(uav);
      _pilotTracks.remove(uav);
    }
    for (final m in macs) {
      _droneTracks.remove(m);
      _pilotTracks.remove(m);
      for (final s in _uniqueMacsPerEngine.values) {
        s.remove(m);
      }
    }
    _rebuildDedupeIndex();
    notifyListeners();
  }

  void _rebuildDedupeIndex() {
    _dedupeIndex.clear();
    for (var i = 0; i < recentDetections.length; i++) {
      final dd = recentDetections[i];
      _dedupeIndex['${dd.macAddress}|${dd.engine.name}'] = i;
    }
  }

  Future<void> enableMesh({
    required bool encryption,
    required List<Uint8List> peerMacs,
  }) async {
    if (_meshKey == null || _meshKey!.length != 32) {
      await generateMeshKey();
    }
    meshEncryption = encryption;
    meshEnabled = true;
    await _ble.writeMeshConfig(
      enabled: true,
      encryption: encryption,
      key: _meshKey!,
      peerMacs: peerMacs,
    );
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setBool('meshAutoEnable', true));
    DebugLog.log('AppState: mesh enabled, peers=${peerMacs.length}');
  }

  Future<void> _restoreHardwareConfig() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('hwConfigSaved') != true) return;
    try {
      await _ble.writeHardwareConfig(
        buzzer: p.getBool('hwBuzzerEnabled') ?? true,
        led: p.getBool('hwLedEnabled') ?? true,
        neopixelBrightness: p.getInt('neopixelBrightness') ?? 50,
        buzzerVolume: p.getInt('hwBuzzerVolume') ?? 100,
        extendedOui: p.getBool('hwFlockExtendedOui') ?? false,
        offlineScan: p.getBool('offlineScanEnabled') ?? false,
      );
      DebugLog.log('AppState: connection ready — restored saved hardware config');
    } catch (e) {
      DebugLog.log('AppState: hardware config restore failed: $e');
    }
  }

  Future<void> disableMesh() async {
    meshEnabled = false;
    SharedPreferences.getInstance().then((p) => p.setBool('meshAutoEnable', false));
    await _ble.writeMeshConfig(
      enabled: false,
      encryption: false,
      key: Uint8List(32),
      peerMacs: [],
    );
    notifyListeners();
    DebugLog.log('AppState: mesh disabled');
  }

  Future<void> generateMeshKey() async {
    final rng = Random.secure();
    _meshKey = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'mesh_encryption_key',
      value: _meshKey!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    DebugLog.log('AppState: new mesh key generated');
    notifyListeners();
  }

  Future<void> loadMeshKey() async {
    const storage = FlutterSecureStorage();
    final hex = await storage.read(key: 'mesh_encryption_key');
    if (hex != null && hex.length == 64) {
      _meshKey = Uint8List.fromList(
        List.generate(32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
      );
    }
  }

  List<Detection> detectionsForNode(String sourceNodeId) {
    return recentDetections.where((d) => d.sourceNodeId == sourceNodeId).toList();
  }

  void resetCounts() {
    _uniqueMacsPerEngine.clear();
    recentDetections.clear();
    _dedupeIndex.clear();
    _droneTracks.clear();
    _pilotTracks.clear();
    notifyListeners();
  }

  static String droneTrackKey(Detection d) {
    final id = d.odid?.uavId;
    return (id != null && id.isNotEmpty) ? id : d.macAddress;
  }

  void _recordDroneTrack(Detection det) {
    if (det.engine != Engine.skySpy) return;
    final o = det.odid;
    if (o == null) return;
    final key = droneTrackKey(det);
    _appendTrack(_droneTracks, key, o.droneLat, o.droneLon);
    _appendTrack(_pilotTracks, key, o.pilotLat, o.pilotLon);
  }

  void _appendTrack(
      Map<String, List<LatLng>> tracks, String mac, double? lat, double? lon) {
    if (lat == null || lon == null) return;
    if (lat == 0 && lon == 0) return;
    if (lat.isNaN || lon.isNaN) return;
    if (lat.abs() > 90 || lon.abs() > 180) return;
    final track = tracks.putIfAbsent(mac, () => <LatLng>[]);
    if (track.isNotEmpty) {
      final last = track.last;
      if ((last.latitude - lat).abs() < 1e-6 &&
          (last.longitude - lon).abs() < 1e-6) {
        return;
      }
    }
    track.add(LatLng(lat, lon));
    if (track.length > _maxTrackPoints) {
      track.removeRange(0, track.length - _maxTrackPoints);
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}

final appStateProvider = ChangeNotifierProvider<AppState>((ref) {
  final ble = ref.watch(bleManagerProvider);
  final gps = ref.watch(gpsProvider);
  final allowlist = ref.watch(ignoreListProvider);
  final geofence = ref.read(geofenceFilterProvider);
  final notif = ref.watch(notificationServiceProvider);
  final liveActivity = ref.watch(liveActivityServiceProvider);
  return AppState(ble, gps, allowlist, geofence, notif, liveActivity);
});
