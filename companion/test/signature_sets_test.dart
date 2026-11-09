import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/signature_sets.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _builtIn = [
  Signature(
    id: 'fleet-known',
    name: 'Known',
    kind: SignatureClass.home,
    rules: [MatchRule(RuleKind.nameGlob, text: 'KNOWN-*'), MatchRule(RuleKind.manufacturerId, companyId: 0x1234)],
  ),
  Signature(
    id: 'fleet-mihome',
    name: 'Mi Home',
    kind: SignatureClass.home,
    rules: [MatchRule(RuleKind.serviceUuid, text: 'FE95')],
  ),
  Signature(
    id: 'fleet-ha-covered',
    name: 'Covered',
    kind: SignatureClass.home,
    rules: [MatchRule(RuleKind.nameGlob, text: 'COV*', radio: RadioKind.ble)],
    notes: 'Bluetooth matcher from the Home Assistant covered integration (homeassistant/generated/bluetooth.py).',
  ),
];

Map<String, dynamic> _rule(String kind, {String text = '', int companyId = 0, String prefix = ''}) =>
    {'kind': kind, 'text': text, 'companyId': companyId, 'dataPrefixHex': prefix, 'radio': null, 'enabled': true};

String _pack(List<Map<String, dynamic>> fleets, {String format = 'fieldwatch-signatures'}) =>
    jsonEncode({'format': format, 'formatVersion': 1, 'fleets': fleets});

Map<String, dynamic> _fleet(String id, List<Map<String, dynamic>> rules, {bool matchAny = true, String kind = 'HOME'}) =>
    {'id': id, 'name': id.toUpperCase(), 'enabled': true, 'matchAny': matchAny, 'kind': kind, 'rules': rules};

const _haText = '''
"""Automatically generated file."""

from typing import Final

BLUETOOTH: Final[list[dict[str, bool | str | int | list[int]]]] = [
    {
        "domain": "example_ble",
        "local_name": "EXM-*",
    },
    {
        "connectable": True,
        "domain": "example_ble",
        "manufacturer_data_start": [1, 2],
        "manufacturer_id": 65535,
    },
    {
        "domain": "ibeacon",
        "manufacturer_data_start": [2, 21],
        "manufacturer_id": 76,
    },
    {
        "domain": "covered",
        "local_name": "COVX*",
    },
    {
        "domain": "broad",
        "manufacturer_id": 76,
    },
    {
        "domain": "generic_ble",
        "manufacturer_id": 89,
    },
    {
        "domain": "mi_ble",
        "service_data_uuid": "0000fe95-0000-1000-8000-00805f9b34fb",
    },
    {
        "domain": "generic_ble",
        "service_data_uuid": "0000181d-0000-1000-8000-00805f9b34fb",
    },
    {
        "domain": "generic_ble",
        "local_name": "Jar*",
    },
    {
        "connectable": False,
        "domain": "both_ble",
        "service_data_uuid": "0000fff1-0000-1000-8000-00805f9b34fb",
        "service_uuid": "0000fff0-0000-1000-8000-00805f9b34fb",
    },
]
''';

Observation _ble({String name = '', List<String> uuids = const [], List<ServiceDataRecord> data = const [], List<MfgRecord> mfg = const []}) =>
    Observation(key: 'BLE:02:00:00:00:00:01', kind: RadioKind.ble, mac: '02:00:00:00:00:01', name: name, serviceUuids: uuids, serviceData: data, mfgRecords: mfg);

