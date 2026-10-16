import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/kin_index.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/vendor_class.dart';

void main() {
  VendorClass.loadTable([for (final a in VendorClass.tableAssets) File(a).readAsStringSync()]);

  test('name stem strips serial tails but keeps words ending in hex letters', () {
    expect(KinIndex.nameStem('Widget_A1B2'), 'widget');
    expect(KinIndex.nameStem('TEST-0000B8'), 'test');
    expect(KinIndex.nameStem('Bed'), 'bed');
    expect(KinIndex.nameStem('Coffee'), 'coffee');
    expect(KinIndex.nameStem('Sensor 12'), 'sensor');
    expect(KinIndex.nameStem('AB'), isNull);
  });

  test('only custom 128-bit service layouts form a kin shape', () {
    const platform = Observation(key: 'B:1', kind: RadioKind.ble, mac: '', mfgRecords: [MfgRecord(0x004C, '1005')]);
    expect(KinIndex.advShape(platform), isNull);
    const sigOnly = Observation(key: 'B:2', kind: RadioKind.ble, mac: '', serviceUuids: ['FEED'], mfgRecords: [MfgRecord(0x0059, '0102')]);
    expect(KinIndex.advShape(sigOnly), isNull);
    const custom = Observation(key: 'B:3', kind: RadioKind.ble, mac: '', serviceUuids: ['6E400001-B5A3-F393-E0A9-E50E24DCCA9E']);
    expect(KinIndex.advShape(custom), isNotNull);
  });

  test('unknown device inherits a confident sibling label one step lower', () {
    final reg = DeviceRegistry(engine: SignatureEngine(const []));
    reg.ingest(const Observation(key: 'BLE:1', kind: RadioKind.ble, mac: '', name: 'Widget 01', serviceUuids: ['180D'], lastSeenMs: 1));
    expect(reg.devices.single.guess.confidence, Confidence.high);
    reg.ingest(const Observation(key: 'BLE:2', kind: RadioKind.ble, mac: '', name: 'Widget 02', lastSeenMs: 2));
    final g = reg.devices.firstWhere((d) => d.obs.key == 'BLE:2').guess;
    expect(g.headline, 'Probably a heart-rate monitor');
    expect(g.confidence, Confidence.medium);
    expect(g.because, contains('name pattern'));
    reg.ingest(const Observation(key: 'BLE:3', kind: RadioKind.ble, mac: '', name: 'Other', lastSeenMs: 3));
    expect(DeviceExplain.isGeneric(reg.devices.firstWhere((d) => d.obs.key == 'BLE:3').guess), isTrue);
  });

  test('wifi never inherits kin', () {
    final reg = DeviceRegistry(engine: SignatureEngine(const []));
    reg.ingest(const Observation(key: 'WIFI:A', kind: RadioKind.wifi, mac: '02:00:00:00:00:01', name: 'TestNet', isAp: true));
    expect(reg.kinIndex.lookup(const Observation(key: 'WIFI:B', kind: RadioKind.wifi, mac: '', name: 'TestNet')), isNull);
  });

  test('AP vendor with an AP-context rule replaces the generic access-point label', () {
    const ap = Observation(key: 'WIFI:M', kind: RadioKind.wifi, mac: '00:11:22:33:44:55', name: 'TestNet', isAp: true);
    expect(DeviceExplain.guess(ap, const [], vendor: 'Motorola Mobility LLC, a Lenovo Company').headline,
        'Probably a Motorola phone hotspot');
    expect(DeviceExplain.guess(ap, const [], vendor: 'Kenwood Corporation').headline, 'Probably a Wi-Fi access point');
  });

  test('BLE keeps chip labels; Wi-Fi gets the Wi-Fi chip label', () {
    const ble = Observation(key: 'B:T', kind: RadioKind.ble, mac: '00:11:22:33:44:55');
    const ap = Observation(key: 'W:T', kind: RadioKind.wifi, mac: '00:11:22:33:44:55', isAp: true);
    expect(VendorClass.hint(ble, 'Texas Instruments')!.label, contains('BLE beacon'));
    expect(VendorClass.hint(ap, 'Texas Instruments')!.label, contains('Wi-Fi IoT'));
  });

  test('locally-administered AP BSSID resolves through its base vendor', () {
    final reg = DeviceRegistry(
      engine: SignatureEngine(const []),
      vendorOf: (mac) => hexOnly(mac).startsWith('001122') ? 'Google, Inc.' : null,
    );
    reg.ingest(const Observation(key: 'WIFI:L', kind: RadioKind.wifi, mac: '02:11:22:33:44:55', name: 'TestNet', isAp: true));
    final d = reg.devices.single;
    expect(d.vendor, isNull);
    expect(d.baseVendor, 'Google, Inc.');
    expect(d.guess.headline, startsWith('Probably a Google Wifi'));
    expect(d.guess.because, contains('locally-administered'));
  });
}
