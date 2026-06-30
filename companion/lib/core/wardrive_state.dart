import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection, Session;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/models/session.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum WardriveState { idle, running, paused }

enum WardriveTarget {
  flock('FLOCK', 'Flock Safety cameras', Icons.videocam),
  drone('DRONE', 'FAA Remote ID drones', Icons.flight),
  wigle('WIGLE', 'All networks (WiGLE)', Icons.wifi_find),
  detector('DETECT', 'Watchlist devices', Icons.radar),
  wigleFlock('WIGLE+FLOCK', 'All networks + Flock', Icons.hub);

  const WardriveTarget(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;

  Color get color => switch (this) {
    WardriveTarget.flock => const Color(0xFFB44AFF),
    WardriveTarget.drone => const Color(0xFF4AFFEA),
    WardriveTarget.wigle => const Color(0xFFFFAA4A),
    WardriveTarget.detector => const Color(0xFF4A9EFF),
    WardriveTarget.wigleFlock => const Color(0xFF4A9EFF),
  };

  List<Engine> engines(WardriveRadio radio) => switch (this) {
    WardriveTarget.flock => switch (radio) {
      WardriveRadio.wifi => [Engine.flockWifi],
      WardriveRadio.ble => [Engine.flockBle],
      WardriveRadio.both => [Engine.flockWifi, Engine.flockBle],
    },
    WardriveTarget.drone => [Engine.skySpy],
    WardriveTarget.wigle => [Engine.wardrive],
    WardriveTarget.detector => [Engine.detector],
    WardriveTarget.wigleFlock => switch (radio) {
      WardriveRadio.wifi => [Engine.wardrive, Engine.flockWifi],
      WardriveRadio.ble => [Engine.wardrive, Engine.flockBle],
      WardriveRadio.both => [Engine.wardrive, Engine.flockBle, Engine.flockWifi],
    },
  };

  bool get hasRadioChoice => true;

  bool get usesPerNodeRadio => this == wigle || this == wigleFlock;

  Engine? get radioMaskEngine => switch (this) {
    WardriveTarget.wigle || WardriveTarget.wigleFlock => Engine.wardrive,
    WardriveTarget.detector => Engine.detector,
    WardriveTarget.drone => Engine.skySpy,
    WardriveTarget.flock => null,
  };

  /// Whether this target includes flock detection engines.
  bool get includesFlock => this == flock || this == wigleFlock;
}

enum WardriveRadio {
  wifi('WiFi'), ble('BLE'), both('WiFi+BLE');
  const WardriveRadio(this.label);
  final String label;
}

Set<WardriveTarget> targetsFromEngineMask(int mask) {
  final targets = <WardriveTarget>{};
  if ((mask & (Engine.flockWifi.bitmask | Engine.flockBle.bitmask)) != 0) {
    targets.add(WardriveTarget.flock);
  }
  if ((mask & Engine.skySpy.bitmask) != 0) targets.add(WardriveTarget.drone);
  if ((mask & Engine.detector.bitmask) != 0) targets.add(WardriveTarget.detector);
  return targets;
}

class WardriveController extends ChangeNotifier {
  WardriveController(this._ble, this._gps, this._db, this._ignoreList, this._geofenceFilter, this._notificationService, this._liveActivity) {
    _connSub = _ble.connectionState.listen((connState) {
      if (connState == NodeConnectionState.ready) {
        SharedPreferences.getInstance().then(
            (p) => offlineGpsTag = p.getBool('offlineGpsTagEnabled') ?? false);
        _adoptFirmwareState();
      }
    });
    _importedDetSub = _ble.importedDetections.listen(_onImportedDetection);
    _awayLiveSub = _ble.awayLiveDetections.listen(_onAwayLiveDetection);
    _spoolImportSub = _ble.spoolImport.listen(_onSpoolProgress);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    offlineGpsTag = p.getBool('offlineGpsTagEnabled') ?? false;
    _wifiRssiRelogDb = p.getInt('wd_wifiRssiRelog') ?? 20;
    _bleRssiRelogDb = p.getInt('wd_bleRssiRelog') ?? 15;
    _wifiScanInterval = p.getInt('wd_wifiScanInterval') ?? 250;
    _wifiDwellPerCh = p.getInt('wd_wifiDwellPerCh') ?? 110;
    _bleScanDuration = p.getInt('wd_bleScanDuration') ?? 800;
    _bleScanInterval = p.getInt('wd_bleScanInterval') ?? 3000;
    _channelStart = p.getInt('wd_channelStart') ?? 1;
    _channelEnd = p.getInt('wd_channelEnd') ?? 14;
    if (!(p.getBool('wd_dwellFastReset_v2') ?? false)) {
      _wifiScanInterval = 250;
      _wifiDwellPerCh = 110;
      await p.setInt('wd_wifiScanInterval', _wifiScanInterval);
      await p.setInt('wd_wifiDwellPerCh', _wifiDwellPerCh);
      await p.setBool('wd_dwellFastReset_v2', true);
    }
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    p.setInt('wd_wifiRssiRelog', _wifiRssiRelogDb);
    p.setInt('wd_bleRssiRelog', _bleRssiRelogDb);
    p.setInt('wd_wifiScanInterval', _wifiScanInterval);
    p.setInt('wd_wifiDwellPerCh', _wifiDwellPerCh);
    p.setInt('wd_bleScanDuration', _bleScanDuration);
    p.setInt('wd_bleScanInterval', _bleScanInterval);
    p.setInt('wd_channelStart', _channelStart);
    p.setInt('wd_channelEnd', _channelEnd);
  }

  /// Map a radio mask (0x01/0x02/0x03) to the [WardriveRadio] enum.
  static WardriveRadio radioFromMask(int mask) => switch (mask & 0x03) {
    0x01 => WardriveRadio.wifi,
    0x02 => WardriveRadio.ble,
    _ => WardriveRadio.both,
  };

  final BleManager _ble;
  final GpsProvider _gps;
  final AppDatabase _db;
  final IgnoreListState _ignoreList;
  final GeofenceFilter _geofenceFilter;
  final NotificationService _notificationService;
  final LiveActivityService _liveActivity;
  StreamSubscription<NodeConnectionState>? _connSub;
  StreamSubscription<Detection>? _importedDetSub;
  StreamSubscription<Detection>? _awayLiveSub;
  StreamSubscription<SpoolImportProgress>? _spoolImportSub;
  String? _spoolSessionId;
  int _spoolInserted = 0;
  int _spoolExpectedTotal = -1;
  bool _spoolDone = false;
  bool _spoolConfirmed = false;

  /// Imperial-units flag mirrored from [unitSystemProvider]. Used by
  /// [_updateLiveActivity] so the iOS Live Activity matches the in-app setting.
  bool isImperial = false;

  /// When on, while-away detections (spool import + node-relayed away-live) that
  /// arrive with no GPS are tagged with the phone's last-known position and
  /// flagged approximate. Gated by the Offline Scan sub-toggle.
  bool offlineGpsTag = false;

