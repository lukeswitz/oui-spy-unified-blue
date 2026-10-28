import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/detector_signatures.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> _detectorPacket({required int method, required String desc, int? confidence, int isFullMac = 0}) {
  final d = utf8.encode(desc);
  return [
    0x00,
    0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
    0xC4,
    0x06,
    0, 0, 0, 0,
    method,
    0, 0, 0, 0, 0,
    isFullMac,
    ...d,
    ...List.filled(32 - d.length, 0),
    ?confidence,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('confidence byte at ext[33] decodes; old 52-byte records read as 0', () {
    final withTier = BleProtocol.decodeDetection(
      _detectorPacket(method: 11, desc: 'Cafe twin BSSID', confidence: 1),
      sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026),
    );
    expect(withTier.method, 'evil_twin');
    expect(withTier.detector?.confidence, 1);
    expect(withTier.detector?.filterDescription, 'Cafe twin BSSID');

    final legacy = BleProtocol.decodeDetection(
      _detectorPacket(method: 2, desc: 'Find My tracker following 4s'),
      sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026),
    );
    expect(legacy.detector?.confidence, 0);
  });

  test('new detector methods 11..13 decode by name', () {
    String m(int id) => BleProtocol.decodeDetection(
          _detectorPacket(method: id, desc: 'x', confidence: 2),
          sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026),
        ).method;
    expect([m(10), m(11), m(12), m(13)], ['amazon', 'evil_twin', 'karma', 'mesh']);
  });

  test('suspected detector hits use the quiet channel and carry the tier', () {
    final det = BleProtocol.decodeDetection(
      _detectorPacket(method: 8, desc: 'Motorola Solutions', confidence: 1),
      sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026),
    );
    final (_, subtitle, _, channel) = NotificationService.detectionNotificationText(det)!;
    expect(channel, NotifChannel.detectorQuiet);
    expect(subtitle, endsWith('· Suspected'));

    final high = BleProtocol.decodeDetection(
      _detectorPacket(method: 8, desc: 'Axon (Law Enforcement)', confidence: 2),
      sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026),
    );
    expect(NotificationService.detectionNotificationText(high)!.$4, NotifChannel.detector);
  });

  test('confidence threshold only filters tiered hits', () {
    final n = NotificationService()..minDetectorConfidence = NotificationService.confHigh;
    expect(n.belowConfidence(0), isFalse);
    expect(n.belowConfidence(1), isTrue);
    expect(n.belowConfidence(2), isFalse);
    expect(n.belowConfidence(3), isFalse);
  });

  test('milestones widen: 1k 5k 10k 25k 50k then every 100k', () {
    expect(NotificationService.milestoneFor(999), 0);
    expect(NotificationService.milestoneFor(4999), 1000);
    expect(NotificationService.milestoneFor(7167), 5000);
    expect(NotificationService.milestoneFor(26000), 25000);
    expect(NotificationService.milestoneFor(99999), 50000);
    expect(NotificationService.milestoneFor(250000), 200000);
  });

  test('UTF-8 SSIDs survive decode; control bytes and malformed sequences do not crash', () {
    final det = BleProtocol.decodeDetection(
      _detectorPacket(method: 5, desc: 'Café\u0007Ñ'),
      sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026),
    );
    expect(det.detector?.filterDescription, 'CaféÑ');
    final bad = _detectorPacket(method: 5, desc: 'ab');
    bad[20] = 0xC3;
    expect(
      BleProtocol.decodeDetection(bad, sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026))
          .detector
          ?.filterDescription,
      isNotNull,
    );
  });

  test('device-info keyed fields parse past the optional temperature field', () {
    final kv = BleManager.deviceInfoKeyed(['0.7.0', 'OUISPY-ABCD', 'xiao_s3', 'node', '123456', 'proto=2', 'epoch=0a1b2c3d', 'boot=17', 'spool=1']);
    expect(kv, {'proto': '2', 'epoch': '0a1b2c3d', 'boot': '17', 'spool': '1'});
  });

  test('radio policy rides as hardware-config byte 7 only when known', () {
    final without = BleProtocol.encodeHardwareConfig(buzzer: true, led: true, neopixelBrightness: 50, buzzerVolume: 100);
    expect(without.length, 7);
    final withPol = BleProtocol.encodeHardwareConfig(
      buzzer: true, led: true, neopixelBrightness: 50, buzzerVolume: 100,
      radioPolicy: BleProtocol.radioPolicyActiveProbe | BleProtocol.radioPolicyPassiveBle,
    );
    expect(withPol.length, 8);
    expect(withPol[7], 0x03);
  });

  test('mesh signature takes the ninth mask bit', () {
    expect(sigMesh, 0x100);
    expect(sigAll & sigMesh, sigMesh);
    expect(detectorMethodsByBit[sigProbe], containsAll(['probe_ssid', 'evil_twin', 'karma']));
  });
}
