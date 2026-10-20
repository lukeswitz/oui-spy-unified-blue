import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';

void main() {
  test('Android status mirrors Live Activity counts, kinds and the full last alert', () {
    final (title, text, big) = LiveActivityService.androidStatusText({
      'mode': 'wardrive',
      'uniqueCount': 109,
      'wifiCount': 103,
      'bleCount': 6,
      'detectorHits': 6,
      'distanceKm': 12.4,
      'speedKmh': 48.0,
      'isImperial': true,
      'alertKinds': {'finder': 2, 'camera': 1, 'detector': 5},
      'lastAlert': 'Cameras: a Ring doorbell or camera',
      'lastAlertDetail': 'Board detector: Ring · -93 dBm · Wi-Fi · ch 6\nRing LLC\nAA:BB:CC:DD:EE:FF',
    });
    expect(title, 'WARDRIVE · WiFi 103 · BLE 6');
    expect(text, 'Cameras: a Ring doorbell or camera');
    expect(
      big,
      '6 hits · 7.7 mi · 30 mph\n'
      'Detector 5 · Finder tags 2 · Cameras 1\n'
      'Cameras: a Ring doorbell or camera\n'
      'Board detector: Ring · -93 dBm · Wi-Fi · ch 6\n'
      'Ring LLC\n'
      'AA:BB:CC:DD:EE:FF',
    );
  });

  test('Android status before any alert: foxhunt shows rssi and target', () {
    final (title, text, big) = LiveActivityService.androidStatusText({
      'mode': 'foxhunter',
      'uniqueCount': 3,
      'rssi': -58,
      'targetMac': 'aa:bb:cc:dd:ee:ff',
    });
    expect(title, 'FOXHUNT · -58 dBm');
    expect(text, 'AA:BB:CC:DD:EE:FF');
    expect(big, 'AA:BB:CC:DD:EE:FF');
  });
}
