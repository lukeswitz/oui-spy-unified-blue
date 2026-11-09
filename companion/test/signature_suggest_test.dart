import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/signature_suggest.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Observation _obs(
  int n, {
  String name = '',
  List<String> uuids = const [],
  List<ServiceDataRecord> data = const [],
  List<int> companies = const [],
  String? mac,
}) {
  final m = mac ?? '02:00:00:00:00:0$n';
  return Observation(
    key: 'BLE:$m',
    kind: RadioKind.ble,
    mac: m,
    name: name,
    serviceUuids: uuids,
    serviceData: data,
    mfgRecords: [for (final c in companies) MfgRecord(c, '0102')],
    lastSeenMs: n,
  );
}

ClassifiedDevice _dev(Observation o, {String? vendor}) => ClassifiedDevice(o, const [], const {'esp32'}, vendor: vendor);

List<ClassifiedDevice> _three(Observation Function(int n) f, {String? vendor}) =>
    [for (var n = 1; n <= 3; n++) _dev(f(n), vendor: vendor)];

void main() {
  test('3 unclassified radios sharing a service become a service rule', () {
    final s = SignatureSuggest.of(_three((n) => _obs(n, uuids: const ['FFE0'])));
    expect(s.single.kind, SuggestionKind.uuid);
    expect(s.single.devices, hasLength(3));
    expect((s.single.matchRule.kind, s.single.matchRule.text), (RuleKind.serviceUuid, 'FFE0'));
  });

  test('service data and custom 128-bit services group too', () {
    final sd = SignatureSuggest.of(_three((n) => _obs(n, data: const [ServiceDataRecord('FFE1', '01')])));
    expect(sd.single.key, 'FFE1');
    final long = SignatureSuggest.of(_three((n) => _obs(n, uuids: const ['6e400001b5a3f393e0a9e50e24dcca9e'])));
    expect(long.single.key, '6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  });

  test('two radios are not a group', () {
    expect(SignatureSuggest.of([_dev(_obs(1, uuids: const ['FFE0'])), _dev(_obs(2, uuids: const ['FFE0']))]), isEmpty);
  });

  test('a shared vendor prefix on public addresses becomes a MAC prefix rule', () {
    final s = SignatureSuggest.of(_three((n) => _obs(n, mac: '00:11:22:00:00:0$n'), vendor: 'Example Vendor'));
    expect(s.single.kind, SuggestionKind.oui);
    expect((s.single.matchRule.kind, s.single.matchRule.text), (RuleKind.macPrefix, '00:11:22'));
    expect(s.single.defaultName, 'Example Vendor');
    expect(s.single.label(), 'Vendor prefix 00:11:22 (Example Vendor)');
    expect(s.single.label(masked: true), 'Vendor prefix 00:11:XX (Example Vendor)');
  });

  test('randomized addresses never form a vendor prefix group', () {
    expect(SignatureSuggest.of(_three((n) => _obs(n, mac: 'AA:BB:CC:00:00:0$n'), vendor: 'Example Vendor')), isEmpty);
  });

  test('name groups become a name glob and company groups a company rule', () {
    final names = SignatureSuggest.of(_three((n) => _obs(n, name: 'Zyx-0$n')));
    expect(names.single.kind, SuggestionKind.name);
    expect((names.single.matchRule.kind, names.single.matchRule.text), (RuleKind.nameGlob, 'Zyx-*'));
    expect(names.single.defaultName, 'Zyx devices');
    expect(names.single.label(), 'Name like "Zyx-01"');
    final companies = SignatureSuggest.of(_three((n) => _obs(n, companies: const [0xFFFF])));
    expect((companies.single.matchRule.kind, companies.single.matchRule.companyId), (RuleKind.manufacturerId, 0xFFFF));
  });

  test('platform companies and standard GATT services are skipped', () {
    expect(SignatureSuggest.of(_three((n) => _obs(n, uuids: const ['180F'], companies: const [0x004C]))), isEmpty);
  });

  test('identical groups fold into one', () {
    final s = SignatureSuggest.of(_three((n) => _obs(n, name: 'Zyx-0$n', uuids: const ['FFE0'], companies: const [0xFFFF])));
    expect(s.single.kind, SuggestionKind.uuid);
    expect(s.single.also.map((a) => a.kind), [SuggestionKind.name, SuggestionKind.company]);
  });

  test('classified radios are left out', () {
    expect(SignatureSuggest.of(_three((n) => _obs(n, uuids: const ['FD5A']))), isEmpty);
  });

  test('bigger groups come first and the list is capped', () {
    final devices = [
      for (var g = 0; g < 25; g++)
        for (var n = 0; n < 3 + (g == 7 ? 2 : 0); n++)
          _dev(_obs(n, mac: '02:00:00:00:${g.toRadixString(16).padLeft(2, '0')}:0$n', uuids: [(0xFF00 + g).toRadixString(16)])),
    ];
    final s = SignatureSuggest.of(devices);
    expect(s, hasLength(SignatureSuggest.maxGroups));
    expect(s.first.key, 'FF07');
    expect(s.first.devices, hasLength(5));
  });

  test('every group kind saves as a signature the classifier matches on a new radio', () {
    final cases = <(List<ClassifiedDevice>, Observation, Observation)>[
      (_three((n) => _obs(n, name: 'Zyx-0$n')), _obs(9, name: 'zyx-99'), _obs(8, name: 'Zyxel')),
      (_three((n) => _obs(n, uuids: const ['FFE0'])), _obs(9, data: const [ServiceDataRecord('FFE0', '00')]), _obs(8, uuids: const ['FFE2'])),
      (_three((n) => _obs(n, mac: '00:11:22:00:00:0$n'), vendor: 'Example Vendor'), _obs(9, mac: '00:11:22:00:00:09'), _obs(8, mac: '00:11:23:00:00:08')),
      (_three((n) => _obs(n, companies: const [0xFFFF])), _obs(9, companies: const [0xFFFF]), _obs(8, companies: const [0xFFFE])),
    ];
    for (final (group, hit, miss) in cases) {
      final sig = SignatureSuggest.of(group).single.toSignature(name: 'Mine', kind: SignatureClass.finder, alert: true);
      final engine = SignatureEngine([Signature.fromJson(jsonDecode(jsonEncode(sig.toJson())) as Map<String, dynamic>)]);
      expect(engine.match(hit).map((s) => s.name), ['Mine'], reason: sig.rules.single.text);
      expect(engine.match(miss), isEmpty, reason: sig.rules.single.text);
    }
  });

  test('saved signatures persist with their alert switch', () async {
    SharedPreferences.setMockInitialValues({});
    final a = UserSignatures();
    await a.loaded;
    final sig = SignatureSuggest.of(_three((n) => _obs(n, uuids: const ['FFE0'])))
        .single
        .toSignature(name: 'Mine', kind: SignatureClass.other, alert: true);
    await a.add(sig);
    expect(a.hasRule(const MatchRule(RuleKind.serviceUuid, text: 'FFE0')), isTrue);
    await a.setAlert(sig.id, false);
    final b = UserSignatures();
    await b.loaded;
    expect((b.items.single.name, b.items.single.alert, b.items.single.kind), ('Mine', false, SignatureClass.other));
    await b.remove(sig.id);
    final c = UserSignatures();
    await c.loaded;
    expect(c.items, isEmpty);
  });

  test('saving reclassifies listed radios quietly; a new match alerts even with its class off', () {
    final reg = DeviceRegistry(engine: SignatureEngine(const []));
    var fired = 0;
    reg.onClassified = (_) => fired++;
    for (var n = 1; n <= 3; n++) {
      reg.ingest(_obs(n, uuids: const ['FFE0']));
    }
    expect(fired, 3);
    final sig = SignatureSuggest.of(reg.devices).single.toSignature(name: 'Mine', kind: SignatureClass.other, alert: true);
    reg.setUserSignatures([sig]);
    expect(reg.devices.every((d) => d.signatures.single.name == 'Mine'), isTrue);
    reg.ingest(_obs(1, uuids: const ['FFE0']));
    expect(fired, 3);
    reg.ingest(_obs(9, uuids: const ['FFE0']));
    expect(fired, 4);
    final fresh = reg.devices.firstWhere((d) => d.obs.mac.endsWith(':09'));
    expect(classAlertOf(fresh, const {}, flock: false)?.kind, SignatureClass.other.name);
    reg.setUserSignatures([]);
    expect(reg.devices.every((d) => d.signatures.isEmpty), isTrue);
    reg.dispose();
  });
}
