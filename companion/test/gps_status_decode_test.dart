import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';

Uint8List _frame({
  required bool hwActive,
  required double lat,
  required double lon,
  required double alt,
  required double speed,
  required double heading,
  required double accuracy,
  required int sats,
}) {
  final b = ByteData(42);
  b.setUint8(0, hwActive ? 1 : 0);
  b.setFloat64(1, lat, Endian.little);
  b.setFloat64(9, lon, Endian.little);
  b.setFloat32(17, alt, Endian.little);
  b.setFloat32(21, speed, Endian.little);
  b.setFloat32(25, heading, Endian.little);
  b.setFloat32(29, accuracy, Endian.little);
  b.setUint8(33, sats);
  b.setInt64(34, 1234567, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  test('decodes hw_active + GpsData at the firmware offsets', () {
    final s = BleProtocol.decodeGpsStatus(_frame(
      hwActive: true,
      lat: 12.5,
      lon: -34.25,
      alt: 158.5,
      speed: 12.25,
      heading: 90.5,
      accuracy: 7.5,
      sats: 11,
    ));

    expect(s, isNotNull);
    expect(s!.hwActive, isTrue);
    expect(s.latitude, closeTo(12.5, 1e-9));
    expect(s.longitude, closeTo(-34.25, 1e-9));
    expect(s.altitude, closeTo(158.5, 1e-3));
    expect(s.speed, closeTo(12.25, 1e-3));
    expect(s.heading, closeTo(90.5, 1e-3));
    expect(s.accuracy, closeTo(7.5, 1e-3));
    expect(s.satellites, 11);
  });

  test('reports no hardware fix when the flag byte is clear', () {
    final s = BleProtocol.decodeGpsStatus(_frame(
      hwActive: false,
      lat: 0,
      lon: 0,
      alt: 0,
      speed: 0,
      heading: 0,
      accuracy: 0,
      sats: 0,
    ));
    expect(s!.hwActive, isFalse);
  });

  test('rejects a short payload from firmware without the read handler', () {
    expect(BleProtocol.decodeGpsStatus(List.filled(41, 0)), isNull);
    expect(BleProtocol.decodeGpsStatus(const <int>[]), isNull);
  });
}
