import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/stops_report.dart' show StopsReport;

class _Cooldown {
  _Cooldown(this.ms);
  final int ms;
  final _at = <String, int>{};

  String? pass(String key, String warning, int now) {
    final last = _at[key];
    if (last != null && now - last < ms) return null;
    _at[key] = now;
    if (_at.length > 1024) _at.remove(_at.keys.first);
    return warning;
  }
}

class CarFollow {
  static const followM = 2000.0;
  static const followMs = 10 * 60 * 1000;
  static const staleMs = 30 * 60 * 1000;
  static const ownCarStartMs = 60 * 1000;
  static const ownCarScans = 2;

  final ownCars = <String>{};
  final startHits = <String, int>{};
  int? _scanStart;
  final _seenThisStart = <String>{};
  final _tracks = <String, List<(int, double, double)>>{};
  final _cool = _Cooldown(60 * 60 * 1000);

  void scanStarted(int now) {
    _scanStart = now;
    _seenThisStart.clear();
  }

  String? onTire(String id, int now, double? lat, double? lon) {
    final start = _scanStart;
    if (start != null && now - start <= ownCarStartMs && _seenThisStart.add(id)) {
      final n = (startHits[id] ?? 0) + 1;
      startHits[id] = n;
      if (n >= ownCarScans) ownCars.add(id);
    }
    if (ownCars.contains(id) || lat == null || lon == null) return null;
    final t = _tracks.putIfAbsent(id, () => []);
    t.add((now, lat, lon));
    t.removeWhere((s) => now - s.$1 > staleMs);
    if (_tracks.length > 512) _tracks.remove(_tracks.keys.first);
    if (t.length < 2 || now - t.first.$1 < followMs) return null;
    var far = 0.0;
    for (final s in t) {
      final d = StopsReport.meters(t.first.$2, t.first.$3, s.$2, s.$3);
      if (d > far) far = d;
    }
    if (far < followM) return null;
    return _cool.pass(id, 'A car may be following you. Its tire sensor was heard over ${(far / 1000).toStringAsFixed(1)} km '
        'and ${((now - t.first.$1) / 60000).round()} min', now);
  }
}

class AircraftCircle {
  static const nearM = 10000.0;
  static const minSpanMs = 10 * 60 * 1000;
  static const windowMs = 30 * 60 * 1000;
  static const turnDeg = 540.0;
  static const minSamples = 20;

  final _tracks = <String, List<(int, double, double, double)>>{};
  final _cool = _Cooldown(60 * 60 * 1000);

  String? onAircraft(String icao, String label, int now, double? lat, double? lon, double? heading, double? hereLat,
      double? hereLon) {
    if (lat == null || lon == null || heading == null) return null;
    final t = _tracks.putIfAbsent(icao, () => []);
    if (t.isNotEmpty && t.last.$4 == heading && t.last.$2 == lat && t.last.$3 == lon) return null;
    t.add((now, lat, lon, heading));
    t.removeWhere((s) => now - s.$1 > windowMs);
    if (_tracks.length > 256) _tracks.remove(_tracks.keys.first);
    if (t.length < minSamples || now - t.first.$1 < minSpanMs) return null;
    final cLat = hereLat ?? t.map((s) => s.$2).reduce((a, b) => a + b) / t.length;
    final cLon = hereLon ?? t.map((s) => s.$3).reduce((a, b) => a + b) / t.length;
    if (t.any((s) => StopsReport.meters(cLat, cLon, s.$2, s.$3) > nearM)) return null;
    var turn = 0.0;
    for (var i = 1; i < t.length; i++) {
      var d = t[i].$4 - t[i - 1].$4;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      turn += d;
    }
    if (turn.abs() < turnDeg) return null;
    return _cool.pass(icao, 'Aircraft circling near you: $label, ${(turn.abs() / 360).toStringAsFixed(1)} turns', now);
  }
}

class DroneLoiter {
  static const nearM = 300.0;
  static const loiterMs = 5 * 60 * 1000;
  static const windowMs = 15 * 60 * 1000;
  static const nearShare = 0.8;
  static const approachM = 200.0;
  static const approachMs = 3 * 60 * 1000;
  static const pilotNearM = 500.0;

  final _tracks = <String, List<(int, double, double?)>>{};
  final _cool = _Cooldown(15 * 60 * 1000);

  String? onDrone(String uav, int now, double? droneLat, double? droneLon, double? pilotLat, double? pilotLon,
      double? hereLat, double? hereLon) {
    if (hereLat == null || hereLon == null || droneLat == null || droneLon == null) return null;
    final drone = StopsReport.meters(hereLat, hereLon, droneLat, droneLon);
    final pilot = pilotLat == null || pilotLon == null || (pilotLat == 0 && pilotLon == 0)
        ? null
        : StopsReport.meters(hereLat, hereLon, pilotLat, pilotLon);
    final t = _tracks.putIfAbsent(uav, () => []);
    t.add((now, drone, pilot));
    t.removeWhere((s) => now - s.$1 > windowMs);
    if (_tracks.length > 128) _tracks.remove(_tracks.keys.first);
    final p = t.where((s) => s.$3 != null && now - s.$1 <= approachMs).toList();
    if (pilot != null && pilot <= pilotNearM && p.length >= 2 && p.first.$3! - pilot >= approachM) {
      final w = _cool.pass('$uav|pilot', 'Drone pilot moving toward you, now ${pilot.round()} m away', now);
      if (w != null) return w;
    }
    if (now - t.first.$1 < loiterMs) return null;
    final near = t.where((s) => s.$2 <= nearM).length;
    if (near < t.length * nearShare) return null;
    return _cool.pass('$uav|loiter', 'Drone loitering near you for ${((now - t.first.$1) / 60000).round()} min', now);
  }
}

