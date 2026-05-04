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
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/models/node.dart';
import 'package:oui_spy/core/models/session.dart';
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
      WardriveRadio.wifi => [Engine.wardrive],
      WardriveRadio.ble => [Engine.wardrive, Engine.flockBle],
      WardriveRadio.both => [Engine.wardrive, Engine.flockBle],
    },
  };

  bool get hasRadioChoice => this != drone;
}

enum WardriveRadio {
  wifi('WiFi'), ble('BLE'), both('WiFi+BLE');
  const WardriveRadio(this.label);
  final String label;
}

class WardriveController extends ChangeNotifier {
  WardriveController(this._ble, this._gps, this._db) {
    _connSub = _ble.connectionState.listen((connState) {
      if (connState == NodeConnectionState.ready && isActive) {
        _reEnableEngines();
      }
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _wifiRssiRelogDb = p.getInt('wd_wifiRssiRelog') ?? 20;
    _bleRssiRelogDb = p.getInt('wd_bleRssiRelog') ?? 15;
    _wifiScanInterval = p.getInt('wd_wifiScanInterval') ?? 150;
    _wifiDwellPerCh = p.getInt('wd_wifiDwellPerCh') ?? 200;
    _bleScanDuration = p.getInt('wd_bleScanDuration') ?? 800;
    _bleScanInterval = p.getInt('wd_bleScanInterval') ?? 2500;
    _channelStart = p.getInt('wd_channelStart') ?? 1;
    _channelEnd = p.getInt('wd_channelEnd') ?? 14;
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

  final BleManager _ble;
  final GpsProvider _gps;
  final AppDatabase _db;
  StreamSubscription<NodeConnectionState>? _connSub;

  WardriveState state = WardriveState.idle;
  WardriveTarget target = WardriveTarget.wigle;
  WardriveRadio radio = WardriveRadio.both;
  bool flockFilter = false;
  double _markerDistanceM = 10.0;

  int _wifiRssiRelogDb = 20;
  int get wifiRssiRelogDb => _wifiRssiRelogDb;
  set wifiRssiRelogDb(int v) { _wifiRssiRelogDb = v; notifyListeners(); _savePrefs(); }

  int _bleRssiRelogDb = 15;
  int get bleRssiRelogDb => _bleRssiRelogDb;
  set bleRssiRelogDb(int v) { _bleRssiRelogDb = v; notifyListeners(); _savePrefs(); }

  int _wifiScanInterval = 150;
  int get wifiScanInterval => _wifiScanInterval;
  set wifiScanInterval(int v) { _wifiScanInterval = v; notifyListeners(); _savePrefs(); }

  int _wifiDwellPerCh = 200;
  int get wifiDwellPerCh => _wifiDwellPerCh;
  set wifiDwellPerCh(int v) { _wifiDwellPerCh = v; notifyListeners(); _savePrefs(); }

  int _bleScanDuration = 800;
  int get bleScanDuration => _bleScanDuration;
  set bleScanDuration(int v) { _bleScanDuration = v; notifyListeners(); _savePrefs(); }

  int _bleScanInterval = 2500;
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

  List<Engine> get activeEngines => target.engines(radio);

  /// Local-only WiFi/BLE counts (excludes peer detections).
  int get localWifiCount =>
      rawWifiCount - nodeWifiCounts.values.fold(0, (a, b) => a + b);
  int get localBleCount =>
      rawBleCount - nodeBleCount.values.fold(0, (a, b) => a + b);
  String? foxhuntTarget;
  String sessionId = '';

  DateTime? startTime;
  final List<Detection> detections = [];
  final Map<String, Detection> _dedupedByMac = {};
  int rawDetectionCount = 0;
  final Set<String> uniqueMacs = {};
  final Set<String> _flockMacs = {};
  final List<LatLng> routePoints = [];
  double distanceKm = 0;
  GpsPosition? lastGpsForDistance;
  GpsPosition? currentPosition;
  int droneCount = 0;

  List<Detection> get dedupedDetections {
    final list = _dedupedByMac.values.toList();
    list.sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
    return list;
  }

  StreamSubscription<Detection>? _detSub;
  StreamSubscription<GpsPosition>? _gpsSub;
  Timer? _statsTimer;

  bool get isRunning => state == WardriveState.running;
  bool get isActive => state != WardriveState.idle;
  int get flockCount => _flockMacs.length;

  /// Unique flock detections (latest per MAC).
  List<Detection> get flockDetections {
    final byMac = <String, Detection>{};
    for (final d in detections) {
      if (d.engine != Engine.flockBle && d.engine != Engine.flockWifi) continue;
      final prev = byMac[d.macAddress];
      if (prev == null || d.appTimestamp.isAfter(prev.appTimestamp)) {
        byMac[d.macAddress] = d;
      }
    }
    final list = byMac.values.toList();
    list.sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
    return list;
  }

  void setTarget(WardriveTarget t) {
    if (isActive) return;
    target = t;
    if (!t.hasRadioChoice) radio = WardriveRadio.both;
    notifyListeners();
  }

  void setRadio(WardriveRadio r) {
    if (isActive) return;
    radio = r;
    notifyListeners();
  }

  Future<void> startSession() async {
    _gps.start();

    startTime = DateTime.now();
    sessionId = const Uuid().v4();
    detections.clear();
    _dedupedByMac.clear();
    rawDetectionCount = 0;
    rawWifiCount = 0;
    rawBleCount = 0;
    nodeWifiCounts.clear();
    nodeBleCount.clear();
    uniqueMacs.clear();
    _flockMacs.clear();
    routePoints.clear();
    distanceKm = 0;
    droneCount = 0;
    lastGpsForDistance = null;
    foxhuntTarget = null;

    _db.insertSession(SessionsCompanion(
      id: drift.Value(sessionId),
      name: drift.Value('Wardrive ${DateTime.now().toIso8601String().substring(0, 16)}'),
      nodeId: const drift.Value('default'),
      startedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
      isWardrive: const drift.Value(true),
    ));

    state = WardriveState.running;

    await _enableEnginesSequentially(activeEngines);

    final cached = _gps.lastPosition;
    if (cached != null) {
      currentPosition = cached;
      routePoints.add(LatLng(cached.latitude, cached.longitude));
    }

    _detSub = _ble.detections.listen(_onDetection);
    _gpsSub = _gps.positionStream.listen(_onGpsUpdate);
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());

    WakelockPlus.enable();
    notifyListeners();
    DebugLog.log('WARDRIVE: started $sessionId target=${target.label} radio=${radio.label}');
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

    // Snapshot engines before clearing state
    final enginesToStop = activeEngines.toList();
    for (final engine in enginesToStop) {
      await _ble.disableEngine(engine);
    }

    WakelockPlus.disable();

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
    detections.clear();
    _dedupedByMac.clear();
    routePoints.clear();
    uniqueMacs.clear();
    _flockMacs.clear();
    rawDetectionCount = 0;
    nodeWifiCounts.clear();
    nodeBleCount.clear();
    distanceKm = 0;
    droneCount = 0;
    _lastCompletedSessionId = null;
    notifyListeners();
  }

  /// Load a previously saved wardrive session onto the map.
  Future<void> loadSession(String sid) async {
    if (isActive) return;

    final dbRows = await _db.getDetectionMapsForSession(sid);
    detections.clear();
    _dedupedByMac.clear();
    rawDetectionCount = 0;
    rawWifiCount = 0;
    rawBleCount = 0;
    nodeWifiCounts.clear();
    nodeBleCount.clear();
    uniqueMacs.clear();
    _flockMacs.clear();
    routePoints.clear();
    distanceKm = 0;
    droneCount = 0;
    lastGpsForDistance = null;
    foxhuntTarget = null;

    for (final row in dbRows) {
      final det = _detectionFromDb(row);
      rawDetectionCount++;
      uniqueMacs.add(det.macAddress);
      if (det.engine == Engine.flockBle || det.engine == Engine.flockWifi) {
        _flockMacs.add(det.macAddress);
      }
      if (det.engine == Engine.skySpy) droneCount++;

      final key = '${det.macAddress}|${det.engine.name}';
      final existing = _dedupedByMac[key];
      if (existing != null) {
        _dedupedByMac[key] = det.copyWith(
          count: existing.count + 1,
          rssi: det.rssi > existing.rssi ? det.rssi : existing.rssi,
        );
      } else {
        _dedupedByMac[key] = det;
        detections.add(det);
      }

      if (det.latitude != null && det.longitude != null) {
        routePoints.add(LatLng(det.latitude!, det.longitude!));
      }
    }

    // Reconstruct distance from route
    for (var i = 1; i < routePoints.length; i++) {
      distanceKm += _haversineKm(
        routePoints[i - 1].latitude, routePoints[i - 1].longitude,
        routePoints[i].latitude, routePoints[i].longitude,
      );
    }

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

    return Detection(
      id: '${row['id']}',
      sessionId: row['sessionId'] as String,
      nodeId: row['nodeId'] as String,
      macAddress: row['macAddress'] as String,
      deviceName: (row['deviceName'] as String?) ?? '',
      engine: engine,
      method: row['detectionMethod'] as String,
      rssi: row['rssi'] as int,
      channel: row['channel'] as int,
      deviceTimestampMs: row['deviceTimestampMs'] as int,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(row['appTimestamp'] as int),
      ssid: (row['ssid'] as String?) ?? '',
      count: (row['count'] as int?) ?? 1,
      latitude: row['latitude'] as double?,
      longitude: row['longitude'] as double?,
      altitude: row['altitude'] as double?,
      speed: row['speed'] as double?,
      heading: row['heading'] as double?,
      accuracy: row['accuracy'] as double?,
      satelliteCount: row['satelliteCount'] as int?,
    );
  }

  /// Save WiGLE CSV to persistent storage.
  Future<String?> _saveCsv(String sid, List<Detection> dets) async {
    if (dets.isEmpty) return null;
    try {
      final dir = await _wardriveDir();
      final file = File(path.join(dir.path, '$sid.csv'));
      final csv = WigleCsv.generate(dets);
      await file.writeAsString(csv);
      DebugLog.log('WARDRIVE: CSV saved ${file.path}');
      return file.path;
    } catch (e) {
      DebugLog.log('WARDRIVE: CSV save failed: $e');
      return null;
    }
  }

  /// Get CSV file for a session (null if not yet saved).
  Future<File?> getCsvFile(String sid) async {
    final dir = await _wardriveDir();
    final file = File(path.join(dir.path, '$sid.csv'));
    if (await file.exists()) return file;
    return null;
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
  void toggleFlockFilter() {
    flockFilter = !flockFilter;
    notifyListeners();
  }

  void setFoxhuntTarget(String mac) {
    _ble.enableEngine(Engine.foxhunter);
    _ble.setFoxhunterTarget(mac);
    foxhuntTarget = mac;
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

  /// Re-enable engines after BLE reconnect killed them with DISABLE_ALL.
  void _reEnableEngines() {
    DebugLog.log('WARDRIVE: re-enabling engines after reconnect');
    _enableEnginesSequentially(activeEngines).then((_) {
      if (foxhuntTarget != null) {
        _ble.enableEngine(Engine.foxhunter);
        _ble.setFoxhunterTarget(foxhuntTarget!);
      }
    });
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
      wifiDetections: _dedupedByMac.values.where((d) =>
          d.method == 'wifi_ap' ||
          (d.engine.isWifi && d.method != 'ble_adv')).length,
      wifiTotal: rawWifiCount,
      bleDetections: _dedupedByMac.values.where((d) =>
          d.method == 'ble_adv' ||
          (d.engine.isBle && d.method != 'wifi_ap')).length,
      bleTotal: rawBleCount,
      flockCount: _flockMacs.length,
      droneCount: droneCount,
      detectionsPerKm: distanceKm > 0 ? rawDetectionCount / distanceKm : 0,
      gpsAccuracy: currentPosition?.accuracy ?? 0,
      satelliteCount: currentPosition?.satelliteCount ?? 0,
    );
  }

  void _onDetection(Detection detection) {
    if (state != WardriveState.running) return;
    rawDetectionCount++;
    final isBle = detection.method == 'ble_adv' || detection.engine.isBle;
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
    if (detection.engine == Engine.flockBle || detection.engine == Engine.flockWifi) {
      _flockMacs.add(detection.macAddress);
    }
    if (detection.engine == Engine.skySpy) droneCount++;

    final key = '${detection.macAddress}|${detection.engine.name}';
    final existing = _dedupedByMac[key];
    final isBleMethod = detection.method == 'ble_adv' || detection.engine.isBle;
    final threshold = isBleMethod ? bleRssiRelogDb : wifiRssiRelogDb;

    if (existing != null) {
      final rssiDelta = (detection.rssi - existing.rssi).abs();
      final shouldRelog = rssiDelta >= threshold;
      _dedupedByMac[key] = detection.copyWith(
        count: existing.count + 1,
        rssi: detection.rssi > existing.rssi ? detection.rssi : existing.rssi,
      );
      if (!shouldRelog) {
        notifyListeners();
        return;
      }
    } else {
      _dedupedByMac[key] = detection;
      detections.add(detection);
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
    ));

    notifyListeners();
  }

  void _onGpsUpdate(GpsPosition pos) {
    currentPosition = pos;
    final ll = LatLng(pos.latitude, pos.longitude);

    if (state == WardriveState.running) {
      routePoints.add(ll);
      if (lastGpsForDistance != null) {
        distanceKm += _haversineKm(
          lastGpsForDistance!.latitude, lastGpsForDistance!.longitude,
          pos.latitude, pos.longitude,
        );
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
    super.dispose();
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.asin(math.sqrt(a));
  }
}

/// Keep wardrive alive across tab switches — session must not die
/// when user checks home or feed tab.
final wardriveProvider = ChangeNotifierProvider<WardriveController>((ref) {
  ref.keepAlive();
  final ble = ref.watch(bleManagerProvider);
  final gps = ref.watch(gpsProvider);
  final db = ref.watch(databaseProvider);
  return WardriveController(ble, gps, db);
});
