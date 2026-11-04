import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';

List<int> _row() {
  final b = Uint8List(61);
  final v = ByteData.sublistView(b);
  b[0] = 0x12;
  b[1] = 0x01;
  b.setRange(2, 8, [0x02, 0x00, 0x00, 0x00, 0x00, 0x01]);
  v.setInt8(8, -61);
  b[9] = 6;
  b[10] = 3;
  b[11] = 0;
  b.setRange(12, 21, 'MyNetwork'.codeUnits);
  v.setInt32(45, 123456789, Endian.little);
  v.setInt32(49, -987654321, Endian.little);
  v.setInt16(53, 42, Endian.little);
  v.setUint16(55, 55, Endian.little);
  v.setUint32(57, 1700000000, Endian.little);
  return b;
}

void main() {
  test('decodes a header', () {
    final b = Uint8List(10);
    b[0] = 0x12;
    ByteData.sublistView(b)
      ..setUint32(2, 1000, Endian.little)
      ..setUint32(6, 7, Endian.little);
    final f = BleProtocol.decodeWdLogFrame(b)!;
    expect(f.total, 1000);
    expect(f.dropped, 7);
    expect(f.isEnd, isFalse);
  });

  test('decodes a row with every field at its firmware offset', () {
    final r = BleProtocol.decodeWdLogFrame(_row())!.row!;
    expect(r.mac, '02:00:00:00:00:01');
    expect(r.rssi, -61);
    expect(r.channel, 6);
    expect(r.authMode, 3);
    expect(r.isBle, isFalse);
    expect(r.name, 'MyNetwork');
    expect(r.latitude, closeTo(12.3456789, 1e-9));
    expect(r.longitude, closeTo(-98.7654321, 1e-9));
    expect(r.altitude, 42);
    expect(r.accuracy, 5.5);
    expect(r.seenAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
  });

  test('decodes the end frame and rejects short or foreign frames', () {
    expect(BleProtocol.decodeWdLogFrame([0x12, 0x02])!.isEnd, isTrue);
    expect(BleProtocol.decodeWdLogFrame([0x12, 0x01, 0x00]), isNull);
    expect(BleProtocol.decodeWdLogFrame([0x12]), isNull);
    expect(BleProtocol.decodeWdLogFrame([0x06, 0x00]), isNull);
    expect(BleProtocol.decodeWdLogFrame([0x12, 0x09]), isNull);
  });
}
