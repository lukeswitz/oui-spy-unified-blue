import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class WifiAdapterDevice {
  const WifiAdapterDevice({required this.id, required this.vendorId, required this.productId, required this.name});

  final String id;
  final int vendorId;
  final int productId;
  final String name;

  String get vidPid =>
      '${vendorId.toRadixString(16).padLeft(4, '0')}:${productId.toRadixString(16).padLeft(4, '0')}';

  static WifiAdapterDevice fromMap(Map<Object?, Object?> m) => WifiAdapterDevice(
        id: m['id']! as String,
        vendorId: m['vid']! as int,
        productId: m['pid']! as int,
        name: (m['name'] as String?) ?? '',
      );
}

class WifiAdapterAp {
  const WifiAdapterAp({required this.bssid, this.ssid, required this.rssi, required this.channel, required this.frequency, this.client = false, this.authMode = 0});

  final String bssid;
  final String? ssid;
  final int rssi;
  final int channel;
  final int frequency;
  final bool client;
  final int authMode;

  static WifiAdapterAp fromMap(Map<Object?, Object?> m) => WifiAdapterAp(
        bssid: m['bssid']! as String,
        ssid: m['ssid'] as String?,
        rssi: m['rssi']! as int,
        channel: m['channel']! as int,
        frequency: m['frequency']! as int,
        client: (m['client'] as bool?) ?? false,
        authMode: (m['authMode'] as int?) ?? 0,
      );
}

class WifiAdapterBleReport {
  const WifiAdapterBleReport({required this.mac, required this.name, required this.rssi, required this.adv});

  final String mac;
  final String name;
  final int rssi;
  final List<int> adv;

  static WifiAdapterBleReport fromMap(Map<Object?, Object?> m) => WifiAdapterBleReport(
        mac: m['mac']! as String,
        name: (m['name'] as String?) ?? '',
        rssi: m['rssi']! as int,
        adv: (m['adv'] as List<Object?>?)?.map((e) => e! as int).toList() ?? const [],
      );
}

class WifiAdapterEvent {
  const WifiAdapterEvent({this.status, this.aps, this.bleReports});

  final String? status;
  final List<WifiAdapterAp>? aps;
  final List<WifiAdapterBleReport>? bleReports;
}

class WifiAdapterAttach {
  const WifiAdapterAttach({required this.attached, required this.device});

  final bool attached;
  final WifiAdapterDevice device;
}

class WifiAdapter {
  const WifiAdapter._();

  static const _methods = MethodChannel('ouispy/wifiadapter');
  static const _events = EventChannel('ouispy/wifiadapter/sightings');
  static const _attach = EventChannel('ouispy/wifiadapter/events');

  static bool get supported => Platform.isAndroid;

  static Future<List<WifiAdapterDevice>> list() async {
    if (!supported) return const [];
    final raw = await _methods.invokeListMethod<Object?>('list') ?? const [];
    return [for (final m in raw) WifiAdapterDevice.fromMap(m! as Map<Object?, Object?>)];
  }

  static Future<bool> start(WifiAdapterDevice device, {int radioMask = 0x01}) async =>
      await _methods.invokeMethod<bool>('start', {'id': device.id, 'radioMask': radioMask}) ?? false;

  static Future<void> stop() async {
    if (supported) await _methods.invokeMethod<void>('stop');
  }

  static Stream<WifiAdapterEvent> get events => !supported
      ? const Stream.empty()
      : _events.receiveBroadcastStream().map((e) {
          final m = e as Map<Object?, Object?>;
          final aps = m['aps'] as List<Object?>?;
          final ble = m['ble'] as List<Object?>?;
          return WifiAdapterEvent(
            status: m['status'] as String?,
            aps: aps == null
                ? null
                : [for (final a in aps) WifiAdapterAp.fromMap(a! as Map<Object?, Object?>)],
            bleReports: ble == null
                ? null
                : [for (final b in ble) WifiAdapterBleReport.fromMap(b! as Map<Object?, Object?>)],
          );
        });

  static Stream<WifiAdapterAttach> get attachEvents => !supported
      ? const Stream.empty()
      : _attach.receiveBroadcastStream().map((e) {
          final m = e as Map<Object?, Object?>;
          return WifiAdapterAttach(
            attached: m['attached']! as bool,
            device: WifiAdapterDevice.fromMap(m['device']! as Map<Object?, Object?>),
          );
        });
}
