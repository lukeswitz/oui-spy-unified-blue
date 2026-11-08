import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/stops_report.dart' show StopsReport;

class CellReading {
  final String rat;
  final String plmn;
  final int area;
  final int cid;
  const CellReading(this.rat, this.plmn, this.area, this.cid);

  int get rank => switch (rat) {
        'GSM' => 2,
        'WCDMA' => 3,
        'LTE' => 4,
        'NR' => 5,
        _ => 0,
      };

  String get label => switch (rat) {
        'GSM' => '2G',
        'WCDMA' => '3G',
        'LTE' => '4G',
        'NR' => '5G',
        _ => rat,
      };

  String get key => '$rat:$plmn:$area:$cid';

  static CellReading? fromMap(Map<Object?, Object?>? m) {
    if (m == null) return null;
    final rat = m['rat'] as String?;
    final cid = (m['cid'] as num?)?.toInt();
    if (rat == null || cid == null || cid <= 0 || cid == 0x7FFFFFFF) return null;
    return CellReading(rat, m['plmn'] as String? ?? '', (m['area'] as num?)?.toInt() ?? 0, cid);
  }
}

class CellPlace {
  final double lat;
  final double lon;
  final int firstMs;
  final Set<String> cells;
  int bestRank;
  CellPlace(this.lat, this.lon, this.firstMs, this.cells, this.bestRank);

  Map<String, dynamic> toJson() => {'a': lat, 'o': lon, 't': firstMs, 'c': cells.toList(), 'r': bestRank};
  factory CellPlace.fromJson(Map<String, dynamic> j) => CellPlace(
        (j['a'] as num).toDouble(),
        (j['o'] as num).toDouble(),
        (j['t'] as num).toInt(),
        {for (final c in (j['c'] as List? ?? const [])) c as String},
        (j['r'] as num?)?.toInt() ?? 0,
      );
}

class CellWatch {
  static const placeM = 300.0;
  static const learnMs = 3 * 24 * 3600 * 1000;
  static const recentMs = 2 * 60 * 1000;
  static const cooldownMs = 30 * 60 * 1000;
  static const maxPlaces = 200;
  static const maxCellsPerPlace = 64;

  final places = <CellPlace>[];
  int _recentRank = 0;
  int _recentAt = 0;
  String _recentPlmn = '';
  final _lastWarn = <String, int>{};

  String? check(CellReading c, double? lat, double? lon, int now) {
    String? warning;
    final hadRecent = now - _recentAt <= recentMs && _recentPlmn == c.plmn ? _recentRank : 0;
    CellPlace? place;
    if (lat != null && lon != null) {
      for (final p in places) {
        if (StopsReport.meters(p.lat, p.lon, lat, lon) <= placeM) {
          place = p;
          break;
        }
      }
      if (place == null) {
        if (places.length >= maxPlaces) places.removeAt(0);
        place = CellPlace(lat, lon, now, {}, 0);
        places.add(place);
      }
    }
    final usual = math.max(hadRecent, place?.bestRank ?? 0);
    if (c.rank == 2 && usual >= 4) {
      warning = 'This phone dropped to 2G';
    } else if (c.rank == 3 && (place?.bestRank ?? 0) >= 4) {
      warning = 'This phone dropped to 3G at a place where it uses ${place!.bestRank == 5 ? '5G' : '4G'}';
    } else if (place != null && now - place.firstMs >= learnMs && place.cells.isNotEmpty && !place.cells.contains(c.key)) {
      warning = 'New ${c.label} cell at a known place';
    }
    if (place != null) {
      if (place.cells.length < maxCellsPerPlace) place.cells.add(c.key);
      if (c.rank > place.bestRank) place.bestRank = c.rank;
    }
    if (c.rank >= 4) {
      _recentRank = c.rank;
      _recentAt = now;
      _recentPlmn = c.plmn;
    }
    if (warning == null) return null;
    final last = _lastWarn[warning];
    if (last != null && now - last < cooldownMs) return null;
    _lastWarn[warning] = now;
    return warning;
  }
}

class GpsWatch {
  static const cooldownMs = 10 * 60 * 1000;
  static const jumpMps = 300.0;
  static const spoofMinSats = 6;
  static const spoofMinMean = 35.0;
  static const spoofMaxSpread = 1.5;
  static const spoofHoldMs = 10000;
  static const jamDropDb = 15.0;
  static const jamMovingMps = 5.0;

  GpsPosition? _lastFix;
  double _lastSpeed = 0;
  int? _uniformSince;
  final _history = <(int, int, double)>[];
  final _lastWarn = <String, int>{};

  String? _warn(String w, int now) {
    final last = _lastWarn[w];
    if (last != null && now - last < cooldownMs) return null;
    _lastWarn[w] = now;
    return w;
  }

  String? onFix(GpsPosition p, bool mocked, int now) {
    final prev = _lastFix;
    _lastFix = p;
    _lastSpeed = p.speed.isFinite ? p.speed : 0;
    if (mocked) return _warn('An app on this phone is setting the GPS location', now);
    if (prev == null) return null;
    final dt = p.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (dt <= 0 || dt > 30 || p.accuracy > 50 || prev.accuracy > 50) return null;
    final d = StopsReport.meters(prev.latitude, prev.longitude, p.latitude, p.longitude);
    if (d / dt > jumpMps) return _warn('GPS position jumped ${(d / 1000).toStringAsFixed(1)} km', now);
    return null;
  }

