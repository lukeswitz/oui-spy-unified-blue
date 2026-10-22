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
  const WifiAdapterAp({required this.bssid, this.ssid, required this.rssi, required this.channel, required this.frequency});

  final String bssid;
  final String? ssid;
  final int rssi;
  final int channel;
  final int frequency;

  static WifiAdapterAp fromMap(Map<Object?, Object?> m) => WifiAdapterAp(
        bssid: m['bssid']! as String,
        ssid: m['ssid'] as String?,
        rssi: m['rssi']! as int,
        channel: m['channel']! as int,
        frequency: m['frequency']! as int,
      );
}

class WifiAdapterEvent {
  const WifiAdapterEvent({this.status, this.aps});

  final String? status;
  final List<WifiAdapterAp>? aps;
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

  static Future<bool> start(WifiAdapterDevice device) async =>
      await _methods.invokeMethod<bool>('start', {'id': device.id}) ?? false;

  static Future<void> stop() async {
    if (supported) await _methods.invokeMethod<void>('stop');
  }

  static Stream<WifiAdapterEvent> get events => !supported
      ? const Stream.empty()
      : _events.receiveBroadcastStream().map((e) {
          final m = e as Map<Object?, Object?>;
          final aps = m['aps'] as List<Object?>?;
          return WifiAdapterEvent(
            status: m['status'] as String?,
            aps: aps == null
                ? null
                : [for (final a in aps) WifiAdapterAp.fromMap(a! as Map<Object?, Object?>)],
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