class MeshCrossing {
  static const handoffMs = 10 * 60 * 1000;
  static const quietMs = 30 * 1000;
  static const confirmMs = 60 * 1000;

  final _last = <String, Map<String, int>>{};
  final _pending = <String, (String, String, int)>{};
  final _cool = _Cooldown(30 * 60 * 1000);

  String? onSighting(String key, String node, int now) {
    String? warning;
    final p = _pending[key];
    if (p != null) {
      if (node == p.$1) {
        _pending.remove(key);
      } else if (node == p.$2 && now - p.$3 >= confirmMs) {
        _pending.remove(key);
        warning = _cool.pass(key, 'Moving through your mesh: node ${p.$1} to node ${p.$2}', now);
      }
    }
    final seen = _last.putIfAbsent(key, () => {});
    seen.removeWhere((_, t) => now - t > handoffMs);
    final before = seen[node];
    if (before == null && seen.isNotEmpty && !_pending.containsKey(key)) {
      final other = seen.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (now - other.value >= quietMs) _pending[key] = (other.key, node, now);
    }
    seen[node] = now;
    if (_last.length > 4096) _last.remove(_last.keys.first);
    return warning;
  }
}

class WatchAlerts extends ChangeNotifier {
  static const kinds = ['car_follow', 'aircraft_circle', 'drone_loiter', 'mesh_crossing'];
  static const _ownCarsKey = 'watch_own_cars';

  WatchAlerts({bool persist = true}) : _persist = persist {
    if (persist) _load();
  }

  final bool _persist;
  final _on = <String>{};
  final car = CarFollow();
  final aircraft = AircraftCircle();
  final drone = DroneLoiter();
  final mesh = MeshCrossing();

  bool isOn(String kind) => _on.contains(kind);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in kinds) {
      if (prefs.getBool('watch_$k') ?? false) _on.add(k);
    }
    car.ownCars.addAll(prefs.getStringList(_ownCarsKey) ?? const []);
    notifyListeners();
  }

  Future<void> set(String kind, bool on) async {
    on ? _on.add(kind) : _on.remove(kind);
    notifyListeners();
    if (_persist) await (await SharedPreferences.getInstance()).setBool('watch_$kind', on);
  }

  Future<void> saveOwnCars() async {
    if (_persist) await (await SharedPreferences.getInstance()).setStringList(_ownCarsKey, car.ownCars.toList());
  }
}

final watchAlertsProvider = ChangeNotifierProvider<WatchAlerts>((ref) {
  final w = WatchAlerts();
  final notif = ref.read(notificationServiceProvider);
  final gps = ref.read(gpsProvider);
  final sdr = ref.read(sdrControllerProvider);
  final ble = ref.read(bleManagerProvider);
  void alert(String kind, String title, String? warning, {String? mac}) {
    if (warning == null) return;
    notif.onWatchAlert(kind: kind, title: title, subtitle: warning, body: warning, mac: mac);
  }

  final subs = <StreamSubscription<dynamic>>[
    sdr.stateStream.listen((s) {
      if (s == SdrState.running && sdr.mode == SdrMode.tpms) w.car.scanStarted(DateTime.now().millisecondsSinceEpoch);
    }),
    sdr.frameStream.listen((f) {
      final d = f.detection;
      if (d == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final here = gps.recentPosition();
      if (d.kind == 'tpms' && w.isOn('car_follow')) {
        final id = '${d.fields['model']}|${d.fields['id']}';
        final owned = w.car.ownCars.length;
        alert('car_follow', 'Car following you', w.car.onTire(id, now, here?.latitude, here?.longitude));
        if (w.car.ownCars.length != owned) w.saveOwnCars();
      } else if (d.kind == 'adsb' && w.isOn('aircraft_circle')) {
        final icao = (d.fields['icao'] as String?)?.toUpperCase() ?? '';
        if (icao.isEmpty) return;
        final cs = (d.fields['callsign'] as String?)?.trim() ?? '';
        alert(
          'aircraft_circle',
          'Aircraft circling you',
          w.aircraft.onAircraft(icao, cs.isEmpty ? icao : '$cs ($icao)', now, (d.fields['lat'] as num?)?.toDouble(),
              (d.fields['lon'] as num?)?.toDouble(), (d.fields['heading'] as num?)?.toDouble(), here?.latitude,
              here?.longitude),
        );
      }
    }),
    ble.detections.listen((d) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final odid = d.odid;
      if (d.engine == Engine.skySpy && odid != null && w.isOn('drone_loiter')) {
        final here = gps.recentPosition();
        alert(
          'drone_loiter',
          'Drone near you',
          w.drone.onDrone(odid.uavId ?? d.macAddress, now, odid.droneLat, odid.droneLon, odid.pilotLat, odid.pilotLon,
              here?.latitude, here?.longitude),
          mac: d.macAddress,
        );
      }
      if (w.isOn('mesh_crossing') && d.sourceNodeId.isNotEmpty && d.isBleDetection && d.macAddress.isNotEmpty) {
        alert('mesh_crossing', 'Device crossing your mesh', w.mesh.onSighting(d.macAddress.toUpperCase(), d.sourceNodeId, now),
            mac: d.macAddress);
      }
    }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
  return w;
});
