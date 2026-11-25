// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/zigbee.dart';

Uint8List _packed({required int channel, required String ssid, required List<int> adv}) {
  final b = BytesBuilder();
  b.addByte(Engine.wardrive.index);
  b.add([0x00, 0x00, 0x12, 0x34, 0x00, 0x00]);
  b.addByte((-61) & 0xFF);
  b.addByte(channel);
  b.add([0x10, 0x27, 0x00, 0x00]);
  b.addByte(3);
  b.add(List.filled(5, 0));
  final s = Uint8List(33)..setAll(0, ssid.codeUnits);
  b.add(s);
  b.addByte(0);
  b.add(Uint8List(21));
  b.addByte(adv.length);
  b.add(adv);
  return b.toBytes();
}

const _zigbeeBeaconAdv = [
  0, 2, 0x34, 0x12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 200, 1,
  0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x22, 0x03,
];

Detection _decode(Uint8List data) => BleProtocol.decodeDetection(
      data,
      sessionId: 's',
      nodeId: 'n',
      appTimestamp: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('wardrive method list ends with ieee802154 at index 3', () {
    expect(BleProtocol.wardriveMethods[3], zigbeeMethod);
  });

  test('firmware record decodes to a zigbee detection', () {
    final d = _decode(_packed(channel: 15, ssid: '', adv: _zigbeeBeaconAdv));
    expect(d.method, zigbeeMethod);
    expect(d.channel, 15);
    expect(d.isZigbeeDetection, isTrue);
    expect(d.isBleDetection, isFalse);
    expect(d.isWifiDetection, isFalse);
    final z = zigbeeInfoFor(d)!;
    expect(z.frameType, ZigbeeFrameType.beacon);
    expect(z.pan, 0x1234);
    expect(z.shortAddress, 0);
    expect(z.eui64, isNull);
    expect(z.lqi, 200);
    expect(z.beacon, ZigbeeBeacon.zigbee);
    expect(z.beaconExtPan, '88:77:66:55:44:33:22:11');
    expect(z.stackProfile, 2);
    expect(z.nwkVersion, 2);
    expect(z.routerCapacity && z.endDeviceCapacity, isTrue);
    expect(zigbeeVendorKey(d), '');
    expect(zigbeeHeadline(d), 'PAN 0x1234 0x0000');
  });

  test('channel 26 is never classified as BLE', () {
    final d = _decode(_packed(channel: 26, ssid: '', adv: _zigbeeBeaconAdv));
    expect(d.isBleDetection, isFalse);
    expect(isBleDetectionRaw(method: zigbeeMethod, engine: Engine.wardrive, channel: 26), isFalse);
  });

  test('thread beacon carries the network name', () {
    final adv = [
      0, 3, 0xCD, 0xAB, 0xFF, 0xFE, 1, 2, 3, 4, 5, 6, 7, 8, 10, 2,
      0xDE, 0xAD, 0xBE, 0xEF, 0, 0xCA, 0xFE, 1, 0x20,
    ];
    final d = _decode(_packed(channel: 20, ssid: 'MyThreadNet', adv: adv));
    expect(d.ssid, 'MyThreadNet');
    final z = zigbeeInfoFor(d)!;
    expect(z.beacon, ZigbeeBeacon.thread);
    expect(z.eui64, '01:02:03:04:05:06:07:08');
    expect(z.threadVersion, 2);
    expect(zigbeeHeadline(d), 'MyThreadNet');
    expect(zigbeeVendorKey(d), '01:02:03:04:05:06:07:08');
    expect(zigbeeFrequencyMhz(20), 2450);
  });

  test('short adv is rejected', () {
    expect(ZigbeeInfo.parse(const [0, 2, 1]), isNull);
    expect(ZigbeeInfo.parse(null), isNull);
  });

  test('c5 gating', () {
    expect(boardHas802154('xiao_c5'), isTrue);
    expect(boardHas802154('tdongle_c5'), isTrue);
    expect(boardHas802154('xiao_s3'), isFalse);
  });
}
