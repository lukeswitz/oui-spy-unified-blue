import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/session_detection_store.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/link/wifi_adapter.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';

enum SdrMode { spectrum, adsb, tpms, rtl433 }

class SdrDetection {
  const SdrDetection({required this.kind, required this.fields});

  final String kind;
  final Map<String, Object?> fields;

  int? get frequency => (fields['frequency'] as num?)?.toInt();
  int? get rssi => (fields['rssi'] as num?)?.toInt();
}

const sdrPowerKeys = ['power_W', 'power0_W', 'power1_W', 'power2_W', 'power_VA', 'power', 'current_A'];
const sdrTotalKeys = [
  'consumption_data', 'Consumption', 'consumption', 'LastConsumptionCount', 'energy_kWh', 'total_kWh',
  'cumulative_kWh', 'reading_kWh', 'reading', 'volume_m3', 'volume_gal', 'volume', 'energy',
];

double? _num(Map<String, Object?> f, List<String> keys) {
  for (final k in keys) {
    final v = f[k];
    if (v is num) return v.toDouble();
  }
  return null;
}

void sdrTrackUsage(Map<String, Object?> f, Map<String, Object?>? prev, int nowMs) {
  final power = _num(f, sdrPowerKeys);
  final total = _num(f, sdrTotalKeys);
  if (power == null && total == null) return;
  var rate = (prev?['_usageRate'] as num?)?.toDouble() ?? 0;
  var anchorTotal = (prev?['_usageTotal'] as num?)?.toDouble();
  var anchorAt = prev?['_usageAt'] as int?;
  if (power != null) {
    rate = power.abs();
  } else if (anchorTotal == null || anchorAt == null || total! < anchorTotal) {
    anchorTotal = total;
    anchorAt = nowMs;
    rate = 0;
  } else if (total > anchorTotal && nowMs > anchorAt) {
    rate = (total - anchorTotal) / ((nowMs - anchorAt) / 3600000);
    anchorTotal = total;
    anchorAt = nowMs;
  }
  final peak = [rate, (prev?['_usagePeak'] as num?)?.toDouble() ?? 0].reduce((a, b) => a > b ? a : b);
  f['_usageRate'] = rate;
  f['_usagePeak'] = peak;
  if (anchorTotal != null) f['_usageTotal'] = anchorTotal;
  if (anchorAt != null) f['_usageAt'] = anchorAt;
  f['_usage'] = peak > 0 ? rate / peak : 0.0;
}

class SdrFrame {
  const SdrFrame({this.power, this.centerHz, this.rate, this.detection, this.status});

  final List<double>? power;
  final int? centerHz;
  final int? rate;
  final SdrDetection? detection;
  final String? status;
}

class Sdr {
  const Sdr._();

  static const _methods = MethodChannel('ouispy/wifiadapter');
  static const _events = EventChannel('ouispy/sdr');

  static bool get supported => Platform.isAndroid;

  static Future<List<WifiAdapterDevice>> list() async {
    if (!supported) return const [];
    final raw = await _methods.invokeListMethod<Object?>('sdrList') ?? const [];
    return [for (final m in raw) WifiAdapterDevice.fromMap(m! as Map<Object?, Object?>)];
  }

  static Future<bool> start(String id, SdrMode mode, int freqHz, int rate,
      {List<int> freqsHz = const [], bool raw = false, List<String> categories = const []}) async {
    if (!supported) return false;
    return await _methods.invokeMethod<bool>('sdrStart', {
          'id': id,
          'mode': mode.name,
          'freqHz': freqHz,
          'rate': rate,
          'freqsHz': freqsHz,
          'raw': raw,
          'categories': categories,
        }) ??
        false;
  }

  static Future<void> stop() async {
    if (supported) await _methods.invokeMethod<void>('sdrStop');
  }

