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
  const SdrFrame({this.power, this.centerHz, this.rate, this.detection});

  final List<double>? power;
  final int? centerHz;
  final int? rate;
  final SdrDetection? detection;
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

  static Future<bool> start(String id, SdrMode mode, int freqHz, int rate) async {
    if (!supported) return false;
    return await _methods.invokeMethod<bool>('sdrStart', {
          'id': id,
          'mode': mode.name,
          'freqHz': freqHz,
          'rate': rate,
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

  SdrState get state => _current;
  List<double> get power => _power;
  int get centerHz => _centerHz;
  int get rate => _rate;
  List<SdrDetection> get detections => List.unmodifiable(_detections);
  Stream<SdrState> get stateStream => _state.stream;
  Stream<SdrFrame> get frameStream => _frames.stream;

  Future<bool> start(String deviceId, SdrMode mode, int freqHz, int rate) async {
    _set(SdrState.starting);
    _detections.clear();
    await _sub?.cancel();
    _sub = Sdr.frames.listen(_onFrame, onError: (Object e) {
      DebugLog.log('SDR: $e');
      _set(SdrState.error);
    });
    try {
      final ok = await Sdr.start(deviceId, mode, freqHz, rate);
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
    if (f.power != null) {
      _power = f.power!;
      if (f.centerHz != null) _centerHz = f.centerHz!;
      if (f.rate != null) _rate = f.rate!;
    }
    if (f.detection != null) {
      _detections.insert(0, f.detection!);
      if (_detections.length > 200) _detections.removeRange(200, _detections.length);
    }
    _frames.add(f);
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
