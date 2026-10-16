import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/ble_class.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/observation.dart';

Observation _ble({List<MfgRecord> mfg = const [], List<String> uuids = const [],
        List<ServiceDataRecord> sd = const [], int? appearance}) =>
    Observation(
      key: 'BLE:AA',
      kind: RadioKind.ble,
      mac: 'C0:11:22:33:44:55',
      mfgRecords: mfg,
      serviceUuids: uuids,
      serviceData: sd,
      appearance: appearance,
    );

void main() {
  test('tables sorted-unique and labels well formed', () {
    for (final t in [bleUuid16Class, bleCompanyClass]) {
      expect(t.length, greaterThan(100));
      expect(t.values.every((v) => v.contains('-')), isTrue);
    }
  });

  test('company id hint', () {
    final h = BleClass.hints(_ble(mfg: [const MfgRecord(0x09C8, '0102')]));
    expect(h.single.bucket, 'camera');
    expect(h.single.label, 'a Flock camera');
  });

  test('128-bit base uuid folds to 16-bit', () {
    final h = BleClass.hints(_ble(uuids: ['0000FD5F-0000-1000-8000-00805F9B34FB']));
    expect(h.single.label, contains('Meta'));
  });

  test('samsung smarttag subtype and eddystone url', () {
    final h = BleClass.hints(_ble(
      mfg: [const MfgRecord(0x0075, '4209AA')],
      sd: [const ServiceDataRecord('FEAA', '10FF')],
    ));
    expect(h.map((e) => e.label), containsAll(['a Samsung SmartTag', 'an Eddystone-URL beacon']));
  });

  test('appearance reaches guess when nothing else matches', () {
    final g = DeviceExplain.guess(_ble(appearance: 0x00C1), const []);
    expect(g.headline, contains('a sports watch'));
    expect(DeviceExplain.guess(_ble(appearance: 0x00C0), const []).headline, contains('a watch'));
  });

  test('appearance categories follow SIG assigned numbers', () {
    String label(int a) => BleClass.hints(_ble(appearance: a)).single.label;
    expect(label(0x0340), 'a heart-rate sensor');
    expect(label(0x0380), 'a blood-pressure monitor');
    expect(label(0x0580), 'a light fixture');
    expect(label(0x0900), 'a home appliance');
    expect(label(0x0C40), 'a pulse oximeter');
    expect(label(0x08C1), 'a car');
    expect(label(0x0842), 'a soundbar');
  });

  test('empty adv yields no hints', () {
    expect(BleClass.hints(_ble()), isEmpty);
  });
}