  static Stream<SdrFrame> get frames => !supported
      ? const Stream.empty()
      : _events.receiveBroadcastStream().map((e) {
          final m = e as Map<Object?, Object?>;
          final det = m['detection'] as Map<Object?, Object?>?;
          final power = m['power'] as List<Object?>?;
          return SdrFrame(
            status: m['status'] as String?,
            power: power == null ? null : [for (final v in power) (v as num).toDouble()],
            centerHz: (m['centerHz'] as num?)?.toInt(),
            rate: (m['rate'] as num?)?.toInt(),
            detection: det == null
                ? null
                : SdrDetection(
                    kind: (det['kind'] as String?) ?? 'rf',
                    fields: {for (final entry in det.entries) entry.key.toString(): entry.value},
                  ),
          );
        });
}

class AdsbAircraft {
  AdsbAircraft({required this.icao, required this.firstSeen});

  final String icao;
  final DateTime firstSeen;
  String callsign = '';
  double? lat;
  double? lon;
  int altFt = 0;
  int velocityKt = 0;
  int heading = 0;
  DateTime? lastSeen;
  final List<(double, double)> track = [];

  bool get hasFix => lat != null && lon != null;
}

enum SdrState { idle, starting, running, error }

class SdrController {
  SdrController({AppDatabase? db, GpsPosition? Function()? gps})
      : _db = db,
        _gps = gps;

  final AppDatabase? _db;
  final GpsPosition? Function()? _gps;
  String _dbSession = '';
  SessionDetectionStore? _store;
  final Set<String> _storedKeys = {};
  final Map<String, LatLng> _adsbStoredAt = {};

  final _state = StreamController<SdrState>.broadcast();
  final _frames = StreamController<SdrFrame>.broadcast();
  StreamSubscription<SdrFrame>? _sub;
  SdrState _current = SdrState.idle;
  List<double> _power = const [];
  int _centerHz = 0;
  int _rate = 0;
  final List<SdrDetection> _detections = [];
  final Map<String, int> _pending = {};
  final Map<String, AdsbAircraft> _adsb = {};
  String _scanStatus = '';
  SdrMode? _mode;
  final Set<int> bands = {315, 433, 915};
  final Set<String> categories = {'weather', 'meter', 'security', 'fob', 'environmental'};

  SdrState get state => _current;
  SdrMode? get mode => _mode;
  String get scanStatus => _scanStatus;
  List<double> get power => _power;
  int get centerHz => _centerHz;
  int get rate => _rate;
  List<SdrDetection> get detections => List.unmodifiable(_detections);
  List<AdsbAircraft> get adsbAircraft => _adsb.values.toList();
  Stream<SdrState> get stateStream => _state.stream;
  Stream<SdrFrame> get frameStream => _frames.stream;