  WardriveState state = WardriveState.idle;
  final Set<WardriveTarget> selectedTargets = {};
  static const List<WardriveTarget> selectableTargets = [
    WardriveTarget.flock,
    WardriveTarget.drone,
    WardriveTarget.wigle,
    WardriveTarget.detector,
  ];
  bool isTargetSelected(WardriveTarget t) => selectedTargets.contains(t);
  WardriveTarget get primaryTarget {
    for (final t in selectableTargets) {
      if (selectedTargets.contains(t)) return t;
    }
    return WardriveTarget.wigle;
  }
  WardriveTarget get target => primaryTarget;
  bool get includesFlock => selectedTargets.any((t) => t.includesFlock);
  String get activeLabel => selectableTargets
      .where(selectedTargets.contains)
      .map((t) => t.label)
      .join(' + ');
  WardriveRadio radio = WardriveRadio.both;
  bool flockFilter = false;
  bool detectorFilter = false;
  double _markerDistanceM = 10.0;

  int _wifiRssiRelogDb = 20;
  int get wifiRssiRelogDb => _wifiRssiRelogDb;
  set wifiRssiRelogDb(int v) { _wifiRssiRelogDb = v; notifyListeners(); _savePrefs(); }

  int _bleRssiRelogDb = 15;
  int get bleRssiRelogDb => _bleRssiRelogDb;
  set bleRssiRelogDb(int v) { _bleRssiRelogDb = v; notifyListeners(); _savePrefs(); }

  int _wifiScanInterval = 250;
  int get wifiScanInterval => _wifiScanInterval;
  set wifiScanInterval(int v) { _wifiScanInterval = v; notifyListeners(); _savePrefs(); }

  int _wifiDwellPerCh = 110;
  int get wifiDwellPerCh => _wifiDwellPerCh;
  set wifiDwellPerCh(int v) { _wifiDwellPerCh = v; notifyListeners(); _savePrefs(); }

  int _bleScanDuration = 800;
  int get bleScanDuration => _bleScanDuration;
  set bleScanDuration(int v) { _bleScanDuration = v; notifyListeners(); _savePrefs(); }

  int _bleScanInterval = 3000;
  int get bleScanInterval => _bleScanInterval;
  set bleScanInterval(int v) { _bleScanInterval = v; notifyListeners(); _savePrefs(); }

  int _channelStart = 1;
  int get channelStart => _channelStart;
  set channelStart(int v) { _channelStart = v.clamp(1, 14); notifyListeners(); _savePrefs(); }

  int _channelEnd = 14;
  int get channelEnd => _channelEnd;
  set channelEnd(int v) { _channelEnd = v.clamp(_channelStart, 14); notifyListeners(); _savePrefs(); }

  double get markerDistanceM => _markerDistanceM;
  set markerDistanceM(double v) {
    _markerDistanceM = v;
    notifyListeners();
  }

  int rawWifiCount = 0;
  int rawBleCount = 0;

  /// Per-source-node WiFi/BLE detection counts for overlay display.
  final Map<String, int> nodeWifiCounts = {};
  final Map<String, int> nodeBleCount = {};

  List<Engine> get activeEngines {
    final set = <Engine>{};
    for (final t in selectedTargets) {
      set.addAll(t.engines(radio));
    }
    return set.toList();
  }

  List<Engine> get _fleetEngines {
    if (!_ble.isManagerConnected) return activeEngines;
    final set = <Engine>{};
    for (final t in selectedTargets) {
      set.addAll(t.engines(WardriveRadio.both));
    }
    return set.toList();
  }

  /// Local-only WiFi/BLE counts (excludes peer detections).
  int get localWifiCount =>
      rawWifiCount - nodeWifiCounts.values.fold(0, (a, b) => a + b);
  int get localBleCount =>
      rawBleCount - nodeBleCount.values.fold(0, (a, b) => a + b);

  Map<String, int> get detectionsPerNode {
    final m = <String, int>{};
    for (final k in {...nodeWifiCounts.keys, ...nodeBleCount.keys}) {
      m[k] = (nodeWifiCounts[k] ?? 0) + (nodeBleCount[k] ?? 0);
    }
    return m;
  }

  String? foxhuntTarget;
  String sessionId = '';

  /// Pending zoom target set from other screens (e.g. feed tap).
  /// Consumed once by the wardrive map, then cleared.
  LatLng? pendingZoomTarget;

  /// Request the wardrive map to zoom to a specific location.
  void requestZoom(double lat, double lon) {
    pendingZoomTarget = LatLng(lat, lon);
    notifyListeners();
  }

  /// Consume the pending zoom target (called by wardrive screen after moving camera).
  LatLng? consumeZoomTarget() {
    final target = pendingZoomTarget;
    pendingZoomTarget = null;
    return target;
  }

  DateTime? startTime;
  final Map<String, Detection> _dedupedByMac = {};
  final List<Detection> _dedupedOrdered = [];
  List<Detection> get detections => _dedupedOrdered;
  int rawDetectionCount = 0;
  final Set<String> uniqueMacs = {};
  final Set<String> _wifiNetworkMacs = {};
  final Set<String> _flockMacs = {};
  final Map<String, Detection> _flockByMac = {};
  List<Detection>? _cachedFlockDetections;
  final Set<String> _detectorMacs = {};
  final Map<String, Detection> _detectorByMac = {};
  List<Detection>? _cachedDetectorDetections;
  final List<LatLng> routePoints = [];
  double distanceKm = 0;
  /// Median coord of the active/loaded session. Used to reject GPS outliers
  /// (e.g. a fix that lands in Antarctica when the rest of the session is in
  /// California). Null when no plausible coords have been seen yet.
  LatLng? sessionCenter;
  double _sessionOutlierKm = 200.0;
  GpsPosition? lastGpsForDistance;
  GpsPosition? currentPosition;
  int get droneCount => droneDetections.length;

  List<WatchlistEntry> Function()? _watchlistGetter;
  void setWatchlistGetter(List<WatchlistEntry> Function() g) {
    _watchlistGetter = g;
  }

  String? _rescanSessionId;
  int _rescanCur = 0;
  int _rescanTotal = 0;
  int _rescanNewDetector = 0;
  int _rescanNewFlock = 0;
  String? get rescanSessionId => _rescanSessionId;
  int get rescanCur => _rescanCur;
  int get rescanTotal => _rescanTotal;
  int get rescanNewDetector => _rescanNewDetector;
  int get rescanNewFlock => _rescanNewFlock;

  List<Detection> get dedupedDetections => _dedupedOrdered;

  StreamSubscription<Detection>? _detSub;
  StreamSubscription<GpsPosition>? _gpsSub;
  Timer? _statsTimer;
  bool _inExclusion = false;
  bool get inExclusion => _inExclusion;
  Set<Engine> _pausedByExclusion = {};
  bool _autoPcapPausedByExclusion = false;

