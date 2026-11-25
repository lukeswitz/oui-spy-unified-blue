// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/features/engines/detection_rules.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/detector_rules.dart';
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/watchlist_state.dart';

WatchlistEntry _e(WatchlistMatchType t, String id, [String d = '']) =>
    WatchlistEntry(identifier: id, matchType: t, description: d);

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('rule builder', () {
    testWidgets('lists every rule kind but the old phone-only name pattern', (tester) async {
      await tester.pumpWidget(_host(const WatchlistPanel()));
      await tester.tap(find.byTooltip('Add target'));
      await tester.pumpAndSettle();
      expect(find.text('Add a rule'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<WatchlistMatchType>));
      await tester.pumpAndSettle();
      for (final t in WatchlistMatchType.values) {
        expect(find.text(t.title), t == WatchlistMatchType.name ? findsNothing : findsWidgets, reason: t.name);
      }
    });

    testWidgets('saves company data and refuses a bad one', (tester) async {
      await tester.pumpWidget(_host(const WatchlistPanel()));
      await tester.tap(find.byTooltip('Add target'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<WatchlistMatchType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Company data').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '004C:12');
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      expect(find.text('Not a valid company data'), findsNothing);
      final container = ProviderScope.containerOf(tester.element(find.byType(WatchlistPanel)));
      expect(container.read(watchlistProvider).entries.single.identifier, '004C:12/FF');
    });

    testWidgets('shows what is wrong with a malformed rule', (tester) async {
      await tester.pumpWidget(_host(const WatchlistPanel()));
      await tester.tap(find.byTooltip('Add target'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<WatchlistMatchType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Company ID').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '4C');
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      expect(find.text('Not a valid company id'), findsOneWidget);
    });

    testWidgets('a name rule keeps its trailing space', (tester) async {
      await tester.pumpWidget(_host(const WatchlistPanel()));
      await tester.tap(find.byTooltip('Add target'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<WatchlistMatchType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name starts with').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Flipper ');
      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(WatchlistPanel)));
      expect(container.read(watchlistProvider).entries.single.identifier, 'Flipper ');
    });
  });

  group('normalize', () {
    test('name rules keep spaces and refuse non-ASCII or long text', () {
      expect(normalizeWatchlistId('Flipper ', WatchlistMatchType.namePrefix), 'Flipper ');
      expect(normalizeWatchlistId('   ', WatchlistMatchType.nameContains), isNull);
      expect(normalizeWatchlistId('a' * 19, WatchlistMatchType.nameContains), isNull);
      expect(normalizeWatchlistId('a' * 18, WatchlistMatchType.nameContains), 'a' * 18);
      expect(normalizeWatchlistId('Café', WatchlistMatchType.nameContains), isNull);
      expect(normalizeWatchlistId('S################C', WatchlistMatchType.namePattern), 'S################C');
    });

    test('company id and company data', () {
      expect(normalizeWatchlistId('0x004c', WatchlistMatchType.companyId), '004C');
      expect(normalizeWatchlistId('4C', WatchlistMatchType.companyId), isNull);
      expect(normalizeWatchlistId('004c:121910/ffff30', WatchlistMatchType.companyData), '004C:121910/FFFF30');
      expect(normalizeWatchlistId('004C:121910', WatchlistMatchType.companyData), '004C:121910/FFFFFF');
      expect(normalizeWatchlistId('004C:121910/FF', WatchlistMatchType.companyData), isNull);
      expect(normalizeWatchlistId('004C:1219101', WatchlistMatchType.companyData), isNull);
      expect(normalizeWatchlistId('004C:${'AA' * 9}', WatchlistMatchType.companyData), isNull);
      expect(normalizeWatchlistId('004C', WatchlistMatchType.companyData), isNull);
    });

    test('service UUID takes 16-bit and 128-bit forms', () {
      expect(normalizeWatchlistId('0xfd5f', WatchlistMatchType.serviceUuid), 'FD5F');
      expect(normalizeWatchlistId('7a2300015475a6a4654c8431f6ad49c4', WatchlistMatchType.serviceUuid),
          '7A230001-5475-A6A4-654C-8431F6AD49C4');
      expect(normalizeWatchlistId('7a230001-5475-a6a4-654c-8431f6ad49c4', WatchlistMatchType.serviceUuid),
          '7A230001-5475-A6A4-654C-8431F6AD49C4');
      expect(normalizeWatchlistId('7a2300015475a6a4654c8431f6ad49', WatchlistMatchType.serviceUuid), isNull);
    });

    test('Wi-Fi prefixes take 3 to 6 bytes', () {
      expect(normalizeWatchlistId('d42dc5', WatchlistMatchType.wifiProbe), 'D4:2D:C5');
      expect(normalizeWatchlistId('d4-2d-c5-01', WatchlistMatchType.wifiBeacon), 'D4:2D:C5:01');
      expect(normalizeWatchlistId('D4:2D', WatchlistMatchType.wifiProbe), isNull);
      expect(normalizeWatchlistId('D4:2D:C5:01:02:03:04', WatchlistMatchType.wifiProbe), isNull);
    });

    test('maker name needs two characters', () {
      expect(normalizeWatchlistId(' Motorola ', WatchlistMatchType.makerName), 'Motorola');
      expect(normalizeWatchlistId('M', WatchlistMatchType.makerName), isNull);
    });
  });

  group('wire', () {
    test('name rules send the text', () {
      expect(_e(WatchlistMatchType.nameContains, 'Fl').rule!.op, [0x05, 0x01, 2, 0x46, 0x6C]);
      expect(_e(WatchlistMatchType.namePrefix, 'Fl').rule!.record, [0x02, 2, 0x46, 0x6C]);
      expect(_e(WatchlistMatchType.namePattern, 'S#C').rule!.record, [0x03, 3, 0x53, 0x23, 0x43]);
    });

    test('company id goes out little endian', () {
      expect(_e(WatchlistMatchType.companyId, '004C').rule!.record, [0x04, 2, 0x4C, 0x00]);
      expect(_e(WatchlistMatchType.companyId, '0D53').rule!.payload, [0x53, 0x0D]);
    });

    test('company data is id, data, mask', () {
      expect(_e(WatchlistMatchType.companyData, '004C:121910/FFFF30').rule!.record,
          [0x05, 8, 0x4C, 0x00, 0x12, 0x19, 0x10, 0xFF, 0xFF, 0x30]);
    });

    test('128-bit UUID goes out in advertisement byte order', () {
      final r = _e(WatchlistMatchType.serviceUuid, '7A230001-5475-A6A4-654C-8431F6AD49C4').rule!;
      expect(r.type, detRuleUuid128);
      expect(r.payload.first, 0xC4);
      expect(r.payload.last, 0x7A);
      expect(r.payload.length, 16);
    });

    test('16-bit UUID, MAC, prefix and phone-only entries are not extension rules', () {
      for (final e in [
        _e(WatchlistMatchType.serviceUuid, 'FD5F'),
        _e(WatchlistMatchType.oui, 'AA:BB:CC'),
        _e(WatchlistMatchType.fullMac, 'AA:BB:CC:DD:EE:FF'),
        _e(WatchlistMatchType.name, 'x*'),
        _e(WatchlistMatchType.makerName, 'Motorola'),
      ]) {
        expect(e.isExtWire, isFalse, reason: e.matchType.name);
        expect(e.rule, isNull, reason: e.matchType.name);
      }
    });

    test('Wi-Fi rules carry the prefix bytes', () {
      expect(_e(WatchlistMatchType.wifiProbe, 'D4:2D:C5').rule!.record, [0x07, 3, 0xD4, 0x2D, 0xC5]);
      expect(_e(WatchlistMatchType.wifiBeacon, 'D4:2D:C5:01').rule!.record, [0x08, 4, 0xD4, 0x2D, 0xC5, 0x01]);
    });

    test('equal rules compare equal', () {
      expect(_e(WatchlistMatchType.companyId, '004C').rule, _e(WatchlistMatchType.companyId, '004c').rule);
      expect(_e(WatchlistMatchType.companyId, '004C').rule, isNot(_e(WatchlistMatchType.companyId, '004D').rule));
    });
  });

  group('name rules', () {
    test('contains and prefix ignore case', () {
      expect(nameRuleMatches(WatchlistMatchType.nameContains, 'flip', 'My FLIPPER x'), isTrue);
      expect(nameRuleMatches(WatchlistMatchType.nameContains, 'zzz', 'My FLIPPER x'), isFalse);
      expect(nameRuleMatches(WatchlistMatchType.namePrefix, 'Flipper ', 'flipper abc'), isTrue);
      expect(nameRuleMatches(WatchlistMatchType.namePrefix, 'Flipper ', 'Flipperabc'), isFalse);
      expect(nameRuleMatches(WatchlistMatchType.namePrefix, 'ipper', 'Flipper'), isFalse);
    });

    test('pattern matches the whole name with # hex, ? any and * run', () {
      const t = WatchlistMatchType.namePattern;
      expect(nameRuleMatches(t, 'S################C', 'S0123456789abcdefC'), isTrue);
      expect(nameRuleMatches(t, 'S################C', 'S0123456789abcdeXC'), isFalse);
      expect(nameRuleMatches(t, 'S################C', 'S0123456789abcdeC'), isFalse);
      expect(nameRuleMatches(t, 'OBD*', 'obdlink mx'), isTrue);
      expect(nameRuleMatches(t, 'OBD*', 'my obd'), isFalse);
      expect(nameRuleMatches(t, 'a?c', 'abc'), isTrue);
      expect(nameRuleMatches(t, 'a*b*c', 'axxbyyc'), isTrue);
      expect(nameRuleMatches(t, 'a*b*c', 'axxbyy'), isFalse);
      expect(nameRuleMatches(t, '*', ''), isTrue);
    });
  });

  group('budget', () {
    test('counts each list and flags what does not fit', () {
      final b = watchlistBudget([
        _e(WatchlistMatchType.oui, 'AA:BB:CC'),
        _e(WatchlistMatchType.fullMac, 'AA:BB:CC:DD:EE:FF'),
        _e(WatchlistMatchType.serviceUuid, 'FD5F'),
        _e(WatchlistMatchType.nameContains, 'Flipper'),
        _e(WatchlistMatchType.makerName, 'Motorola'),
      ]);
      expect((b.macs, b.uuids, b.rules, b.phoneOnly), (2, 1, 1, 1));
      expect(b.wireBytes, 1 + 14 + 1 + 2 + 1 + 2 + 7);
      expect(b.warning, isEmpty);
    });

    test('warns past the device limits and past one mesh frame', () {
      final macs = [for (var i = 0; i < 40; i++) _e(WatchlistMatchType.fullMac, 'AA:BB:CC:DD:EE:${i.toRadixString(16).padLeft(2, '0')}')];
      final b = watchlistBudget(macs);
      expect(b.overMeshFrame, isTrue);
      expect(b.overDevice, isFalse);
      expect(b.warning, contains('mesh frame'));
      final rules = [for (var i = 0; i < 33; i++) _e(WatchlistMatchType.companyId, i.toRadixString(16).padLeft(4, '0'))];
      expect(watchlistBudget(rules).overRules, isTrue);
      expect(watchlistBudget(rules).warning, contains('32'));
    });
  });

  group('storage', () {
    test('every type survives export and import', () async {
      final wl = WatchlistState();
      await wl.replaceAll([
        for (final t in WatchlistMatchType.values)
          _e(t, switch (t) {
            WatchlistMatchType.oui => 'AA:BB:CC',
            WatchlistMatchType.fullMac => 'AA:BB:CC:DD:EE:FF',
            WatchlistMatchType.serviceUuid => 'FD5F',
            WatchlistMatchType.companyId => '004C',
            WatchlistMatchType.companyData => '004C:121910/FFFF30',
            WatchlistMatchType.wifiProbe || WatchlistMatchType.wifiBeacon => 'D4:2D:C5',
            _ => 'Flipper',
          }, 'row ${t.name}'),
      ]);
      final json = wl.exportJson();
      final other = WatchlistState();
      await other.clear();
      final r = await other.importText(json);
      expect(r.added, WatchlistMatchType.values.length);
      expect(r.skipped, 0);
      for (final t in WatchlistMatchType.values) {
        expect(other.entries.where((e) => e.matchType == t).length, 1, reason: t.name);
      }
    });

    test('csv rows name their kind by label', () async {
      final wl = WatchlistState();
      await wl.clear();
      final r = await wl.importText('004C:121910/FFFF30,AirTag,DATA\n0D53,Meta,COMPANY\nD4:2D:C5,Body cam,PROBE\n');
      expect(r.added, 3);
      expect(wl.entries.map((e) => e.matchType), [
        WatchlistMatchType.companyData,
        WatchlistMatchType.companyId,
        WatchlistMatchType.wifiProbe,
      ]);
    });

    test('entries saved before these kinds still load', () {
      final e = WatchlistEntry.fromJson({'identifier': 'AA:BB:CC', 'matchType': 'oui', 'description': 'x', 'enabled': true});
      expect(e.matchType, WatchlistMatchType.oui);
      final legacy = WatchlistEntry.fromJson({'identifier': 'AA:BB:CC:DD:EE:FF', 'isFullMac': true});
      expect(legacy.matchType, WatchlistMatchType.fullMac);
    });
  });

  group('phone matching', () {
    Detection ap(int i, String ssid) => Detection(
          id: '$i',
          sessionId: 's',
          nodeId: 'n',
          macAddress: '02:00:00:00:00:0$i',
          engine: Engine.wardrive,
          method: 'wifi_ap',
          rssi: -60,
          channel: 6,
          deviceTimestampMs: 0,
          appTimestamp: DateTime.utc(2026, 11, 23, 12, 0, i),
          ssid: ssid,
          latitude: 51.4,
          longitude: -0.1,
          wardrive: WardriveExtension(ssid: ssid, authMode: 0),
        );

    test('name rules and maker name flag rows on import', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final csv = WigleCsv.generate([ap(1, 'FlipperAB'), ap(2, 'MyNetwork'), ap(3, 'Plain')]);
      final res = await WigleCsvImport.importString(
        db,
        csv,
        fileName: 'rules.csv',
        watchlist: [
          _e(WatchlistMatchType.nameContains, 'flipper'),
          _e(WatchlistMatchType.makerName, 'acme'),
          _e(WatchlistMatchType.companyId, '004C'),
        ],
        maker: (mac) => mac.endsWith('02') ? 'Acme Corp' : null,
      );
      expect(res.detectorMacs, 2);
      await db.close();
    });
  });
}
