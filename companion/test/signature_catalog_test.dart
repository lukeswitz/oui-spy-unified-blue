import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

void main() {
  final sigs = Signature.parseCatalog(File('assets/fieldwatch-signatures-v2.json').readAsStringSync());
  final byId = {for (final s in sigs) s.id: s};
  final engine = SignatureEngine(sigs);

  test('Home Assistant sourced matchers classify their products', () {
    List<String> ids(Observation o) => [for (final s in engine.match(o)) s.id];
    expect(ids(const Observation(key: 'B:1', kind: RadioKind.ble, mac: '', name: 'Triones-ABC')), contains('fleet-ha-led-ble'));
    expect(ids(const Observation(key: 'B:2', kind: RadioKind.ble, mac: '', name: 'CC-RT-BLE')), contains('fleet-ha-eq3'));
    expect(ids(const Observation(key: 'B:3', kind: RadioKind.ble, mac: '', serviceUuids: ['B42E1C08-ADE7-11E4-89D3-123B93F75CBA'])),
        contains('fleet-ha-airthings'));
    expect(ids(const Observation(key: 'B:4', kind: RadioKind.ble, mac: '', mfgRecords: [MfgRecord(0x004C, '0215A495BB10')])),
        contains('fleet-ha-tilt'));
    expect(ids(const Observation(key: 'B:5', kind: RadioKind.ble, mac: '', serviceData: [ServiceDataRecord('FCD2', '40')])),
        contains('fleet-ha-bthome'));
    expect(ids(const Observation(key: 'B:6', kind: RadioKind.ble, mac: '', name: 'Unrelated')), isEmpty);
    expect(ids(const Observation(key: 'B:7', kind: RadioKind.ble, mac: '', name: 'SBMO-ABCD')), contains('fleet-te-shelly-motion'));
    expect(ids(const Observation(key: 'B:8', kind: RadioKind.ble, mac: '', mfgRecords: [MfgRecord(0x094F, '0100AA')])),
        contains('fleet-te-mikrotik-tag'));
    expect(ids(const Observation(key: 'B:9', kind: RadioKind.ble, mac: '', mfgRecords: [MfgRecord(0x0702, '01')])),
        contains('fleet-ha-aranet'));
  });

  test('catalog parses with expected stock rows', () {
    expect(sigs.length, 312);
    final ray = byId['fleet-rayneo']!;
    expect(ray.matchAny, isFalse);
    expect(ray.rules.length, 2);
    expect(ray.rules.singleWhere((r) => r.kind == RuleKind.manufacturerId).companyId, 0x0BC6);
    expect(ray.rules.singleWhere((r) => r.kind == RuleKind.nameGlob).text, 'RayNeo*');
    expect(byId['fleet-even-g1']!.rules.any((r) => r.kind == RuleKind.manufacturerId && r.companyId == 0x10F9),
        isTrue);
    final lite = byId['fleet-liteon-camera-radio']!;
    final ouis = lite.rules.where((r) => r.kind == RuleKind.oui).map((r) => r.text.toUpperCase()).toSet();
    expect(ouis, containsAll(['E0:0A:F6', '14:B5:CD']));
    final rid = byId['fleet-remote-id']!;
    for (final o in ['6A:5C:35', 'FA:0B:BC']) {
      expect(rid.rules.any((r) => r.kind == RuleKind.vendorIeOui && r.text.toUpperCase() == o), isTrue);
    }
    expect(byId['fleet-tello']!.rules.map((r) => r.text).toSet(), {'TELLO*', 'RMTT*'});
    expect(byId['fleet-crazyflie']!.rules.any((r) => r.kind == RuleKind.manufacturerId), isFalse);
    expect(byId['fleet-parrot']!.rules.any((r) => r.kind == RuleKind.nameGlob && r.text == 'Skycontroller*'),
        isTrue);
  });

  test('rayneo needs both company id and name', () {
    Observation ble(String name) => Observation(
          key: 'BLE:AA:BB:CC:DD:EE:01',
          kind: RadioKind.ble,
          mac: 'AA:BB:CC:DD:EE:01',
          name: name,
          mfgRecords: const [MfgRecord(0x0BC6, '0102')],
        );
    expect(engine.match(ble('RayNeo X2')).map((s) => s.id), contains('fleet-rayneo'));
    expect(engine.match(ble('Other')).map((s) => s.id), isNot(contains('fleet-rayneo')));
  });

  test('liteon oui matches wifi bssid', () {
    const o = Observation(key: 'WIFI:E0:0A:F6:11:22:33', kind: RadioKind.wifi, mac: 'E0:0A:F6:11:22:33');
    expect(engine.match(o).map((s) => s.id), contains('fleet-liteon-camera-radio'));
  });

  test('remote id vendor ie matches', () {
    const o = Observation(
      key: 'WIFI:60:60:1F:06:31:08',
      kind: RadioKind.wifi,
      mac: '60:60:1F:06:31:08',
      vendorIeOuis: ['FA:0B:BC'],
    );
    expect(engine.match(o).map((s) => s.id), contains('fleet-remote-id'));
  });

  test('rows written from verified identifiers match', () {
    List<String> ids(Observation o) => [for (final s in engine.match(o)) s.id];
    Observation ble({List<String> uuids = const [], List<MfgRecord> mfg = const [], String name = ''}) =>
        Observation(key: 'BLE:X', kind: RadioKind.ble, mac: '', name: name, serviceUuids: uuids, mfgRecords: mfg);
    Observation wifi(String ssid, {List<String> ies = const []}) => Observation(
          key: 'WIFI:02:00:00:00:00:01',
          kind: RadioKind.wifi,
          mac: '02:00:00:00:00:01',
          name: ssid,
          vendorIeOuis: ies,
        );
    expect(ids(ble(uuids: ['F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C'])), contains('fleet-bitchat'));
    expect(ids(ble(uuids: ['FE95'])), contains('fleet-xiaomi-mihome'));
    expect(ids(ble(uuids: ['FE33'])), contains('fleet-chipolo'));
    expect(ids(ble(uuids: ['FEEC'])), contains('fleet-tile'));
    for (final u in ['3080', '3081', '3082', '3083']) {
      expect(ids(ble(uuids: [u])), contains('fleet-flipper'));
    }
    expect(ids(ble(mfg: const [MfgRecord(0x006B, '00')])), contains('fleet-polar'));
    expect(ids(ble(uuids: ['FEEE', 'FEA5'])), allOf(contains('fleet-polar'), isNot(contains('fleet-gopro'))));
    expect(ids(ble(uuids: ['FEA5'])), contains('fleet-gopro'));
    expect(ids(wifi('ExpressLRS TX')), contains('fleet-elrs'));
    expect(ids(wifi('EZVIZ_123456789')), contains('fleet-ezviz'));
    expect(ids(wifi('', ies: ['26:37:12'])), contains('fleet-dji'));
    expect(ids(ble(uuids: ['FD5A'])), contains('fleet-smarttag'));
    expect(ids(ble(mfg: const [MfgRecord(0x0075, '0100')])), isNot(contains('fleet-smarttag')));
  });

  test('new rows get a plain explanation, not just their name', () {
    const o = Observation(key: 'WIFI:X', kind: RadioKind.wifi, mac: '', name: 'EZVIZ_123456789', isAp: true);
    expect(DeviceExplain.guess(o, ['EZVIZ']).headline, contains('EZVIZ camera or doorbell'));
    const p = Observation(key: 'BLE:X', kind: RadioKind.ble, mac: '');
    expect(DeviceExplain.guess(p, ['Polar']).headline, contains('Polar heart-rate strap'));
    expect(DeviceExplain.guess(p, ['Bitchat']).headline, contains('Bitchat'));
  });

  test('a Silicon Labs radio is not a Flock battery; the battery name is', () {
    List<String> ids(Observation o) => [for (final s in engine.match(o)) s.id];
    for (final mac in ['94:34:69:00:00:01', '04:0D:84:00:00:01', 'F0:82:C0:00:00:01']) {
      expect(ids(Observation(key: 'BLE:$mac', kind: RadioKind.ble, mac: mac)), isNot(contains('fleet-fs-ext-battery')));
    }
    expect(ids(const Observation(key: 'BLE:X', kind: RadioKind.ble, mac: '', name: 'FS Ext 12')), contains('fleet-fs-ext-battery'));
    const lite = Observation(key: 'WIFI:B8:35:32:00:00:01', kind: RadioKind.wifi, mac: 'B8:35:32:00:00:01');
    expect(ids(lite), isNot(contains('fleet-liteon-camera-radio')));
  });

  test('iOS-scanned Apple adverts without a MAC classify', () {
    List<String> ids(String hex) =>
        [for (final s in engine.match(Observation(key: 'BLE:UUID', kind: RadioKind.ble, mac: '', mfgRecords: [MfgRecord(0x004C, hex)]))) s.id];
    expect(ids('1005431C1A2B3C'), contains('fleet-apple-device'));
    expect(ids('0C0E00AABBCCDD'), contains('fleet-apple-device'));
    expect(ids('07190110200455AA'), contains('fleet-apple-audio'));
    expect(ids('0B0501020304'), contains('fleet-apple-watch'));
    expect(ids('1219' '00' * 25), isNotEmpty);
  });

  test('blank connectable iOS advert is a hidden Apple device until a GATT probe says which', () {
    List<String> ids(Observation o) => [for (final s in engine.match(o)) s.id];
    const blank = Observation(key: 'BLE:U1', kind: RadioKind.ble, mac: '', iosConnectable: true);
    expect(ids(blank), ['ios-apple-hidden']);
    expect(ids(const Observation(key: 'BLE:U2', kind: RadioKind.ble, mac: '')), isEmpty);
    expect(ids(const Observation(key: 'BLE:U3', kind: RadioKind.ble, mac: '', iosConnectable: true, name: 'Thing')), isEmpty);
    Observation probed(List<String> svcs, [String model = '']) =>
        blank.merge(Observation(key: 'BLE:U1', kind: RadioKind.ble, mac: '', gattServices: svcs, gattModel: model));
    expect(ids(probed(['0000FD44-0000-1000-8000-00805F9B34FB'])), ['fleet-airtag']);
    expect(ids(probed(['0000FD43-0000-1000-8000-00805F9B34FB', gattFindMyInfoService], 'left')), ['fleet-apple-audio']);
    expect(ids(probed([gattFindMyInfoService], 'AirPods Pro')), ['fleet-apple-audio']);
    expect(ids(probed(['00001800-0000-1000-8000-00805F9B34FB', gattAncsService])), ['fleet-apple-device']);
    expect(ids(probed(['00001800-0000-1000-8000-00805F9B34FB'])), ['ios-apple-hidden']);
    expect(probed([gattAmsService]).iosConnectable, isTrue);
  });

  test('phone-scanned watch name classifies as wearable', () {
    const o = Observation(key: 'BLE:A967F874', kind: RadioKind.ble, mac: '', name: 'Brian’s Samsung Watch');
    final hits = engine.match(o);
    expect(hits.map((s) => s.id), contains('fleet-smartwatch'));
    expect(hits.first.kind, SignatureClass.wearable);
    const guard = Observation(key: 'BLE:X', kind: RadioKind.ble, mac: '', name: 'WatchGuard VISTA');
    expect(engine.match(guard).map((s) => s.id), isNot(contains('fleet-smartwatch')));
  });
}