  bool get isRunning => state == WardriveState.running;
  bool get isActive => state != WardriveState.idle;
  int get flockCount => _flockMacs.length;
  int get detectorCount => _detectorMacs.length;

  List<Detection> get flockDetections {
    if (_cachedFlockDetections != null) return _cachedFlockDetections!;
    final list = _flockByMac.values.toList();
    list.sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
    _cachedFlockDetections = list;
    return list;
  }

  List<Detection> get detectorDetections {
    if (_cachedDetectorDetections != null) return _cachedDetectorDetections!;
    final list = _detectorByMac.values.toList();
    list.sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
    _cachedDetectorDetections = list;
    return list;
  }

  bool get includesDrone =>
      selectedTargets.any((t) => t.engines(radio).contains(Engine.skySpy));

  bool get includesDetector =>
      selectedTargets.any((t) => t.engines(radio).contains(Engine.detector));

  List<Detection> get droneDetections {
    final byKey = <String, Detection>{};
    for (final d in _dedupedOrdered) {
      if (d.engine != Engine.skySpy) continue;
      final id = (d.odid?.uavId?.isNotEmpty ?? false)
          ? d.odid!.uavId!
          : d.macAddress;
      final ex = byKey[id];
      if (ex == null ||
          odidCompleteness(d.odid) > odidCompleteness(ex.odid)) {
        byKey[id] = d;
      }
    }
    final list = byKey.values.toList();
    list.sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
    return list;
  }

  void toggleTarget(WardriveTarget t) {
    if (isActive) return;
    if (selectedTargets.contains(t)) {
      if (selectedTargets.length > 1) selectedTargets.remove(t);
    } else {
      selectedTargets.add(t);
    }
    notifyListeners();
  }

  void setTarget(WardriveTarget t) {
    if (isActive) return;
    selectedTargets
      ..clear()
      ..add(t);
    notifyListeners();
  }

  void setRadio(WardriveRadio r) {
    if (isActive) return;
    radio = r;
    notifyListeners();
  }

  /// Stop a single engine that the active wardrive session owns (e.g. user
  /// toggled its card off on the home screen). Drops the owning target(s) and
  /// disables the engine(s) that only those targets needed; if nothing is left
  /// to scan, tears down the whole session. Keeps [selectedTargets] intact for
  /// the next run when the session is stopped.
  Future<void> stopOwnedEngine(Engine e) async {
    if (!isActive) return;
    if (e == Engine.wardrive) {
      await stopSession();
      return;
    }
    final removed = selectedTargets.where((t) => t.engines(radio).contains(e)).toSet();
    if (removed.isEmpty) {
      try {
        await _ble.disableEngine(e);
      } catch (err) {
        DebugLog.log('WARDRIVE: stopOwnedEngine $e error: $err');
      }
      return;
    }
    final remaining = selectedTargets.where((t) => !removed.contains(t)).toSet();
    if (remaining.isEmpty) {
      await stopSession();
      return;
    }
    final keep = <Engine>{};
    for (final t in remaining) {
      keep.addAll(t.engines(radio));
    }
    final toStop = <Engine>{};
    for (final t in removed) {
      toStop.addAll(t.engines(radio));
    }
    toStop.removeAll(keep);
    selectedTargets
      ..clear()
      ..addAll(remaining);
    for (final eng in toStop) {
      try {
        await _ble.disableEngine(eng);
      } catch (err) {
        DebugLog.log('WARDRIVE: stopOwnedEngine $eng error: $err');
      }
    }
    notifyListeners();
  }

