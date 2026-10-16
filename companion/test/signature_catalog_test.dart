import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    expect(sigs.length, 305);
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

  test('phone-scanned watch name classifies as wearable', () {
    const o = Observation(key: 'BLE:A967F874', kind: RadioKind.ble, mac: '', name: 'Brian’s Samsung Watch');
    final hits = engine.match(o);
    expect(hits.map((s) => s.id), contains('fleet-smartwatch'));
    expect(hits.first.kind, SignatureClass.wearable);
    const guard = Observation(key: 'BLE:X', kind: RadioKind.ble, mac: '', name: 'WatchGuard VISTA');
    expect(engine.match(guard).map((s) => s.id), isNot(contains('fleet-smartwatch')));
  });
}
