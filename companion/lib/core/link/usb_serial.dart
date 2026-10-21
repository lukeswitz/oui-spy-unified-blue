import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:oui_spy/core/link/link_session.dart';

class UsbSerialDevice {
  const UsbSerialDevice({
    required this.id,
    required this.vendorId,
    required this.productId,
    required this.name,
  });

  final String id;
  final int vendorId;
  final int productId;
  final String name;

  String get vidPid =>
      '${vendorId.toRadixString(16).padLeft(4, '0')}:${productId.toRadixString(16).padLeft(4, '0')}';

  static UsbSerialDevice fromMap(Map<Object?, Object?> m) => UsbSerialDevice(
        id: m['id']! as String,
        vendorId: m['vid']! as int,
        productId: m['pid']! as int,
        name: (m['name'] as String?) ?? '',
      );
}

class UsbSerialEvent {
  const UsbSerialEvent(this.attached, this.device);

  final bool attached;
  final UsbSerialDevice device;
}

class UsbSerial {
  const UsbSerial._();

  static const _methods = MethodChannel('ouispy/usb');
  static const _data = EventChannel('ouispy/usb/data');
  static const _events = EventChannel('ouispy/usb/events');

  static bool get supported => Platform.isAndroid;

  static Future<List<UsbSerialDevice>> list() async {
    if (!supported) return const [];
    final raw = await _methods.invokeListMethod<Object?>('list') ?? const [];
    return [for (final m in raw) UsbSerialDevice.fromMap(m! as Map<Object?, Object?>)];
  }

  static Stream<UsbSerialEvent> get events => !supported
      ? const Stream.empty()
      : _events.receiveBroadcastStream().map((e) {
          final m = e as Map<Object?, Object?>;
          return UsbSerialEvent(m['attached'] == true,
              UsbSerialDevice.fromMap(m['device']! as Map<Object?, Object?>));
        });

  static Future<LinkTransport> open(UsbSerialDevice device) async {
    final ok = await _methods.invokeMethod<bool>('open', {'id': device.id}) ?? false;
    if (!ok) {
      throw PlatformException(code: 'usb_open', message: 'USB permission denied or open failed');
    }
    return _UsbSerialTransport();
  }
}

class _UsbSerialTransport implements LinkTransport {
  final Stream<Uint8List> _input = UsbSerial._data
      .receiveBroadcastStream()
      .map((e) => e is Uint8List ? e : Uint8List.fromList((e as List).cast<int>()));

  @override
  Stream<Uint8List> get input => _input;

  @override
  Future<void> send(Uint8List bytes) async {
    await UsbSerial._methods.invokeMethod<void>('write', bytes);
  }

  @override
  Future<void> close() async {
    await UsbSerial._methods.invokeMethod<void>('close');
  }
}
