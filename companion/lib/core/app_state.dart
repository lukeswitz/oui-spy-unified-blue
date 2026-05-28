import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
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
  AppState(this._ble, this._gps, this._ignoreList, this._notificationService, this._liveActivity) {
    _init();
  }

  final BleManager _ble;
  final GpsProvider _gps;
  final IgnoreListState _ignoreList;
  final NotificationService _notificationService;
  final LiveActivityService _liveActivity;
  final List<StreamSubscription<dynamic>> _subs = [];

  // Connection
  NodeConnectionState connectionState = NodeConnectionState.disconnected;
  bool get isConnected => connectionState == NodeConnectionState.ready;
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
  final Map<String, int> _dedupeIndex = {}; // "mac|engine" → index in list
  static const int maxRecentDetections = 500;

  // Foxhunter
  int foxhunterRssi = -100;
  int foxhunterIntervalMs = 3000;
  String? foxhunterTarget;

  int foxhunterChannel = 0;

  void setFoxhunterTarget(String mac, {int channel = 0}) {
    foxhunterTarget = mac;
    foxhunterChannel = channel;
    // Only enable engine if not already running — avoid DISABLE/ENABLE spam
    if (!isEngineActive(Engine.foxhunter)) {
      _ble.enableEngine(Engine.foxhunter, radio: engineRadio[Engine.foxhunter] ?? 0x03);
    }
    // Always send target (even if already running — updates MAC + channel hint)
    _ble.setFoxhunterTarget(mac, channel: channel);
    notifyListeners();
  }

  void clearFoxhunterTarget() {
    foxhunterTarget = null;
    foxhunterChannel = 0;
    foxhunterRssi = -100;
    foxhunterIntervalMs = 3000;
    _ble.disableEngine(Engine.foxhunter);
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

  Set<String> get meshSourceNodes {
    final nodes = <String>{};
    for (final d in recentDetections) {
      if (d.sourceNodeId.isNotEmpty) nodes.add(d.sourceNodeId);
    }
    return nodes;
  }

  Map<String, int> get detectionsPerSourceNode {
    final m = <String, int>{};
    for (final d in recentDetections) {
      final k = d.sourceNodeId.isEmpty ? 'LOCAL' : d.sourceNodeId;
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  String labelForNode(String id) {
    final prefs = _nodeLabels;
    final stored = prefs[id];
    if (stored != null && stored.isNotEmpty) return stored;
    if (id == 'LOCAL' || id.isEmpty) return 'LOCAL';
    return id;
  }

  final Map<String, String> _nodeLabels = {};
  void setNodeLabel(String id, String label) {
    if (label.isEmpty) {
      _nodeLabels.remove(id);
    } else {
      _nodeLabels[id] = label;
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
    final entries = p.getStringList('nodeLabels') ?? const [];
    for (final e in entries) {
      final i = e.indexOf('=');
      if (i > 0) _nodeLabels[e.substring(0, i)] = e.substring(i + 1);
    }
  }

  void _init() {
    // Connection state
    connectionState = _ble.currentConnectionState;

    _subs.add(_ble.connectionState.listen((state) {
      connectionState = state;
      if (state == NodeConnectionState.ready) {
        nodeId = _ble.nodeId;
        sessionStartTime = DateTime.now();
        _gps.start().catchError((e) {
          DebugLog.log('GPS: start failed from BLE connect: $e');
          return false;
        });
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
      final isNewMac = !(_uniqueMacsPerEngine[det.engine]?.contains(det.macAddress) ?? false);
      (_uniqueMacsPerEngine[det.engine] ??= {}).add(det.macAddress);
      lastDetectionTime[det.engine] = DateTime.now();
      (_recentDetectionTimes[det.engine] ??= []).add(DateTime.now());
      _upsertDetection(det);

      // Fire notification only for first-seen MACs per engine
      if (isNewMac) {
        _notificationService.onDetection(det);
      }

      notifyListeners();
    }));

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
          uniqueCount: totalDetections,
          targetMac: foxhunterTarget!,
          rssi: data.rssi,
          intervalMs: data.intervalMs,
        );
      }

      notifyListeners();
    }));

    // Mesh status
    _subs.add(_ble.meshStatusUpdates.listen((data) {
      meshEnabled = data.enabled;
      meshPeerCount = data.peerCount;
      meshConnectedPeers = data.connectedPeers;
      meshRxCount = data.rxCount;
      meshTxCount = data.txCount;
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
    return recentDetections.where((d) => d.engine == engine).toList();
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

  Uint8List? get meshKey => _meshKey;

  List<Detection> detectionsForNode(String sourceNodeId) {
    return recentDetections.where((d) => d.sourceNodeId == sourceNodeId).toList();
  }

  void resetCounts() {
    _uniqueMacsPerEngine.clear();
    recentDetections.clear();
    _dedupeIndex.clear();
    notifyListeners();
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
  final notif = ref.watch(notificationServiceProvider);
  final liveActivity = ref.watch(liveActivityServiceProvider);
  return AppState(ble, gps, allowlist, notif, liveActivity);
});