  String? onSatellites(List<double> cn0, int now) {
    final used = cn0.length;
    final mean = used == 0 ? 0.0 : cn0.reduce((a, b) => a + b) / used;
    _history.add((now, used, mean));
    _history.removeWhere((h) => now - h.$1 > 10000);
    if (used >= spoofMinSats && mean >= spoofMinMean) {
      final spread = math.sqrt(cn0.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) / used);
      if (spread < spoofMaxSpread) {
        _uniformSince ??= now;
        if (now - _uniformSince! >= spoofHoldMs) {
          return _warn('Satellite signals look identical. Possible GPS spoofing', now);
        }
      } else {
        _uniformSince = null;
      }
    } else {
      _uniformSince = null;
    }
    if (_lastSpeed >= jamMovingMps) {
      final good = _history.where((h) => now - h.$1 >= 3000 && h.$2 >= 6 && h.$3 >= 30);
      if (good.isNotEmpty && (used <= 2 || good.first.$3 - mean >= jamDropDb)) {
        return _warn('GPS signal dropped suddenly while moving. Possible jamming', now);
      }
    }
    return null;
  }
}

class PhoneWatch extends ChangeNotifier {
  static const _cellKey = 'phone_watch_cell';
  static const _gpsKey = 'phone_watch_gps';
  static const _placesKey = 'phone_watch_cell_places';
  static const _method = MethodChannel('ouispy/phone_watch');
  static const _gnss = EventChannel('ouispy/phone_watch/gnss');
  static const cellPoll = Duration(seconds: 30);

  PhoneWatch(this._gps, this._notif) {
    if (supported) _load();
  }

  final GpsProvider _gps;
  final NotificationService _notif;
  final cell = CellWatch();
  final gps = GpsWatch();
  bool cellOn = false;
  bool gpsOn = false;
  Timer? _cellTimer;
  StreamSubscription<dynamic>? _gnssSub;
  StreamSubscription<(GpsPosition, bool)>? _fixSub;
  int _savedPlaces = 0;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      for (final j in jsonDecode(prefs.getString(_placesKey) ?? '[]') as List) {
        cell.places.add(CellPlace.fromJson(j as Map<String, dynamic>));
      }
    } on FormatException {
      cell.places.clear();
    }
    _savedPlaces = cell.places.length;
    await setCell(prefs.getBool(_cellKey) ?? false, save: false);
    await setGps(prefs.getBool(_gpsKey) ?? false, save: false);
  }

  Future<void> setCell(bool on, {bool save = true}) async {
    if (!supported) return;
    cellOn = on;
    _cellTimer?.cancel();
    _cellTimer = on ? Timer.periodic(cellPoll, (_) => _pollCell()) : null;
    if (on) _pollCell();
    notifyListeners();
    if (save) await (await SharedPreferences.getInstance()).setBool(_cellKey, on);
  }

  Future<void> setGps(bool on, {bool save = true}) async {
    if (!supported) return;
    gpsOn = on;
    await _gnssSub?.cancel();
    await _fixSub?.cancel();
    _gnssSub = null;
    _fixSub = null;
    if (on) {
      _gnssSub = _gnss.receiveBroadcastStream().listen(
        (e) {
          final cn0 = [for (final c in ((e as Map)['cn0'] as List? ?? const [])) (c as num).toDouble()];
          _alert('gps_watch', 'GPS warning', gps.onSatellites(cn0, DateTime.now().millisecondsSinceEpoch));
        },
        onError: (Object e) => DebugLog.log('PHONEWATCH: gnss $e'),
      );
      _fixSub = _gps.phoneFixes.listen(
        (f) => _alert('gps_watch', 'GPS warning', gps.onFix(f.$1, f.$2, DateTime.now().millisecondsSinceEpoch)),
      );
    }
    notifyListeners();
    if (save) await (await SharedPreferences.getInstance()).setBool(_gpsKey, on);
  }

  Future<void> _pollCell() async {
    try {
      final c = CellReading.fromMap(await _method.invokeMethod<Map<Object?, Object?>>('servingCell'));
      if (c == null) return;
      final here = _gps.recentPosition();
      final w = cell.check(c, here?.latitude, here?.longitude, DateTime.now().millisecondsSinceEpoch);
      _alert('cell_watch', 'Cell network warning', w, body: '${c.label} cell ${c.cid} · network ${c.plmn}');
      if (cell.places.length != _savedPlaces || w != null) await _savePlaces();
    } on PlatformException catch (e) {
      DebugLog.log('PHONEWATCH: cell ${e.message}');
    }
  }

  Future<void> _savePlaces() async {
    _savedPlaces = cell.places.length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_placesKey, jsonEncode([for (final p in cell.places) p.toJson()]));
  }

  void _alert(String kind, String title, String? warning, {String? body}) {
    if (warning == null) return;
    DebugLog.log('PHONEWATCH: $kind $warning');
    _notif.onWatchAlert(kind: kind, title: title, subtitle: warning, body: body ?? warning);
  }

  @override
  void dispose() {
    _cellTimer?.cancel();
    _gnssSub?.cancel();
    _fixSub?.cancel();
    super.dispose();
  }
}

final phoneWatchProvider = ChangeNotifierProvider<PhoneWatch>(
  (ref) => PhoneWatch(ref.read(gpsProvider), ref.read(notificationServiceProvider)),
);
