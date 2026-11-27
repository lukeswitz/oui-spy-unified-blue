// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';

List<int> boardBleWardrive({List<int> adv = const [], String name = 'Pixel Buds'}) {
  final b = Uint8List(adv.isEmpty ? 74 : 75 + adv.length);
  b[0] = 6;
  b.setAll(1, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
  b[7] = (-60) & 0xFF;
  b[8] = 0;
  b.buffer.asByteData().setUint32(9, 123456, Endian.little);
  b[13] = 1;
  b.setAll(14, '49BE'.codeUnits);
  b.setAll(53, name.codeUnits);
  if (adv.isNotEmpty) {
    b[74] = adv.length;
    b.setAll(75, adv);
  }
  return b;
}

void main() {
  for (final c in {
    'no advert bytes': const <int>[],
    'flags and manufacturer data': const [0x02, 0x01, 0x06, 0x05, 0xFF, 0x4C, 0x00, 0x10, 0x05],
  }.entries) {
    test('a board BLE wardrive packet decodes as BLE (${c.key})', () {
      final d = BleProtocol.decodeDetection(
        boardBleWardrive(adv: c.value),
        sessionId: 's',
        nodeId: '49BE',
        appTimestamp: DateTime(2026),
        latitude: null,
        longitude: null,
        accuracy: null,
        satelliteCount: null,
      );
      expect(d.engine, Engine.wardrive);
      expect(d.method, 'ble_adv');
      expect(d.macAddress.toUpperCase(), 'AA:BB:CC:DD:EE:FF');
      expect(d.isBleDetection, isTrue);
    });
  }
}
