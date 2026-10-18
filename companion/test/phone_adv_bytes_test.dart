import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/core/classify/device_registry.dart';

void main() {
  test('phone advertisement survives conversion to AD bytes', () {
    final a = AdvertisementData(
      advName: 'Tag',
      txPowerLevel: null,
      appearance: 0x0200,
      connectable: false,
      manufacturerData: {0x004C: [0x12, 0x19]},
      serviceData: {Guid('FEAA'): [0x10, 0x00]},
      serviceUuids: [Guid('180F')],
    );
    final p = parseAdvStructures(PhoneBleSource.advBytes(a));
    expect(p.name, 'Tag');
    expect(p.appearance, 0x0200);
    expect(p.mfg.single.companyId, 0x004C);
    expect(p.serviceUuids.single.toUpperCase(), contains('180F'));
    expect(p.serviceData.single.uuid.toUpperCase(), contains('FEAA'));
  });

  test('Android Wi-Fi frequency and capabilities map to channel and auth', () {
    expect(PhoneBleSource.wifiChannel(2412), 1);
    expect(PhoneBleSource.wifiChannel(2484), 14);
    expect(PhoneBleSource.wifiChannel(5180), 36);
    expect(PhoneBleSource.wifiChannel(5955), 1);
    expect(PhoneBleSource.wifiAuthMode('[WPA2-PSK-CCMP][ESS]'), 3);
    expect(PhoneBleSource.wifiAuthMode('[WPA-PSK-CCMP][WPA2-PSK-CCMP][ESS]'), 4);
    expect(PhoneBleSource.wifiAuthMode('[RSN-SAE-CCMP][ESS]'), 6);
    expect(PhoneBleSource.wifiAuthMode('[WPA2-EAP-CCMP][ESS]'), 5);
    expect(PhoneBleSource.wifiAuthMode('[ESS]'), 0);
  });
}