  Future<bool> start(String deviceId, SdrMode mode, int freqHz, int rate,
      {List<int> freqsHz = const [], bool raw = false, List<String> categories = const []}) async {
    _set(SdrState.starting);
    if (mode != _mode) {
      _detections.clear();
      _pending.clear();
      _adsb.clear();
    }
    _mode = mode;
    _scanStatus = '';
    final db = _db;
    if (db != null) {
      await _closeSession();
      _store?.dispose();
      _store = SessionDetectionStore(db);
      _storedKeys.clear();
      _adsbStoredAt.clear();
      _dbSession = 'sdr-${DateTime.now().microsecondsSinceEpoch}';
      try {
        await db.insertSession(SessionsCompanion(
          id: drift.Value(_dbSession),
          name: drift.Value('SDR ${DateTime.now().toIso8601String().substring(0, 16)}'),
          nodeId: const drift.Value('default'),
          startedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
          isWardrive: const drift.Value(false),
        ));
      } catch (e) {
        DebugLog.log('SDR: insertSession failed: $e');
      }
    }
    await _sub?.cancel();
    _sub = Sdr.frames.listen(_onFrame, onError: (Object e) {
      DebugLog.log('SDR: $e');
      _set(SdrState.error);
    });
    try {
      final ok = await Sdr.start(deviceId, mode, freqHz, rate, freqsHz: freqsHz, raw: raw, categories: categories);
      if (!ok) {
        _set(SdrState.error);
        await _sub?.cancel();
        _sub = null;
      } else {
        _set(SdrState.running);
      }
      return ok;
    } on PlatformException catch (e) {
      DebugLog.log('SDR: start failed ${e.message}');
      _set(SdrState.error);
      return false;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await Sdr.stop();
    await _closeSession();
    _set(SdrState.idle);
  }

  void clearDetections() {
    _detections.clear();
    _pending.clear();
    _adsb.clear();
    _power = const [];
  }

  void _onFrame(SdrFrame f) {
    if (f.status != null) _scanStatus = f.status!;
    if (f.power != null) {
      _power = f.power!;
      if (f.centerHz != null) _centerHz = f.centerHz!;
      if (f.rate != null) _rate = f.rate!;
    }
    final d = f.detection;
    if (d != null) {
      final key = _dedupKey(d);
      final idx = key == null ? -1 : _detections.indexWhere((e) => _dedupKey(e) == key);
      if (key != null && d.kind != 'adsb' && idx < 0) {
        final seen = (_pending[key] ?? 0) + 1;
        if (seen < 2) {
          _pending[key] = seen;
          _frames.add(f);
          return;
        }
        _pending.remove(key);
        sdrTrackUsage(d.fields, null, DateTime.now().millisecondsSinceEpoch);
        _detections.insert(0, d);
        _record(d);
      } else {
        if (idx >= 0) {
          final prev = _detections.removeAt(idx);
          d.fields['count'] = ((prev.fields['count'] as int?) ?? 1) + 1;
          sdrTrackUsage(d.fields, prev.fields, DateTime.now().millisecondsSinceEpoch);
        }
        _detections.insert(0, d);
        if (d.kind == 'adsb') _mergeAdsb(d);
        _record(d);
      }
      if (_detections.length > 400) _detections.removeRange(400, _detections.length);
    }
    _frames.add(f);
  }

  static const _adsbTrackStepM = 250.0;

  Detection _asDetection(SdrDetection d) {
    final f = d.fields;
    final model = (f['model'] ?? f['icao'] ?? d.kind).toString();
    final ident = (f['id'] ?? f['icao'] ?? '').toString();
    final cs = (f['callsign'] as String?)?.trim() ?? '';
    final pos = _gps?.call();
    final now = DateTime.now();
    return Detection(
      id: '',
      sessionId: _dbSession,
      nodeId: 'default',
      macAddress: ident.isNotEmpty ? '$model|$ident' : model,
      engine: Engine.sdr,
      method: d.kind,
      rssi: (f['rssi'] as num?)?.toInt() ?? 0,
      channel: 0,
      deviceTimestampMs: now.millisecondsSinceEpoch,
      appTimestamp: now,
      deviceName: d.kind == 'adsb' && cs.isNotEmpty ? cs : model,
      ssid: jsonEncode({
        for (final e in f.entries)
          if (!e.key.startsWith('_')) e.key: e.value,
      }),
      count: (f['count'] as int?) ?? 1,
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      altitude: pos?.altitude,
      speed: pos?.speed,
      heading: pos?.heading,
      accuracy: pos?.accuracy,
      satelliteCount: pos?.satelliteCount,
    );
  }

  void _record(SdrDetection d) {
    final store = _store;
    if (store == null || _dbSession.isEmpty) return;
    if (d.kind != 'tpms' && d.kind != 'rtl433' && d.kind != 'adsb') return;
    final det = _asDetection(d);
    final key = det.macAddress;
    var insert = !_storedKeys.contains(key);
    if (d.kind == 'adsb' && !insert) {
      final lat = (d.fields['lat'] as num?)?.toDouble();
      final lon = (d.fields['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        final last = _adsbStoredAt[key];
        if (last == null ||
            const Distance().as(LengthUnit.Meter, last, LatLng(lat, lon)) >= _adsbTrackStepM) {
          insert = true;
        }
      }
    }
    if (d.kind == 'adsb') {
      final lat = (d.fields['lat'] as num?)?.toDouble();
      final lon = (d.fields['lon'] as num?)?.toDouble();
      if (insert && lat != null && lon != null) _adsbStoredAt[key] = LatLng(lat, lon);
    }
    if (insert) {
      _storedKeys.add(key);
      store.insert(key, _dbSession, det);
    } else {
      store.update(key, _dbSession, det);
    }
  }

  Future<void> _closeSession() async {
    final store = _store;
    final db = _db;
    if (store == null || db == null || _dbSession.isEmpty) return;
    await store.flush();
    try {
      await db.updateSession(SessionsCompanion(
        id: drift.Value(_dbSession),
        endedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
        detectionCount: drift.Value(_storedKeys.length),
        uniqueMacCount: drift.Value(_storedKeys.length),
      ));
    } catch (e) {
      DebugLog.log('SDR: updateSession failed for $_dbSession: $e');
    }
  }

  String? _dedupKey(SdrDetection d) {
    switch (d.kind) {
      case 'tpms':
      case 'rtl433':
        return '${d.kind}|${d.fields['model']}|${d.fields['id']}';
      case 'adsb':
        return 'adsb|${d.fields['icao']}';
      default:
        return null;
    }
  }

  void _mergeAdsb(SdrDetection d) {
    final icao = (d.fields['icao'] as String?)?.toUpperCase().trim();
    if (icao == null || icao.isEmpty) return;
    final a = _adsb.putIfAbsent(
        icao, () => AdsbAircraft(icao: icao, firstSeen: DateTime.now().toUtc()));
    final cs = (d.fields['callsign'] as String?)?.trim();
    if (cs != null && cs.isNotEmpty) a.callsign = cs;
    final lat = (d.fields['lat'] as num?)?.toDouble();
    final lon = (d.fields['lon'] as num?)?.toDouble();
    if (lat != null && lon != null) {
      a.lat = lat;
      a.lon = lon;
      if (a.track.isEmpty || a.track.last.$1 != lat || a.track.last.$2 != lon) {
        a.track.add((lat, lon));
        if (a.track.length > 500) a.track.removeAt(0);
      }
    }
    final alt = (d.fields['altitude'] as num?)?.toInt();
    if (alt != null) a.altFt = alt;
    final vel = (d.fields['velocity'] as num?)?.toInt();
    if (vel != null) a.velocityKt = vel;
    final hdg = (d.fields['heading'] as num?)?.toInt();
    if (hdg != null) a.heading = hdg;
    a.lastSeen = DateTime.now();
  }

  void _set(SdrState s) {
    _current = s;
    _state.add(s);
  }

  void dispose() {
    _sub?.cancel();
    _state.close();
    _frames.close();
  }
}

final sdrControllerProvider = Provider<SdrController>((ref) {
  final c = SdrController(
    db: ref.read(databaseProvider),
    gps: () => ref.read(wardriveProvider).currentPosition,
  );
  final attachSub = WifiAdapter.attachEvents.listen((e) async {
    if (!e.attached && c.state != SdrState.idle) {
      final present = await Sdr.list();
      if (present.isEmpty) await c.stop();
    }
  });
  ref.onDispose(() {
    attachSub.cancel();
    c.dispose();
  });
  return c;
});

final sdrStateProvider = StreamProvider<SdrState>((ref) {
  return ref.watch(sdrControllerProvider).stateStream;
});

final sdrPresentProvider = StreamProvider<bool>((ref) async* {
  Future<bool> check() async => (await Sdr.list()).isNotEmpty;
  yield await check();
  await for (final _ in WifiAdapter.attachEvents) {
    yield await check();
  }
});
