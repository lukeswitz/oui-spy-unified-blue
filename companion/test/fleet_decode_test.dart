import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/fleet_decode.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

void main() {
  final byId = {
    for (final s in Signature.parseCatalog(File('assets/fieldwatch-signatures-v2.json').readAsStringSync())) s.id: s,
  };

  test('catalog decode maps parse (19 fleets carry one)', () {
    expect(byId.values.where((s) => s.decode != null).length, 19);
  });

  test('Remote ID location height reference and EU system fields decode', () {
    Map<String, String> decode(String hex) => {
          for (final d in FleetDecode.decode(
              byId['fleet-remote-id']!.decode!,
              Observation(key: 'B:R', kind: RadioKind.ble, mac: '', serviceData: [ServiceDataRecord('FFFA', hex)])))
            d.label: d.display,
        };
    final loc = decode('0D011224${'00' * 23}');
    expect(loc['Height above'], 'Ground');
    final eu = decode('0D014205${'00' * 15}239808${'00' * 5}');
    expect(eu['Operator position'], 'Live GNSS');
    expect(eu['EU category'], 'Specific');
    expect(eu['EU class'], 'C2');
    expect(eu['Operator altitude (HAE)'], startsWith('100'));
    final us = decode('0D014201${'00' * 15}230000${'00' * 5}');
    expect(us.containsKey('EU category'), isFalse);
    expect(us.containsKey('Operator altitude (HAE)'), isFalse);
  });

  test('Ruuvi RAWv5 published vector decodes temperature/humidity/pressure', () {
    const o = Observation(
      key: 'B:1',
      kind: RadioKind.ble,
      mac: 'C0:11:22:33:44:55',
      mfgRecords: [MfgRecord(0x0499, '0512FC5394C37C0004FFFC040CAC364200CDCBB8334C884F')],
    );
    final f = {for (final d in FleetDecode.decode(byId['fleet-ruuvi']!.decode!, o)) d.label: d.display};
    expect(f['Temperature'], '24.3 °C');
    expect(f['Humidity'], '53.49 %');
    expect(f['Pressure'], '1000.44 hPa');
  });

  test('Find Hub separated frame shows enum label and note', () {
    const o = Observation(
      key: 'B:2',
      kind: RadioKind.ble,
      mac: 'C0:11:22:33:44:56',
      serviceData: [ServiceDataRecord('FEAA', '410102030405060708090A0B0C0D0E0F1011121314')],
    );
    final mode = FleetDecode.decode(byId['fleet-find-hub']!.decode!, o).firstWhere((d) => d.label == 'Mode');
    expect(mode.display, 'separated');
    expect(mode.live, isTrue);
    expect(mode.emphasis, isTrue);
    expect(mode.note, startsWith('Separated from its owner.'));
  });

  test('gate blocks wrong format; short payload yields nothing', () {
    const o = Observation(
      key: 'B:3',
      kind: RadioKind.ble,
      mac: 'C0:11:22:33:44:57',
      mfgRecords: [MfgRecord(0x0499, '0312')],
    );
    final f = FleetDecode.decode(byId['fleet-ruuvi']!.decode!, o).map((d) => d.label);
    expect(f, isNot(contains('Temperature')));
  });
}