void main() {
  final idx = BuiltInIndex.of(_builtIn);

  group('Fieldwatch packs', () {
    test('skips known ids and covered rules, namespaces ids, forces alerts off and drops decode maps', () {
      final sigs = SetParser.fieldwatch(
        _pack([
          _fleet('fleet-known', [_rule('NAME_GLOB', text: 'OTHER-*')]),
          _fleet('fleet-dup', [_rule('NAME_GLOB', text: 'known-*')]),
          _fleet('fleet-dup-uuid', [_rule('SERVICE_UUID', text: '0000fe95-0000-1000-8000-00805f9b34fb')]),
          {
            ..._fleet('fleet-new', [_rule('NAME_GLOB', text: 'NEW-*'), _rule('MANUFACTURER_ID', companyId: 0x1234)]),
            'alert': true,
            'decode': {'fields': []},
          },
        ]),
        idx,
        'fw',
      );
      expect(sigs.map((s) => s.id), ['set:fw:fleet-new']);
      expect(sigs.single.rules.map((r) => r.text), ['NEW-*']);
      expect(sigs.single.alert, isFalse);
      expect(sigs.single.decode, isNull);
    });

    test('drops wide globs, and AND entries that lost a rule or are covered', () {
      final sigs = SetParser.fieldwatch(
        _pack([
          _fleet('fleet-stars', [_rule('NAME_GLOB', text: '*a*b*c*'), _rule('NAME_GLOB', text: 'OK-*')]),
          _fleet('fleet-and-unknown', [_rule('NAME_GLOB', text: 'A-*'), _rule('FUTURE_KIND', text: 'x')], matchAny: false),
          _fleet('fleet-and-covered', [_rule('MANUFACTURER_ID', companyId: 0x1234), _rule('SERVICE_UUID', text: 'FFF0')], matchAny: false),
          _fleet('fleet-and-new', [_rule('MANUFACTURER_ID', companyId: 0x4321), _rule('SERVICE_UUID', text: 'FFF0')], matchAny: false),
        ]),
        idx,
        'fw',
      );
      expect(sigs.map((s) => s.id), ['set:fw:fleet-stars', 'set:fw:fleet-and-new']);
      expect(sigs.first.rules.map((r) => r.text), ['OK-*']);
    });

    test('rejects files that are not signature packs', () {
      expect(() => SetParser.fieldwatch('nope', idx, 'x'), throwsA(isA<SetError>()));
      expect(() => SetParser.fieldwatch(_pack(const [], format: 'other'), idx, 'x'), throwsA(isA<SetError>()));
    });

    test('an exported set reads back as a set', () {
      const mine = Signature(
        id: 'user-1',
        name: 'Mine',
        kind: SignatureClass.finder,
        rules: [MatchRule(RuleKind.serviceUuid, text: 'FFE0', radio: RadioKind.ble)],
        alert: true,
      );
      final back = SetParser.fieldwatch(SetParser.exportPack(const [mine]), idx, 'c1').single;
      expect((back.id, back.name, back.kind, back.rules.single.text, back.alert), ('set:c1:user-1', 'Mine', SignatureClass.finder, 'FFE0', false));
    });
  });

  group('Home Assistant file', () {
    test('converts matchers, skips iBeacon, chip-vendor, standard-service, short-glob and covered matchers', () {
      final sigs = SetParser.homeAssistant(_haText, idx, 'ha');
      expect(sigs.map((s) => s.name), ['Example', 'Example', 'Both']);
      expect(sigs.every((s) => s.kind == SignatureClass.home && !s.alert), isTrue);
      final engine = SignatureEngine(sigs);
      expect(engine.match(_ble(name: 'EXM-7')), hasLength(1));
      expect(engine.match(_ble(mfg: const [MfgRecord(0xFFFF, '0102AA')])), hasLength(1));
      expect(engine.match(_ble(mfg: const [MfgRecord(0xFFFF, '0203')])), isEmpty);
      expect(engine.match(_ble(uuids: const ['FFF0'])), isEmpty);
      expect(engine.match(_ble(uuids: const ['FFF0'], data: const [ServiceDataRecord('FFF1', '00')])), hasLength(1));
    });

    test('a changed file format is reported, not guessed', () {
      expect(() => SetParser.homeAssistant('BLUETOOTH = [ {"domain": oops} ]', idx, 'ha'), throwsA(isA<SetError>()));
      expect(() => SetParser.homeAssistant('nothing here', idx, 'ha'), throwsA(isA<SetError>()));
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('sets');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    SignatureSets make(Future<String> Function(Uri) fetch) =>
        SignatureSets(fetch: fetch, dir: () async => dir, builtIn: () async => _builtIn);

    test('turning a preset on downloads it once, and it reloads from disk', () async {
      final asked = <Uri>[];
      final a = make((u) async {
        asked.add(u);
        return _pack([_fleet('fleet-new', [_rule('NAME_GLOB', text: 'NEW-*')])]);
      });
      await a.loaded;
      expect(a.sets.map((s) => s.id), ['fieldwatch', 'home-assistant']);
      await a.setEnabled('fieldwatch', true);
      expect(asked.single.host, 'raw.githubusercontent.com');
      expect(a.signatures.map((s) => s.id), ['set:fieldwatch:fleet-new']);
      await a.setEnabled('fieldwatch', false);
      expect(a.signatures, isEmpty);
      await a.setEnabled('fieldwatch', true);
      expect(asked, hasLength(1));
      final b = make((u) async => throw StateError('no network expected'));
      await b.loaded;
      expect(b.signatures.map((s) => s.id), ['set:fieldwatch:fleet-new']);
      expect(b.sets.first.count, 1);
    });

    test('a failed download shows its error and keeps the old copy', () async {
      var fail = false;
      final a = make((u) async {
        if (fail) throw const SetError('Download failed: HTTP 404.');
        return _pack([_fleet('fleet-new', [_rule('NAME_GLOB', text: 'NEW-*')])]);
      });
      await a.setEnabled('fieldwatch', true);
      fail = true;
      await a.update('fieldwatch');
      expect(a.sets.first.error, 'Download failed: HTTP 404.');
      expect(a.busy, isEmpty);
      expect(a.signatures, hasLength(1));
    });

    test('own sets: https links only, bad files are refused, removal deletes the copy', () async {
      final a = make((u) async => _pack([_fleet('fleet-mine', [_rule('NAME_GLOB', text: 'MINE-*')])]));
      expect(() => a.addLink('http://example.com/s.json', ''), throwsA(isA<SetError>()));
      await a.addLink('https://example.com/s.json', '');
      final link = a.sets.last;
      expect((link.name, link.enabled, link.count), ('example.com', true, 1));
      await expectLater(a.addFile('not json', 'bad'), throwsA(isA<SetError>()));
      expect(a.sets, hasLength(3));
      await a.addFile(_pack([_fleet('fleet-file', [_rule('NAME_GLOB', text: 'FILE-*')])]), 'Mine');
      expect(a.signatures.map((s) => s.name), ['FLEET-MINE', 'FLEET-FILE']);
      final file = File('${dir.path}/signature_sets/${link.id}.json');
      expect(file.existsSync(), isTrue);
      await a.remove(link.id);
      expect(file.existsSync(), isFalse);
      await a.remove('fieldwatch');
      expect(a.sets.map((s) => s.id), contains('fieldwatch'));
    });
  });

  test('set signatures follow class alert settings', () {
    final sig = SetParser.homeAssistant(_haText, idx, 'ha').first;
    final reg = DeviceRegistry(engine: SignatureEngine(const []));
    reg.setExtraSignatures([sig]);
    reg.ingest(_ble(name: 'EXM-1'));
    final d = reg.devices.single;
    expect(d.signatures.single.id, sig.id);
    expect(classAlertOf(d, const {}, flock: false), isNull);
    expect(classAlertOf(d, const {SignatureClass.home}, flock: false)?.kind, 'home');
    reg.dispose();
  });
}
