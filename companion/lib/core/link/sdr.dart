import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/wifi_adapter.dart';

enum SdrMode { spectrum, adsb, tpms, rtl433 }

class SdrDetection {
  const SdrDetection({required this.kind, required this.fields});

  final String kind;
  final Map<String, Object?> fields;

  int? get frequency => (fields['frequency'] as num?)?.toInt();
  int? get rssi => (fields['rssi'] as num?)?.toInt();
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
      {List<int> freqsHz = const []}) async {
    if (!supported) return false;
    return await _methods.invokeMethod<bool>('sdrStart', {
          'id': id,
          'mode': mode.name,
          'freqHz': freqHz,
          'rate': rate,
          'freqsHz': freqsHz,
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

  bool get hasFix => lat != null && lon != null;
}

enum SdrState { idle, starting, running, error }

class SdrController {
  SdrController();

  final _state = StreamController<SdrState>.broadcast();
  final _frames = StreamController<SdrFrame>.broadcast();
  StreamSubscription<SdrFrame>? _sub;
  SdrState _current = SdrState.idle;
  List<double> _power = const [];
  int _centerHz = 0;
  int _rate = 0;
  final List<SdrDetection> _detections = [];
  final Map<String, AdsbAircraft> _adsb = {};
  String _scanStatus = '';

  SdrState get state => _current;
  String get scanStatus => _scanStatus;
  List<double> get power => _power;
  int get centerHz => _centerHz;
  int get rate => _rate;
  List<SdrDetection> get detections => List.unmodifiable(_detections);
  List<AdsbAircraft> get adsbAircraft => _adsb.values.toList();
  Stream<SdrState> get stateStream => _state.stream;
  Stream<SdrFrame> get frameStream => _frames.stream;

  Future<bool> start(String deviceId, SdrMode mode, int freqHz, int rate,
      {List<int> freqsHz = const []}) async {
    _set(SdrState.starting);
    _detections.clear();
    _adsb.clear();
    _scanStatus = '';
    await _sub?.cancel();
    _sub = Sdr.frames.listen(_onFrame, onError: (Object e) {
      DebugLog.log('SDR: $e');
      _set(SdrState.error);
    });
    try {
      final ok = await Sdr.start(deviceId, mode, freqHz, rate, freqsHz: freqsHz);
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
    _set(SdrState.idle);
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
      if (key != null) {
        final idx = _detections.indexWhere((e) => _dedupKey(e) == key);
        if (idx >= 0) {
          final prev = _detections.removeAt(idx);
          d.fields['count'] = ((prev.fields['count'] as int?) ?? 1) + 1;
        }
      }
      _detections.insert(0, d);
      if (_detections.length > 400) _detections.removeRange(400, _detections.length);
      if (d.kind == 'adsb') _mergeAdsb(d);
    }
    _frames.add(f);
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
  final c = SdrController();
  ref.onDispose(c.dispose);
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
