// Copyright (c) 2026 Luke Switzer
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/feed/detection_row.dart';

Detection _d({String node = 'OUISPY-AB12', String src = '', String method = 'wifi_ap', int ch = 6}) => Detection(
      id: '1',
      sessionId: 's',
      nodeId: node,
      macAddress: '02:00:00:00:00:01',
      engine: Engine.wardrive,
      method: method,
      rssi: -60,
      channel: ch,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      sourceNodeId: src,
    );

void main() {
  test('scanner names the radio and the phone or adapter that heard it', () {
    expect(detectionScanner(_d()), 'Wardrive · Wi-Fi');
    expect(detectionScanner(_d(method: 'ble_adv', ch: 37)), 'Wardrive · BLE');
    expect(detectionScanner(_d(node: BleManager.phoneNodeId, src: BleManager.phoneNodeId, method: 'ble_adv', ch: 0)),
        'Phone Bluetooth scan');
    expect(detectionScanner(_d(node: BleManager.phoneNodeId, src: BleManager.phoneNodeId)), 'Phone Wi-Fi scan');
    expect(detectionScanner(_d(node: '${BleManager.usbWifiNodeId}:X', src: '${BleManager.usbWifiNodeId}:X')),
        'USB Wi-Fi adapter');
    expect(detectionScanner(_d(node: BleManager.usbBleNodeId, src: BleManager.usbBleNodeId, method: 'ble_adv', ch: 0)),
        'USB Bluetooth adapter');
  });

  test('a local board hit keeps its board after a DB round-trip', () {
    final d = _d();
    expect(detectionHasBoard(d), isTrue);
    final back = detectionFromDbRow({
      'id': 1,
      'sessionId': 's',
      'nodeId': 'default',
      'macAddress': d.macAddress,
      'engine': d.engine.name,
      'detectionMethod': d.method,
      'rssi': d.rssi,
      'channel': d.channel,
      'deviceTimestampMs': 0,
      'appTimestamp': 1000,
      'ext': detectionExt(d),
    });
    expect(back.nodeId, 'OUISPY-AB12');
    expect(detectionHasBoard(back), isTrue);
    expect(detectionHasBoard(_d(node: 'default')), isFalse);
    expect(detectionHasBoard(_d(node: BleManager.phoneNodeId)), isFalse);
  });
}
