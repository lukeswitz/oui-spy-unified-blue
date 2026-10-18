import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';

List<int> _hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

void main() {
  test('S3 capture (v3_app_controlled_ie_e2e): watchlist hit notification titled by description', () {
    final det = BleProtocol.decodeDetection(
      _hex('0040486e8bd31aa9064a1a0000010000000000004e6f6b696120726f757465720000000000000000000000000000000000000000'),
      sessionId: 's',
      nodeId: 'n',
      appTimestamp: DateTime(2026),
    );
    final (title, subtitle, body, channel) = NotificationService.detectionNotificationText(det)!;
    expect(title, 'Nokia router');
    expect(subtitle, 'Detector · WATCHLIST');
    expect(body, '-87 dBm · ch 6\n40:48:6E:8B:D3:1A');
    expect(channel, NotifChannel.detector);
  });

  test('S3 capture: probe-SSID detector record titled by its description', () {
    final det = BleProtocol.decodeDetection(
      _hex('005cfce1006a24a706212100000500000000000056696c6c6173656e6f7200000000000000000000000000000000000000000000'),
      sessionId: 's',
      nodeId: 'n',
      appTimestamp: DateTime(2026),
    );
    final (title, subtitle, body, _) = NotificationService.detectionNotificationText(det)!;
    expect(title, 'Probe request for "Villasenor"');
    expect(subtitle, 'Detector · PROBE');
    expect(body, '-89 dBm · ch 6\n5C:FC:E1:00:6A:24');
  });

  test('pwnagotchi hit carries hit, class, engine and device data', () {
    final det = Detection(
      id: 'x',
      sessionId: 's',
      nodeId: 'n',
      macAddress: 'de:ad:be:ef:00:01',
      engine: Engine.detector,
      method: 'pwnagotchi',
      rssi: -61,
      channel: 6,
      deviceTimestampMs: 0,
      appTimestamp: DateTime(2026),
      deviceName: 'pwny',
      sourceNodeId: 'node2',
    );
    final (title, subtitle, body, channel) = NotificationService.detectionNotificationText(det)!;
    expect(title, 'Pwnagotchi');
    expect(subtitle, 'Detector · PWNAGOTCHI');
    expect(body, '-61 dBm · ch 6\npwny\nDE:AD:BE:EF:00:01\nvia node node2');
    expect(channel, NotifChannel.detector);
  });
}
