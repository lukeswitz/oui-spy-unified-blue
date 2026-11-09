import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_suggest.dart';
import 'package:oui_spy/core/watchlist_state.dart';

ClassifiedDevice _ble(
  int n, {
  String name = '',
  List<String> uuids = const [],
  List<int> companies = const [],
  String? mac,
  String? vendor,
}) {
  final m = mac ?? '02:00:00:00:00:0$n';
  return ClassifiedDevice(
    Observation(
      key: 'BLE:$m',
      kind: RadioKind.ble,
      mac: m,
      name: name,
      serviceUuids: uuids,
      mfgRecords: [for (final c in companies) MfgRecord(c, '0102')],
    ),
    const [],
    const {'esp32'},
    vendor: vendor,
  );
}

List<ClassifiedDevice> _three(ClassifiedDevice Function(int n) f) => [for (var n = 1; n <= 3; n++) f(n)];

void main() {
  test('3 unclassified radios sharing a service get a UUID rule', () {
    final s = SignatureSuggest.of(_three((n) => _ble(n, uuids: const ['FFE0'])));
    expect(s.single.kind, SuggestionKind.uuid);
    expect(s.single.devices, hasLength(3));
    expect(s.single.rule!.matchType, WatchlistMatchType.serviceUuid);
    expect(s.single.rule!.identifier, 'FFE0');
  });

  test('two radios are not a group', () {
    expect(SignatureSuggest.of([_ble(1, uuids: const ['FFE0']), _ble(2, uuids: const ['FFE0'])]), isEmpty);
  });

  test('a shared vendor prefix on public addresses gets an OUI rule', () {
    final s = SignatureSuggest.of(_three((n) => _ble(n, mac: '00:11:22:00:00:0$n', vendor: 'Example Vendor')));
    expect(s.single.kind, SuggestionKind.oui);
    expect(s.single.rule!.matchType, WatchlistMatchType.oui);
    expect(s.single.rule!.identifier, '00:11:22');
    expect(s.single.rule!.description, 'Example Vendor');
    expect(s.single.label(), 'Vendor prefix 00:11:22 (Example Vendor)');
    expect(s.single.label(masked: true), 'Vendor prefix 00:11:XX (Example Vendor)');
  });

  test('randomized addresses never form a vendor prefix group', () {
    expect(SignatureSuggest.of(_three((n) => _ble(n, mac: 'AA:BB:CC:00:00:0$n', vendor: 'Example Vendor'))), isEmpty);
  });

  test('name and company groups are listed with no rule', () {
    final names = SignatureSuggest.of(_three((n) => _ble(n, name: 'Zyx-0$n')));
    expect(names.single.kind, SuggestionKind.name);
    expect(names.single.rule, isNull);
    expect(names.single.label(), 'Name like "Zyx-01"');
    final companies = SignatureSuggest.of(_three((n) => _ble(n, companies: const [0xFFFF])));
    expect(companies.single.kind, SuggestionKind.company);
    expect(companies.single.rule, isNull);
  });

  test('platform companies and standard GATT services are skipped', () {
    expect(SignatureSuggest.of(_three((n) => _ble(n, uuids: const ['180F'], companies: const [0x004C]))), isEmpty);
  });

  test('identical groups fold into the one that has a rule', () {
    final s = SignatureSuggest.of(_three((n) => _ble(n, name: 'Zyx-0$n', uuids: const ['FFE0'], companies: const [0xFFFF])));
    expect(s.single.kind, SuggestionKind.uuid);
    expect(s.single.also.map((a) => a.kind), [SuggestionKind.name, SuggestionKind.company]);
  });

  test('classified radios are left out', () {
    expect(SignatureSuggest.of(_three((n) => _ble(n, uuids: const ['FD5A']))), isEmpty);
  });

  test('bigger groups come first and the list is capped', () {
    final devices = [
      for (var g = 0; g < 25; g++)
        for (var n = 0; n < 3 + (g == 7 ? 2 : 0); n++)
          _ble(n, mac: '02:00:00:00:${g.toRadixString(16).padLeft(2, '0')}:0$n', uuids: [(0xFF00 + g).toRadixString(16)]),
    ];
    final s = SignatureSuggest.of(devices);
    expect(s, hasLength(SignatureSuggest.maxGroups));
    expect(s.first.key, 'FF07');
    expect(s.first.devices, hasLength(5));
  });
}
