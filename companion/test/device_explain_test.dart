import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/observation.dart';

Observation _wifi(String mac, String name) =>
    Observation(key: 'WIFI:$mac', kind: RadioKind.wifi, mac: mac, name: name, rssi: -86);

void main() {
  test('raven DIRECT ssid is acoustic sensor not phone or tv', () {
    final g = DeviceExplain.guess(
        _wifi('00:0A:F5:86:56:DD', 'DIRECT-rR-Raven-607'), ['Raven / ShotSpotter', 'Unknown Signature']);
    expect(g.headline, contains('Raven'));
    expect(g.headline, contains('ShotSpotter'));
    expect(g.headline.contains('phone or TV'), isFalse);
    expect(g.because, contains('Raven / ShotSpotter'));
    expect(g.because, contains('DIRECT-'));
  });

  test('generic DIRECT ssid looks like wifi direct', () {
    expect(DeviceExplain.guess(_wifi('02:11:22:33:44:55', 'DIRECT-xy-LivingRoom'), []).headline,
        contains('Wi-Fi Direct'));
  });

  test('local bit with group bit is not a factory address', () {
    const ble = Observation(key: 'BLE:5B:AF:C8:11:22:33', kind: RadioKind.ble, mac: '5B:AF:C8:11:22:33');
    expect(DeviceExplain.addressExplain(ble, addressType: 'Public'), 'Custom · fixed');
    const pub = Observation(key: 'BLE:00:00:0C:11:22:33', kind: RadioKind.ble, mac: '00:00:0C:11:22:33');
    expect(DeviceExplain.addressExplain(pub, addressType: 'Public'), 'Factory · fixed');
  });

  test('wifi local-bit bssid is not a rotating privacy mac', () {
    final text = DeviceExplain.addressExplain(_wifi('02:0A:F5:86:56:DD', 'PS-CRADLEPOINT'));
    expect(text, 'Custom · fixed');
    expect(text.contains('changes'), isFalse);
  });

  test('rssi 127 is not available', () {
    expect(DeviceExplain.rssiExplain(127), 'Not available');
    expect(DeviceExplain.rssiBand(127), 'not available');
  });

  test('unknown signature name is not a product guess', () {
    final g = DeviceExplain.guess(_wifi('02:11:22:33:44:56', 'DIRECT-ab-TV'), ['Unknown Signature']);
    expect(g.headline.toLowerCase().contains('unknown'), isFalse);
    expect(g.headline, contains('Wi-Fi Direct'));
  });

  test('airpods proximity pairing gives high confidence', () {
    const o = Observation(
      key: 'BLE:AA',
      kind: RadioKind.ble,
      mac: '7A:00:00:00:00:01',
      mfgRecords: [MfgRecord(0x004C, '0707010F2051981100')],
    );
    final g = DeviceExplain.guess(o, []);
    expect(g.confidence, Confidence.high);
    expect(g.headline, 'Most likely AirPods (2nd generation)');
    expect(DeviceExplain.title(g), 'AirPods (2nd generation)');
    expect(DeviceExplain.title(const Guess('Probably a phone', '', Confidence.medium)), 'Probably a phone');
  });
}
