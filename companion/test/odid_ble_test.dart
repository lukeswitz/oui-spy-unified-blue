import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/odid/odid_ble.dart';

Map<String, List<int>> _vectors() {
  final src = File('../test/host/vectors.h').readAsStringSync();
  final out = <String, List<int>>{};
  for (final m in RegExp(r'static const uint8_t (\w+)\[\] = \{([^}]*)\};').allMatches(src)) {
    out[m.group(1)!] = [for (final h in m.group(2)!.split(',')) int.parse(h.trim().substring(2), radix: 16)];
  }
  return out;
}

void main() {
  final v = _vectors();

  test('a BLE message pack from the DroneID encoder decodes every field', () {
    final o = OdidBleDecoder().feed('02:00:00:00:00:0a', v['BLE_A']!)!;
    expect(o.uavId, 'TESTDRONE1234567890');
    expect(o.idType, 1);
    expect(o.uaType, 2);
    expect(o.altitudeMsl, 101);
    expect(o.heightAgl, isNull);
    expect(o.altitudeBaro, isNull);
    expect(o.droneSpeed, 6);
    expect(o.vertSpeed, isNull);
    expect(o.droneHeading, 90);
    expect(o.locTimestamp, isNull);
    expect(o.droneLat, closeTo(51.4779, 1e-6));
    expect(o.droneLon, closeTo(-0.0015, 1e-6));
    expect(o.pilotLat, closeTo(51.478, 1e-6));
    expect(o.operatorId, 'OPERATOR01');
    expect(o.selfId, 'host test');
    expect(o.areaCount, 1);
  });

  test('the ID in the second Basic ID is used when the first is empty', () {
    final o = OdidBleDecoder().feed('02:00:00:00:00:0b', v['BLE_B']!)!;
    expect(o.uavId, 'CAAREG0001');
    expect(o.idType, 2);
  });

  test('single BLE 4 messages from one MAC build up one drone', () {
    final pack = v['BLE_A']!.sublist(6);
    final dec = OdidBleDecoder();
    var last = dec.feed('02:00:00:00:00:0c', const []);
    for (var m = 0; m < pack[2]; m++) {
      final msg = pack.sublist(3 + m * 25, 3 + (m + 1) * 25);
      final adv = [msg.length + 5, 0x16, 0xFA, 0xFF, 0x0D, m, ...msg];
      last = dec.feed('02:00:00:00:00:0c', adv) ?? last;
    }
    expect(last!.uavId, 'TESTDRONE1234567890');
    expect(last.operatorId, 'OPERATOR01');
    expect(last.droneSpeed, 6);
  });

  List<int> vendorIe(List<int> beacon) => beacon.sublist(38, 38 + beacon[37]);

  test('a Wi-Fi beacon Remote ID element from the DroneID encoder decodes', () {
    final a = OdidBleDecoder().feedMessages('02:00:00:00:00:1a', odidMessagesFromVendorIe(vendorIe(v['BEACON_A']!)))!;
    expect(a.uavId, 'TESTDRONE1234567890');
    expect(a.altitudeMsl, 101);
    expect(a.droneSpeed, 6);
    expect(a.operatorId, 'OPERATOR01');
    final b = OdidBleDecoder().feedMessages('02:00:00:00:00:1b', odidMessagesFromVendorIe(vendorIe(v['BEACON_B']!)))!;
    expect(b.uavId, 'CAAREG0001');
  });

  test('a phone Wi-Fi scan Remote ID element becomes a Sky Spy beacon detection', () async {
    final ble = BleManager();
    final got = ble.detections.first;
    ble.addPhoneWifiOdid('02:00:00:00:00:1C', -55, 6, vendorIe(v['BEACON_A']!));
    final d = await got.timeout(const Duration(seconds: 2));
    expect(d.engine, Engine.skySpy);
    expect(d.method, 'odid_beacon');
    expect(d.channel, 6);
    expect(d.odid?.uavId, 'TESTDRONE1234567890');
  });

  test('a phone advertisement with Remote ID becomes a Sky Spy detection', () async {
    final ble = BleManager();
    final got = ble.detections.first;
    ble.addPhoneDetection('02:00:00:00:00:0d', '', -60, v['BLE_A']!);
    final d = await got.timeout(const Duration(seconds: 2));
    expect(d.engine, Engine.skySpy);
    expect(d.method, 'odid_ble');
    expect(d.odid?.uavId, 'TESTDRONE1234567890');
    expect(d.sourceNodeId, BleManager.phoneNodeId);
  });
}
