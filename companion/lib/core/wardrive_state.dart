import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/models/session.dart';
import 'package:drift/drift.dart' as drift;
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

  bool get hasRadioChoice => this == flock || this == wigleFlock;
}

enum WardriveRadio {
  wifi('WiFi'), ble('BLE'), both('WiFi+BLE');
  const WardriveRadio(this.label);
  final String label;
}

class WardriveController extends ChangeNotifier {
  WardriveController(this._ble, this._gps, this._db);

  final BleManager _ble;
  final GpsProvider _gps;
  final AppDatabase _db;

  WardriveState state = WardriveState.idle;
  WardriveTarget target = WardriveTarget.flock;
  WardriveRadio radio = WardriveRadio.both;
  bool flockFilter = false;
  double markerDistanceM = 10.0;

  List<Engine> get activeEngines => target.engines(radio);
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

  void startSession() {
    _gps.start();

    startTime = DateTime.now();
    sessionId = const Uuid().v4();
    detections.clear();
    _dedupedByMac.clear();
    rawDetectionCount = 0;
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

    for (final engine in activeEngines) {
      _ble.enableEngine(engine);
    }

    state = WardriveState.running;

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
    _detSub?.cancel();
    _gpsSub?.cancel();
    _statsTimer?.cancel();
    _detSub = null;
    _gpsSub = null;
    _statsTimer = null;

    for (final engine in activeEngines) {
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
      DebugLog.log('WARDRIVE: saved $sessionId (${detections.length} det, ${uniqueMacs.length} unique, ${_flockMacs.length} flock)');
    }

    state = WardriveState.idle;
    notifyListeners();
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
      wifiDetections: _dedupedByMac.values.where((d) => d.engine.isWifi).length,
      bleDetections: _dedupedByMac.values.where((d) => d.engine.isBle).length,
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
    uniqueMacs.add(detection.macAddress);
    if (detection.engine == Engine.flockBle || detection.engine == Engine.flockWifi) {
      _flockMacs.add(detection.macAddress);
    }
    if (detection.engine == Engine.skySpy) droneCount++;

    final key = '${detection.macAddress}|${detection.engine.name}';
    final existing = _dedupedByMac[key];
    if (existing != null) {
      _dedupedByMac[key] = detection.copyWith(
        count: existing.count + 1,
        rssi: detection.rssi > existing.rssi ? detection.rssi : existing.rssi,
      );
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
