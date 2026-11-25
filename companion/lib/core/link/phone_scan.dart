// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class NativePhoneScan {
  NativePhoneScan._();

  static const modeBalanced = 1;
  static const modeLowLatency = 2;
  static const modeOpportunistic = -1;
  static const _method = MethodChannel('ouispy/phone_scan');
  static const _events = EventChannel('ouispy/phone_scan/results');

  static Stream<ScanResult> get results =>
      _events.receiveBroadcastStream().map((e) => decode(e as Map));

  static Future<bool> start(int mode) async =>
      await _method.invokeMethod<bool>('start', {'mode': mode}) ?? false;

  static Future<void> stop() => _method.invokeMethod<void>('stop');

  static const _nanEvents = EventChannel('ouispy/phone_scan/nan');

  static Stream<({int peer, List<int> ssi})> get nanResults => _nanEvents
      .receiveBroadcastStream()
      .map((e) => (peer: (e as Map)['peer'] as int, ssi: List<int>.from(e['ssi'] as List)));

  static Future<bool> nanStart() async => await _method.invokeMethod<bool>('nanStart') ?? false;

  static Future<void> nanStop() => _method.invokeMethod<void>('nanStop');

  static Future<List<({String bssid, int rssi, int freq, List<int> ie})>> wifiOdid() async {
    final raw = await _method.invokeListMethod<Object?>('wifiOdid') ?? const [];
    return [
      for (final e in raw)
        if (e is Map)
          (
            bssid: e['bssid'] as String,
            rssi: e['rssi'] as int,
            freq: e['freq'] as int,
            ie: List<int>.from(e['ie'] as List),
          ),
    ];
  }

  static ScanResult decode(Map m) {
    final mfg = <int, List<int>>{};
    (m['mfg'] as Map?)?.forEach((k, v) => mfg[k as int] = List<int>.from(v as List));
    final svcData = <Guid, List<int>>{};
    (m['svcData'] as Map?)?.forEach((k, v) => svcData[Guid(k as String)] = List<int>.from(v as List));
    return ScanResult(
      device: BluetoothDevice.fromId(m['id'] as String),
      advertisementData: AdvertisementData(
        advName: m['name'] as String? ?? '',
        txPowerLevel: m['tx'] as int?,
        appearance: m['appearance'] as int?,
        connectable: m['connectable'] as bool? ?? false,
        manufacturerData: mfg,
        serviceData: svcData,
        serviceUuids: [for (final u in (m['svc'] as List? ?? const [])) Guid(u as String)],
      ),
      rssi: m['rssi'] as int,
      timeStamp: DateTime.now(),
    );
  }
}