  /// Remove every map/session member of the same logical detection as [d]
  /// (by UAS-ID for Remote-ID drones, else by MAC) from the in-memory overlay
  /// and from the database, so a deleted drone/device does not reappear.
  Future<void> removeDetectionGroup(Detection d) async {
    final uav = d.odid?.uavId;
    final byUav = uav != null && uav.isNotEmpty;
    final macs = <String>{};
    final keys = <String>[];
    _dedupedByMac.forEach((k, det) {
      final match =
          byUav ? (det.odid?.uavId == uav) : (det.macAddress == d.macAddress);
      if (match) {
        keys.add(k);
        macs.add(det.macAddress);
      }
    });
    for (final k in keys) {
      final det = _dedupedByMac.remove(k);
      if (det != null) _dedupedOrdered.remove(det);
    }
    for (final m in macs) {
      _flockByMac.remove(m);
      _detectorByMac.remove(m);
      _flockMacs.remove(m);
      _detectorMacs.remove(m);
      uniqueMacs.remove(m);
    }
    _cachedFlockDetections = null;
    _cachedDetectorDetections = null;
    final sid = sessionId.isNotEmpty ? sessionId : (_lastCompletedSessionId ?? '');
    if (sid.isNotEmpty && macs.isNotEmpty) {
      try {
        await _db.deleteDetectionsByMacs(sid, macs.toList());
      } catch (e) {
        DebugLog.log('WARDRIVE: deleteDetectionsByMacs failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> startSession() async {
    final gpsOk = await _gps.start();
    if (!gpsOk) {
      DebugLog.log('WARDRIVE: GPS failed to start — check permissions/services');
    }

    startTime = DateTime.now();
    sessionId = const Uuid().v4();
    _dedupedOrdered.clear();
    _dedupedByMac.clear();
    rawDetectionCount = 0;
    rawWifiCount = 0;
    rawBleCount = 0;
    nodeWifiCounts.clear();
    nodeBleCount.clear();
    uniqueMacs.clear();
    _wifiNetworkMacs.clear();
    _flockMacs.clear();
    _flockByMac.clear();
    _cachedFlockDetections = null;
    _detectorMacs.clear();
    _detectorByMac.clear();
    _cachedDetectorDetections = null;
    routePoints.clear();
    distanceKm = 0;    lastGpsForDistance = null;
    foxhuntTarget = null;

    // Reload geofence exclusion zones at session start
    await _geofenceFilter.reload();
    _notificationService.resetMilestones();

    _db.insertSession(SessionsCompanion(
      id: drift.Value(sessionId),
      name: drift.Value('Wardrive ${DateTime.now().toIso8601String().substring(0, 16)}'),
      nodeId: const drift.Value('default'),
      startedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
      isWardrive: const drift.Value(true),
    ));

    state = WardriveState.running;

    _detSub = _ble.detections.listen(_onDetection);
    _gpsSub = _gps.positionStream.listen(_onGpsUpdate);
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());

    final cached = _gps.lastPosition;
    if (cached != null) {
      currentPosition = cached;
    }

    await _enableEnginesSequentially(_fleetEngines);

    WakelockPlus.enable();

    // Start iOS Live Activity (Dynamic Island / Lock Screen)
    _updateLiveActivity();

    notifyListeners();
    DebugLog.log('WARDRIVE: started $sessionId targets=$activeLabel radio=${radio.label}');
  }

  Future<void> stopSession() async {
    state = WardriveState.idle;
    notifyListeners();

    _detSub?.cancel();
    _gpsSub?.cancel();
    _statsTimer?.cancel();
    _detSub = null;
    _gpsSub = null;
    _statsTimer = null;

    const wardriveEngines = [
      Engine.wardrive,
      Engine.flockWifi,
      Engine.flockBle,
      Engine.skySpy,
      Engine.detector,
      Engine.pcap,
    ];
    try {
      for (final engine in wardriveEngines) {
        try {
          await _ble.disableEngine(engine);
        } catch (e) {
          DebugLog.log('WARDRIVE: disable $engine error: $e');
        }
      }
    } finally {
      WakelockPlus.disable();
      _liveActivity.end();
    }

    if (sessionId.isNotEmpty && startTime != null) {
      _db.updateSession(SessionsCompanion(
        id: drift.Value(sessionId),
        endedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
        detectionCount: drift.Value(detections.length),
        uniqueMacCount: drift.Value(uniqueMacs.length),
        distanceKm: drift.Value(distanceKm),
      ));

      await _saveCsv(sessionId, detections);

      DebugLog.log('WARDRIVE: saved $sessionId (${detections.length} det, ${uniqueMacs.length} unique, ${_flockMacs.length} flock)');

      final wl = _watchlistGetter?.call() ?? const <WatchlistEntry>[];
      _rescanSessionId = sessionId;
      _rescanCur = 0;
      _rescanTotal = detections.length;
      _rescanNewDetector = 0;
      _rescanNewFlock = 0;
      notifyListeners();
      try {
        final res = await WigleCsvRescan.rescanSession(
          _db,
          sessionId,
          watchlist: wl,
          onProgress: (cur, total, newDet, newFlock) {
            _rescanCur = cur;
            _rescanTotal = total;
            _rescanNewDetector = newDet;
            _rescanNewFlock = newFlock;
            notifyListeners();
          },
        );
        DebugLog.log(
            'WARDRIVE: rescan $sessionId scanned=${res.rowsScanned} updated=${res.rowsUpdated} det=${res.newDetectorMacs} flock=${res.newFlockMacs}');
      } catch (e) {
        DebugLog.log('WARDRIVE: rescan failed $e');
      }
      _rescanSessionId = null;
      notifyListeners();
    }

    _lastCompletedSessionId = sessionId;
    notifyListeners();
  }

  /// Session ID of the most recently completed or loaded session.
  String? _lastCompletedSessionId;
  String? get lastCompletedSessionId => _lastCompletedSessionId;

  /// ID of the currently loaded (viewed) session on the map.
  String? get loadedSessionId => !isActive ? _lastCompletedSessionId : null;

  /// Clear the loaded session from the map (e.g., after deletion).
  void clearLoadedSession() => clearMapData();

  /// Whether we have map data from a completed/loaded session.
  bool get hasSessionData =>
      routePoints.isNotEmpty || detections.isNotEmpty;

  /// Clear map overlay from a completed/loaded session.
  void clearMapData() {
    _dedupedOrdered.clear();
    _dedupedByMac.clear();
    routePoints.clear();
    uniqueMacs.clear();
    _flockMacs.clear();
    _flockByMac.clear();
    _cachedFlockDetections = null;
    _detectorMacs.clear();
    _detectorByMac.clear();
    _cachedDetectorDetections = null;
    rawDetectionCount = 0;
    nodeWifiCounts.clear();
    nodeBleCount.clear();
    distanceKm = 0;    flockFilter = false;
    detectorFilter = false;
    _lastCompletedSessionId = null;
    sessionCenter = null;
    notifyListeners();
  }

  /// True when (lat, lon) is inside the loaded session's outlier radius.
  /// Always true when no session center is known (live capture, empty session).
  bool isWithinSession(double lat, double lon) {
    final c = sessionCenter;
    if (c == null) return true;
    final d = _haversineKm(c.latitude, c.longitude, lat, lon);
    return d.isFinite && d <= _sessionOutlierKm;
  }

  /// Load a previously saved wardrive session onto the map.
  Future<void> loadSession(String sid) async {
    if (isActive) return;

    final dbRows = await _db.getDetectionMapsForSession(sid);
    _dedupedOrdered.clear();
    _dedupedByMac.clear();
    _flockByMac.clear();
    _cachedFlockDetections = null;
    _detectorByMac.clear();
    _cachedDetectorDetections = null;
    _detectorMacs.clear();
    rawDetectionCount = 0;
    rawWifiCount = 0;
    rawBleCount = 0;
    nodeWifiCounts.clear();
    nodeBleCount.clear();
    uniqueMacs.clear();
    _flockMacs.clear();
    routePoints.clear();
    distanceKm = 0;    lastGpsForDistance = null;
    foxhuntTarget = null;

    final lats = <double>[];
    final lons = <double>[];
    for (final row in dbRows) {
      final det = _detectionFromDb(row);
      rawDetectionCount++;
      uniqueMacs.add(det.macAddress);
      final isFlock =
          det.engine == Engine.flockBle || det.engine == Engine.flockWifi;
      if (isFlock) {
        _flockMacs.add(det.macAddress);
        _flockByMac[det.macAddress] = det;
      }
      if (det.engine == Engine.detector) {
        _detectorMacs.add(det.macAddress);
        _detectorByMac[det.macAddress] = det;
      }

      final key = '${det.macAddress}|${det.engine.name}';
      final existing = _dedupedByMac[key];
      if (existing != null) {
        _dedupedByMac[key] = existing.copyWith(
          count: existing.count + 1,
          rssi: det.rssi > existing.rssi ? det.rssi : existing.rssi,
        );
      } else {
        _dedupedByMac[key] = det;
      }

      if (_isPlausibleCoord(det.latitude, det.longitude)) {
        lats.add(det.latitude!);
        lons.add(det.longitude!);
      }
    }

    LatLng? center;
    if (lats.isNotEmpty) {
      final ls = List<double>.from(lats)..sort();
      final os = List<double>.from(lons)..sort();
      center = LatLng(ls[ls.length ~/ 2], os[os.length ~/ 2]);
    }
    sessionCenter = center;
    const outlierKm = 200.0;
    const minRoutePointSepKm = 0.005; // ~5m
    final anchor = center;
    bool inRange(double lat, double lon) =>
        anchor == null ||
        _haversineKm(anchor.latitude, anchor.longitude, lat, lon) <= outlierKm;

    // Pass 2: build ordered detection list (no shifts) + downsampled route.
    _dedupedOrdered
      ..clear()
      ..addAll(_dedupedByMac.values.toList().reversed);

    double? lastRouteLat;
    double? lastRouteLon;
    for (final det in _dedupedByMac.values) {
      if (!_isPlausibleCoord(det.latitude, det.longitude)) continue;
      final lat = det.latitude!;
      final lon = det.longitude!;
      if (!inRange(lat, lon)) continue;
      if (lastRouteLat == null) {
        routePoints.add(LatLng(lat, lon));
        lastRouteLat = lat;
        lastRouteLon = lon;
      } else {
        final stepKm = _haversineKm(lastRouteLat, lastRouteLon!, lat, lon);
        if (stepKm.isFinite && stepKm >= minRoutePointSepKm) {
          routePoints.add(LatLng(lat, lon));
          distanceKm += stepKm;
          lastRouteLat = lat;
          lastRouteLon = lon;
        }
      }
    }
    _sessionOutlierKm = outlierKm;

    // Load session metadata for start time display.
    final sessionRow = await _db.getSessionById(sid);
    if (sessionRow != null) {
      startTime = DateTime.fromMillisecondsSinceEpoch(
        (sessionRow as dynamic).startedAt as int,
      );
    }

    sessionId = sid;
    _lastCompletedSessionId = sid;
    notifyListeners();
    DebugLog.log('WARDRIVE: loaded session $sid (${detections.length} det, ${routePoints.length} pts)');
  }

  /// Convert a detection map (from `getDetectionMapsForSession`) to our model.
  Detection _detectionFromDb(Map<String, dynamic> row) {
    final engineName = row['engine'] as String;
    final engine = Engine.values.firstWhere(
      (e) => e.name == engineName,
      orElse: () => Engine.wardrive,
    );

    final ssid = (row['ssid'] as String?) ?? '';
    final authMode = (row['authMode'] as int?) ?? 0;
    final deviceName = (row['deviceName'] as String?) ?? '';

    return Detection(
      id: '${row['id']}',
      sessionId: row['sessionId'] as String,
      nodeId: row['nodeId'] as String,
      macAddress: row['macAddress'] as String,
      deviceName: deviceName,
      engine: engine,
      method: row['detectionMethod'] as String,
      rssi: row['rssi'] as int,
      channel: row['channel'] as int,
      deviceTimestampMs: row['deviceTimestampMs'] as int,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(row['appTimestamp'] as int),
      ssid: ssid,
      count: (row['count'] as int?) ?? 1,
      latitude: row['latitude'] as double?,
      longitude: row['longitude'] as double?,
      altitude: row['altitude'] as double?,
      speed: row['speed'] as double?,
      heading: row['heading'] as double?,
      accuracy: row['accuracy'] as double?,
      satelliteCount: row['satelliteCount'] as int?,
      approxGps: (row['approxGps'] as bool?) ?? false,
      wardrive: engine == Engine.wardrive
          ? WardriveExtension(ssid: ssid, authMode: authMode, deviceName: deviceName)
          : null,
      odid: engine == Engine.skySpy
          ? OdidExtension(
              uavId: row['uavId'] as String?,
              operatorId: row['operatorId'] as String?,
              droneLat: row['droneLat'] as double?,
              droneLon: row['droneLon'] as double?,
              altitudeMsl: row['altitudeMsl'] as int?,
              heightAgl: row['heightAgl'] as int?,
              droneSpeed: row['droneSpeed'] as int?,
              droneHeading: row['droneHeading'] as int?,
              pilotLat: row['pilotLat'] as double?,
              pilotLon: row['pilotLon'] as double?,
            )
          : null,
    );
  }

  /// Save WiGLE CSV to persistent storage.
  Future<String?> _saveCsv(String sid, List<Detection> dets) async {
    if (dets.isEmpty) return null;
    try {
      final dir = await _wardriveDir();
      final filename = await _csvFilename(sid);
      final file = File(path.join(dir.path, filename));
      final csv = WigleCsv.generate(dets, ignoreList: _ignoreList, geofenceFilter: _geofenceFilter);
      await file.writeAsString(csv);
      DebugLog.log('WARDRIVE: CSV saved ${file.path}');
      return file.path;
    } catch (e) {
      DebugLog.log('WARDRIVE: CSV save failed: $e');
      return null;
    }
  }

  /// Get CSV file for a session. Always regenerates from DB to ensure
  /// latest WiGLE format. Uses human-readable filename based on session date.
  Future<File?> getCsvFile(String sid) async {
    final dir = await _wardriveDir();
    final filename = await _csvFilename(sid);
    final file = File(path.join(dir.path, filename));
    final regenerated = await _regenerateCsvFromDb(sid, file);
    if (regenerated != null) return regenerated;
    // Fallback: check old UUID-named file
    final legacyFile = File(path.join(dir.path, '$sid.csv'));
    if (await legacyFile.exists()) return legacyFile;
    return null;
  }

  /// Build a human-readable CSV filename from session start time.
  Future<String> _csvFilename(String sid) async {
    final session = await _db.getSessionById(sid);
    if (session != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        (session as dynamic).startedAt as int,
      );
      final stamp = '${dt.year}${_pad(dt.month)}${_pad(dt.day)}_'
          '${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
      return 'ouispy_wardrive_$stamp.csv';
    }
    return 'ouispy_wardrive_$sid.csv';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Regenerate CSV from database detections when file is missing.
  Future<File?> _regenerateCsvFromDb(String sid, File file) async {
    try {
      final dbRows = await _db.getDetectionMapsForSession(sid);
      if (dbRows.isEmpty) return null;
      final dets = dbRows.map(_detectionFromDb).toList();
      final csv = WigleCsv.generate(dets, ignoreList: _ignoreList, geofenceFilter: _geofenceFilter);
      await file.writeAsString(csv);
      DebugLog.log('WARDRIVE: CSV regenerated from DB for $sid (${dets.length} det)');
      return file;
    } catch (e) {
      DebugLog.log('WARDRIVE: CSV regeneration failed: $e');
      return null;
    }
  }

  /// List all saved CSV files.
  Future<List<File>> savedCsvFiles() async {
    final dir = await _wardriveDir();
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.csv'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  static Future<Directory> _wardriveDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(docs.path, 'wardrives'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void pauseSession() {
    state = WardriveState.paused;
    notifyListeners();
  }

  void resumeSession() {
    state = WardriveState.running;
    notifyListeners();
  }

  /// Toggle flock display filter (does NOT control engines).
  void toggleDetectorFilter() {
    detectorFilter = !detectorFilter;
    notifyListeners();
  }

  void toggleFlockFilter() {
    flockFilter = !flockFilter;
    notifyListeners();
  }

  void setFoxhuntTarget(String mac, {int channel = 0}) {
    _ble.enableEngine(Engine.foxhunter);
    _ble.setFoxhunterTarget(mac, channel: channel);
    foxhuntTarget = mac;
    _updateLiveActivity();
    notifyListeners();
  }

  /// Radio bitmask for firmware config: 0x01=WiFi, 0x02=BLE, 0x03=both.
  int get radioBitmask => switch (radio) {
    WardriveRadio.wifi => 0x01,
    WardriveRadio.ble => 0x02,
    WardriveRadio.both => 0x03,
  };

  /// Enable engines one at a time with a settle delay after WiFi engines.
  /// ESP32 WiFi init can destabilize the NimBLE connection if BLE scan
  /// restarts too quickly; the resulting reconnect fires DISABLE_ALL.
  Future<void> _enableEnginesSequentially(List<Engine> engineList) async {
    for (final engine in engineList) {
      if (state == WardriveState.idle) return;
      if (engine == Engine.wardrive) {
        await _ble.sendEngineConfig(
          engine,
          Uint8List.fromList([
            radioBitmask,
            wifiScanInterval & 0xFF, (wifiScanInterval >> 8) & 0xFF,
            wifiDwellPerCh & 0xFF, (wifiDwellPerCh >> 8) & 0xFF,
            bleScanDuration & 0xFF, (bleScanDuration >> 8) & 0xFF,
            bleScanInterval & 0xFF, (bleScanInterval >> 8) & 0xFF,
            channelStart,
            channelEnd,
          ]),
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (state == WardriveState.idle) return;
      await _ble.enableEngine(engine, radio: radioBitmask);
      if (engine.isWifi) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _adoptFirmwareState() async {
    var mask = await _ble.readCommandedEngineMask();
    for (var i = 0; mask < 0 && i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      mask = await _ble.readCommandedEngineMask();
    }
    if (mask < 0) return;

    final restore = state != WardriveState.running;
    final wigleAlive = (mask & Engine.wardrive.bitmask) != 0;
    if (restore) {
      selectedTargets.remove(WardriveTarget.wigle);
      if (wigleAlive) {
        try {
          await _ble.disableEngine(Engine.wardrive);
        } catch (e) {
          DebugLog.log('WARDRIVE: adopt disable wardrive error: $e');
        }
      }
    }

    const klass = [
      Engine.flockWifi,
      Engine.flockBle,
      Engine.skySpy,
      Engine.detector,
    ];
    final running = klass.any((e) => (mask & e.bitmask) != 0);
    if (!running) {
      if (state == WardriveState.running) {
        state = WardriveState.idle;
        notifyListeners();
      } else if (restore) {
        notifyListeners();
      }
      DebugLog.log('WARDRIVE: firmware reports no keep-alive engines — staying idle');
      return;
    }
    selectedTargets
      ..clear()
      ..addAll(targetsFromEngineMask(mask));
    await _ensureLoggingAttached();
    state = WardriveState.running;
    notifyListeners();
    DebugLog.log('WARDRIVE: adopted firmware mask 0x${mask.toRadixString(16)} -> $activeLabel');
  }

  Future<void> _ensureLoggingAttached() async {
    if (_detSub != null) return;
    sessionId = await _resolveSpoolSessionId();
    startTime ??= DateTime.now();
    _gps.start();
    _detSub = _ble.detections.listen(_onDetection);
    _gpsSub = _gps.positionStream.listen(_onGpsUpdate);
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    final cached = _gps.lastPosition;
    if (cached != null) currentPosition = cached;
    WakelockPlus.enable();
    _updateLiveActivity();
  }

  Future<String> _resolveSpoolSessionId() async {
    if (sessionId.isNotEmpty) return sessionId;
    final rows = await _db.getWardriveSessions();
    if (rows.isNotEmpty) return rows.first.id;
    final newId = const Uuid().v4();
    await _db.insertSession(SessionsCompanion(
      id: drift.Value(newId),
      name: drift.Value('Recovered ${DateTime.now().toIso8601String().substring(0, 16)}'),
      nodeId: const drift.Value('default'),
      startedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
      isWardrive: const drift.Value(true),
    ));
    DebugLog.log('SPOOL: created recovered session $newId');
    return newId;
  }

  ({double? lat, double? lon, double? acc, bool approx}) _tagGps(Detection d) {
    if (offlineGpsTag && d.latitude == null) {
      final p = _gps.lastPosition;
      if (p != null) {
        return (lat: p.latitude, lon: p.longitude, acc: p.accuracy, approx: true);
      }
    }
    return (lat: d.latitude, lon: d.longitude, acc: d.accuracy, approx: false);
  }

  Future<void> _onImportedDetection(Detection detection) async {
    _spoolSessionId ??= await _resolveSpoolSessionId();
    final sid = _spoolSessionId!;
    final deviceNow = _ble.importDeviceNowMs;
    final offsetMs = deviceNow - detection.deviceTimestampMs;
    final wallClock = offsetMs < 0
        ? DateTime.now()
        : DateTime.now().subtract(Duration(milliseconds: offsetMs));
    final g = _tagGps(detection);
    await _db.insertDetection(DetectionsCompanion(
      sessionId: drift.Value(sid),
      nodeId: const drift.Value('default'),
      macAddress: drift.Value(detection.macAddress),
      deviceName: drift.Value(detection.deviceName),
      engine: drift.Value(detection.engine.name),
      detectionMethod: drift.Value(detection.method),
      rssi: drift.Value(detection.rssi),
      channel: drift.Value(detection.channel),
      deviceTimestampMs: drift.Value(detection.deviceTimestampMs),
      appTimestamp: drift.Value(wallClock.millisecondsSinceEpoch),
      latitude: drift.Value(g.lat),
      longitude: drift.Value(g.lon),
      accuracy: drift.Value(g.acc),
      approxGps: drift.Value(g.approx),
      ssid: drift.Value(detection.ssid),
      authMode: drift.Value(detection.wardrive?.authMode ?? 0),
      uavId: drift.Value(detection.odid?.uavId),
      operatorId: drift.Value(detection.odid?.operatorId),
      droneLat: drift.Value(detection.odid?.droneLat),
      droneLon: drift.Value(detection.odid?.droneLon),
      altitudeMsl: drift.Value(detection.odid?.altitudeMsl),
      heightAgl: drift.Value(detection.odid?.heightAgl),
      droneSpeed: drift.Value(detection.odid?.droneSpeed),
      droneHeading: drift.Value(detection.odid?.droneHeading),
      pilotLat: drift.Value(detection.odid?.pilotLat),
      pilotLon: drift.Value(detection.odid?.pilotLon),
    ));
    _spoolInserted++;
    DebugLog.log('SPOOL: inserted ${detection.macAddress} → session $sid wallClock=${wallClock.toIso8601String()} ($_spoolInserted/$_spoolExpectedTotal)');
    _maybeConfirmSpool();
  }

  Future<void> _onAwayLiveDetection(Detection detection) async {
    if (state == WardriveState.running) return;
    final sid = _spoolSessionId ??= await _resolveSpoolSessionId();
    final g = _tagGps(detection);
    await _db.insertDetection(DetectionsCompanion(
      sessionId: drift.Value(sid),
      nodeId: const drift.Value('default'),
      macAddress: drift.Value(detection.macAddress),
      deviceName: drift.Value(detection.deviceName),
      engine: drift.Value(detection.engine.name),
      detectionMethod: drift.Value(detection.method),
      rssi: drift.Value(detection.rssi),
      channel: drift.Value(detection.channel),
      deviceTimestampMs: drift.Value(detection.deviceTimestampMs),
      appTimestamp: drift.Value(detection.appTimestamp.millisecondsSinceEpoch),
      latitude: drift.Value(g.lat),
      longitude: drift.Value(g.lon),
      accuracy: drift.Value(g.acc),
      approxGps: drift.Value(g.approx),
      ssid: drift.Value(detection.ssid),
      authMode: drift.Value(detection.wardrive?.authMode ?? 0),
      uavId: drift.Value(detection.odid?.uavId),
      operatorId: drift.Value(detection.odid?.operatorId),
      droneLat: drift.Value(detection.odid?.droneLat),
      droneLon: drift.Value(detection.odid?.droneLon),
      altitudeMsl: drift.Value(detection.odid?.altitudeMsl),
      heightAgl: drift.Value(detection.odid?.heightAgl),
      droneSpeed: drift.Value(detection.odid?.droneSpeed),
      droneHeading: drift.Value(detection.odid?.droneHeading),
      pilotLat: drift.Value(detection.odid?.pilotLat),
      pilotLon: drift.Value(detection.odid?.pilotLon),
    ));
    DebugLog.log('AWAY-LIVE: persisted ${detection.macAddress} → session $sid');
  }

  void _onSpoolProgress(SpoolImportProgress p) {
    if (!p.done && !p.aborted && p.seen == 0) {
      _spoolExpectedTotal = p.total;
      _spoolInserted = 0;
      _spoolDone = false;
      _spoolConfirmed = false;
      _spoolSessionId = null;
      DebugLog.log('SPOOL: batch header total=${p.total}');
      return;
    }
    if (p.aborted) {
      DebugLog.log('SPOOL: batch aborted seen=${p.seen} total=${p.total} — retaining spool, no confirm');
      _spoolDone = false;
      _spoolInserted = 0;
      _spoolExpectedTotal = -1;
      _spoolConfirmed = false;
      _spoolSessionId = null;
      return;
    }
    if (p.done) {
      DebugLog.log('SPOOL: batch done seen=${p.seen} dropped=${p.dropped} inserted=$_spoolInserted expected=$_spoolExpectedTotal');
      _spoolDone = true;
      _maybeConfirmSpool();
    }
  }

  Future<void> _maybeConfirmSpool() async {
    if (_spoolDone && _spoolExpectedTotal >= 0 && _spoolInserted >= _spoolExpectedTotal && !_spoolConfirmed) {
      _spoolConfirmed = true;
      DebugLog.log('SPOOL: confirming inserted=$_spoolInserted expected=$_spoolExpectedTotal');
      await _ble.confirmSpoolImported();
      _spoolDone = false;
      _spoolInserted = 0;
      _spoolExpectedTotal = -1;
      _spoolConfirmed = false;
      _spoolSessionId = null;
    }
  }

  /// Push combined state to iOS Live Activity / Dynamic Island.
  /// Resolves primary display mode from active engines + foxhunt target,
  /// then sends all cross-engine counts so expanded view shows everything.
  void _updateLiveActivity() {
    final engineNames = activeEngines.map((e) => e.name).toSet();
    if (foxhuntTarget != null) engineNames.add('foxhunter');
    final mode = LiveActivityService.resolvePrimaryMode(
      engineNames,
      foxhuntTarget: foxhuntTarget,
    );
    _liveActivity.update(
      primaryMode: mode,
      uniqueCount: uniqueMacs.length,
      flockCount: _flockMacs.length,
      droneCount: droneCount,
      distanceKm: distanceKm,
      speedKmh: currentPosition?.speedKmh ?? 0,
      targetMac: foxhuntTarget ?? '',
      isImperial: isImperial,
    );
  }

  SessionStats get currentStats {
    final duration = startTime != null
        ? DateTime.now().difference(startTime!)
        : Duration.zero;

    return SessionStats(
      duration: duration,
      distanceKm: distanceKm,
      speedKmh: currentPosition?.speedKmh ?? 0,
      totalDetections: rawDetectionCount,
      uniqueMacs: uniqueMacs.length,
      newMacs: uniqueMacs.length,
      wifiDetections: _dedupedByMac.values.where((d) => d.isWifiDetection).length,
      wifiTotal: rawWifiCount,
      bleDetections: _dedupedByMac.values.where((d) => d.isBleDetection).length,
      bleTotal: rawBleCount,
      flockCount: includesFlock ? _flockMacs.length : 0,
      droneCount: droneCount,
      detectorCount: includesDetector ? detectorCount : 0,
      detectionsPerKm: distanceKm > 0 && distanceKm.isFinite 
          ? rawDetectionCount / distanceKm 
          : 0,
      gpsAccuracy: currentPosition?.accuracy ?? 0,
      satelliteCount: currentPosition?.satelliteCount ?? 0,
    );
  }

  void _onDetection(Detection detection) {
    if (state != WardriveState.running) return;

    final isBle = detection.isBleDetection;
    if (_ignoreList.shouldSuppress(
      mac: detection.macAddress,
      ssid: detection.ssid.isNotEmpty ? detection.ssid : detection.deviceName,
      isBle: isBle,
    )) {
      return;
    }

    // Geofence exclusion: drop detections inside any wardrive-exclusion zone
    if (_geofenceFilter.isExcludedNullable(detection.latitude, detection.longitude)) {
      return;
    }

    rawDetectionCount++;
    if (isBle) { rawBleCount++; } else { rawWifiCount++; }

    // Track per-source-node WiFi/BLE counts
    final src = detection.sourceNodeId;
    if (src.isNotEmpty) {
      if (isBle) {
        nodeBleCount[src] = (nodeBleCount[src] ?? 0) + 1;
      } else {
        nodeWifiCounts[src] = (nodeWifiCounts[src] ?? 0) + 1;
      }
    }
    uniqueMacs.add(detection.macAddress);
    if (detection.engine == Engine.wardrive) {
      _wifiNetworkMacs.add(detection.macAddress);
    }
    _notificationService.onWardriveUpdate(uniqueCount: _wifiNetworkMacs.length);
    _updateLiveActivity();
    final isFlock = detection.engine == Engine.flockBle || detection.engine == Engine.flockWifi;
    if (isFlock) {
      _flockMacs.add(detection.macAddress);
      _flockByMac[detection.macAddress] = detection;
      _cachedFlockDetections = null;
    }
    if (detection.engine == Engine.detector) {
      _detectorMacs.add(detection.macAddress);
      _detectorByMac[detection.macAddress] = detection;
      _cachedDetectorDetections = null;
    }

    final key = '${detection.macAddress}|${detection.engine.name}';
    final existing = _dedupedByMac[key];
    final threshold = detection.isBleDetection ? bleRssiRelogDb : wifiRssiRelogDb;

    if (existing != null) {
      final rssiDelta = (detection.rssi - existing.rssi).abs();
      final shouldRelog = rssiDelta >= threshold;
      WardriveExtension? mergedWardrive = detection.wardrive ?? existing.wardrive;
      if (detection.wardrive != null && existing.wardrive != null) {
        final newAuth = detection.wardrive!.authMode;
        final oldAuth = existing.wardrive!.authMode;
        mergedWardrive = detection.wardrive!.copyWith(
          authMode: newAuth > 0 ? newAuth : oldAuth,
          ssid: detection.wardrive!.ssid.isNotEmpty
              ? detection.wardrive!.ssid
              : existing.wardrive!.ssid,
          deviceName: detection.wardrive!.deviceName.isNotEmpty
              ? detection.wardrive!.deviceName
              : existing.wardrive!.deviceName,
        );
      }
      final updated = detection.copyWith(
        count: existing.count + 1,
        rssi: detection.rssi > existing.rssi ? detection.rssi : existing.rssi,
        wardrive: mergedWardrive,
      );
      _dedupedByMac[key] = updated;
      _dedupedOrdered.remove(existing);
      _dedupedOrdered.insert(0, updated);
      if (!shouldRelog) {
        notifyListeners();
        return;
      }
    } else {
      _dedupedByMac[key] = detection;
      _dedupedOrdered.insert(0, detection);
    }

    _db.insertDetection(DetectionsCompanion(
      sessionId: drift.Value(sessionId),
      nodeId: const drift.Value('default'),
      macAddress: drift.Value(detection.macAddress),
      deviceName: drift.Value(detection.deviceName),
      engine: drift.Value(detection.engine.name),
      detectionMethod: drift.Value(detection.method),
      rssi: drift.Value(detection.rssi),
      channel: drift.Value(detection.channel),
      deviceTimestampMs: drift.Value(detection.deviceTimestampMs),
      appTimestamp: drift.Value(detection.appTimestamp.millisecondsSinceEpoch),
      latitude: drift.Value(detection.latitude),
      longitude: drift.Value(detection.longitude),
      accuracy: drift.Value(detection.accuracy),
      ssid: drift.Value(detection.ssid),
      authMode: drift.Value(detection.wardrive?.authMode ?? 0),
      uavId: drift.Value(detection.odid?.uavId),
      operatorId: drift.Value(detection.odid?.operatorId),
      droneLat: drift.Value(detection.odid?.droneLat),
      droneLon: drift.Value(detection.odid?.droneLon),
      altitudeMsl: drift.Value(detection.odid?.altitudeMsl),
      heightAgl: drift.Value(detection.odid?.heightAgl),
      droneSpeed: drift.Value(detection.odid?.droneSpeed),
      droneHeading: drift.Value(detection.odid?.droneHeading),
      pilotLat: drift.Value(detection.odid?.pilotLat),
      pilotLon: drift.Value(detection.odid?.pilotLon),
    ));

    notifyListeners();
  }

  void _applyExclusionGate(GpsPosition pos) {
    final excluded = _geofenceFilter.isExcludedNullable(pos.latitude, pos.longitude);
    if (excluded == _inExclusion) return;
    _inExclusion = excluded;
    if (excluded) {
      DebugLog.log('WARDRIVE: entered exclusion zone — pausing radios');
      _pausedByExclusion = Set<Engine>.from(activeEngines);
      for (final e in _pausedByExclusion) {
        _ble.disableEngine(e);
      }
      _autoPcapPausedByExclusion = _ble.latestPcapStats.autoEnabled;
      if (_autoPcapPausedByExclusion) _ble.setAutoPcap(false);
    } else {
      DebugLog.log('WARDRIVE: exited exclusion zone — restoring radios');
      _enableEnginesSequentially(_pausedByExclusion.toList());
      _pausedByExclusion = {};
      if (_autoPcapPausedByExclusion) {
        _ble.setAutoPcap(true);
        _autoPcapPausedByExclusion = false;
      }
    }
    notifyListeners();
  }

  void _onGpsUpdate(GpsPosition pos) {
    // Validate GPS position before using
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) {
      DebugLog.log('WARDRIVE: invalid GPS position, skipping');
      return;
    }

    currentPosition = pos;
    final ll = LatLng(pos.latitude, pos.longitude);

    if (state == WardriveState.running) {
      _applyExclusionGate(pos);
    }

    if (state == WardriveState.running) {
      // Guard against GPS jumps (stale restore, satellite reacquisition)
      if (routePoints.isNotEmpty) {
        final last = routePoints.last;
        final jumpKm = _haversineKm(
          last.latitude, last.longitude, pos.latitude, pos.longitude,
        );
        if (jumpKm.isFinite && jumpKm > 0.5) {
          // >500m jump — likely stale position or GPS glitch, skip route point
          DebugLog.log('WARDRIVE: GPS jump ${(jumpKm * 1000).round()}m, skipping route point');
          lastGpsForDistance = pos;
          notifyListeners();
          return;
        }
      }

      routePoints.add(ll);
      if (lastGpsForDistance != null) {
        final km = _haversineKm(
          lastGpsForDistance!.latitude, lastGpsForDistance!.longitude,
          pos.latitude, pos.longitude,
        );
        if (km.isFinite) {
          distanceKm += km;
        }
      }
      lastGpsForDistance = pos;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _detSub?.cancel();
    _gpsSub?.cancel();
    _statsTimer?.cancel();
    _importedDetSub?.cancel();
    _awayLiveSub?.cancel();
    _spoolImportSub?.cancel();
    super.dispose();
  }

  /// Reject coords that are null, non-finite, exact (0,0), or pole-locked.
  /// Mirrors the map-render filter in wardrive_screen so the in-memory route
  /// stays clean too (no polyline darting to Null Island / Antarctica).
  static bool _isPlausibleCoord(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    if (!lat.isFinite || !lon.isFinite) return false;
    if (lat == 0.0 && lon == 0.0) return false;
    if (lat.abs() > 89.5) return false;
    return true;
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.pow(math.sin(dLon / 2), 2);
    final sqrtVal = math.sqrt(a.clamp(0.0, 1.0));
    return r * 2 * math.asin(sqrtVal);
  }
}

final wardriveProvider = ChangeNotifierProvider<WardriveController>((ref) {
  ref.keepAlive();
  final ble = ref.watch(bleManagerProvider);
  final gps = ref.watch(gpsProvider);
  final db = ref.watch(databaseProvider);
  final allowlist = ref.watch(ignoreListProvider);
  final geofence = ref.read(geofenceFilterProvider);
  final notif = ref.watch(notificationServiceProvider);
  final liveActivity = ref.watch(liveActivityServiceProvider);
  final controller = WardriveController(ble, gps, db, allowlist, geofence, notif, liveActivity);
  controller.setWatchlistGetter(() => ref.read(watchlistProvider).enabledEntries);
  controller.isImperial = ref.read(unitSystemProvider) == UnitSystem.imperial;
  ref.listen<UnitSystem>(unitSystemProvider, (_, next) {
    controller.isImperial = next == UnitSystem.imperial;
  });
  return controller;
});
