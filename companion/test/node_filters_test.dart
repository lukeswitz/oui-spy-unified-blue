// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/detector_rules.dart';
import 'package:oui_spy/core/node_filters.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/features/engines/presets_panel.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchlistEntry _e(WatchlistMatchType t, String id) => WatchlistEntry(identifier: id, matchType: t);

NodeFilterResult _res(String id, int status, {int changed = 0, int skipped = 0}) =>
    (id: id, status: status, filterMacs: 1, filterUuids: 2, filterRules: 3, changed: changed, skipped: skipped);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('presets match the firmware table', () {
    final header = File('../src/engines/detector_presets.h').readAsStringSync();
    const kinds = {
      'OUI': WatchlistMatchType.oui,
      'PROBE': WatchlistMatchType.wifiProbe,
      'BEACON': WatchlistMatchType.wifiBeacon,
      'SVC': WatchlistMatchType.serviceUuid,
      'CID': WatchlistMatchType.companyId,
      'NAME': WatchlistMatchType.nameContains,
      'PFX': WatchlistMatchType.namePrefix,
      'MFR': WatchlistMatchType.companyData,
      'PAT': WatchlistMatchType.namePattern,
      'UUID': WatchlistMatchType.serviceUuid,
    };

    Map<String, List<(String, String, String)>> parse() {
      final out = <String, List<(String, String, String)>>{};
      List<(String, String, String)>? cur;
      for (final line in header.split('\n')) {
        final a = RegExp(r'static const DetPresetRow PRESET_(\w+)\[\]').firstMatch(line);
        if (a != null) {
          cur = out[a.group(1)!.toLowerCase()] = [];
          continue;
        }
        final r = RegExp(r'\{PR_(\w+), "([^"]*)", "([^"]*)"\}').firstMatch(line);
        if (r != null && cur != null) cur.add((r.group(1)!, r.group(2)!, r.group(3)!));
      }
      return out;
    }

    test('same presets in the same order', () {
      final order = RegExp(r'\{"(\w+)", DET_PRESET_ROWS').allMatches(header).map((m) => m.group(1)).toList();
      expect(order, [for (final p in detectorPresets) p.key]);
      expect([for (final p in detectorPresets) p.id], List.generate(detectorPresets.length, (i) => i));
    });

    test('same rows, ids and labels', () {
      final fw = parse();
      expect(fw.length, detectorPresets.length);
      var total = 0;
      for (final p in detectorPresets) {
        final rows = fw[p.key]!;
        expect(rows.length, p.rows.length, reason: p.key);
        for (var i = 0; i < rows.length; i++) {
          final (k, id, desc) = rows[i];
          final r = p.rows[i];
          expect(kinds[k], r.type, reason: '${p.key} row $i');
          final want = switch (k) {
            'OUI' || 'PROBE' || 'BEACON' => r.identifier.replaceAll(':', ''),
            'UUID' => r.identifier.replaceAll('-', ''),
            _ => r.identifier,
          };
          expect(id, want, reason: '${p.key} row $i');
          expect(desc, r.description, reason: '${p.key} row $i');
          expect(desc.length, lessThanOrEqualTo(31));
          total++;
        }
      }
      expect(total, 99);
    });

    test('every row is a valid rule and fits a record', () {
      for (final p in detectorPresets) {
        for (final r in p.rows) {
          expect(normalizeWatchlistId(r.identifier, r.type), isNotNull, reason: '${p.key} ${r.identifier}');
          expect(filterRecordOf(r.entry), isNotNull, reason: '${p.key} ${r.identifier}');
        }
      }
    });
  });

  group('records', () {
    test('every record kind survives a round trip', () {
      final entries = [
        _e(WatchlistMatchType.oui, 'AA:BB:CC'),
        _e(WatchlistMatchType.fullMac, 'AA:BB:CC:DD:EE:FF'),
        _e(WatchlistMatchType.serviceUuid, 'FD5F'),
        _e(WatchlistMatchType.serviceUuid, '7A230001-5475-A6A4-654C-8431F6AD49C4'),
        _e(WatchlistMatchType.nameContains, 'Flipper'),
        _e(WatchlistMatchType.namePrefix, 'Flipper '),
        _e(WatchlistMatchType.namePattern, 'S################C'),
        _e(WatchlistMatchType.companyId, '004C'),
        _e(WatchlistMatchType.companyData, '004C:121910/FFFF30'),
        _e(WatchlistMatchType.wifiProbe, 'D4:2D:C5'),
        _e(WatchlistMatchType.wifiBeacon, 'D4:2D:C5:01'),
      ];
      final bytes = [for (final e in entries) ...filterRecordOf(e)!];
      final back = decodeFilterRecords(bytes);
      expect([for (final r in back) r.entry!.matchType], [for (final e in entries) e.matchType]);
      expect([for (final r in back) r.entry!.identifier], [for (final e in entries) e.identifier]);
    });

    test('MAC and UUID rows use the older record kinds', () {
      expect(filterRecordOf(_e(WatchlistMatchType.oui, 'AA:BB:CC')), [0x10, 4, 3, 0xAA, 0xBB, 0xCC]);
      expect(filterRecordOf(_e(WatchlistMatchType.serviceUuid, 'FD5F')), [0x11, 2, 0x5F, 0xFD]);
      expect(filterRecordOf(_e(WatchlistMatchType.makerName, 'Motorola')), isNull);
      expect(filterRecordOf(_e(WatchlistMatchType.name, 'x*')), isNull);
    });

    test('a cut or unknown record ends or skips the list', () {
      expect(decodeFilterRecords([0x04, 2, 0x4C, 0x00, 0x04, 9, 0x4C]).length, 1);
      expect(decodeFilterRecords([0x7F, 1, 0x55, 0x04, 2, 0x4C, 0x00]).length, 1);
      expect(decodeFilterRecords(const []), isEmpty);
    });

    test('edits are packed without splitting a record', () {
      final recs = [for (var i = 0; i < 40; i++) filterRecordOf(_e(WatchlistMatchType.companyData, '004C:${i.toRadixString(16).padLeft(2, '0')}'))!];
      final packs = packFilterRecords(recs);
      expect(packs.length, greaterThan(1));
      for (final p in packs) {
        expect(p.length, lessThanOrEqualTo(BleProtocol.filterOpDataMax));
        expect(decodeFilterRecords(p).isNotEmpty, isTrue);
      }
      expect(packs.fold<int>(0, (n, p) => n + decodeFilterRecords(p).length), 40);
    });
  });

  group('wire', () {
    test('a filter edit carries the target and data', () {
      expect(BleProtocol.encodeNodeFilterOp('AB12', BleProtocol.filterOpPreset, [9]),
          [0x06, 4, 0x41, 0x42, 0x31, 0x32, 9]);
      expect(BleProtocol.encodeNodeFilterOp(null, BleProtocol.filterOpGet), [0x06, 5, 0, 0, 0, 0]);
      expect(() => BleProtocol.encodeNodeFilterOp('AB', 1), throwsArgumentError);
      expect(() => BleProtocol.encodeNodeFilterOp('AB12', 1, List.filled(101, 0)), throwsArgumentError);
    });

    test('the manager status carries the filter edit answers', () {
      final body = [
        7, 4, 2, 2,
        0xAB, 0x12, 0, 1, 2, 3, 4, 0,
        0xCD, 0x34, 4, 1, 2, 3, 0, 2,
      ];
      final data = <int>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...[0, 0, 0, 0], 0x04, body.length, ...body];
      final s = BleProtocol.decodeMeshStatus(data);
      final op = s.filterOp!;
      expect((op.seq, op.op, op.expected), (7, 4, 2));
      expect(op.results.length, 2);
      expect(op.results[0].id, 'AB12');
      expect((op.results[0].filterMacs, op.results[0].filterUuids, op.results[0].filterRules, op.results[0].changed), (1, 2, 3, 4));
      expect((op.results[1].status, op.results[1].skipped), (4, 2));
      expect(s.filterPush, isNull);
    });

    test('a status without the answers has none', () {
      expect(BleProtocol.decodeMeshStatus([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).filterOp, isNull);
    });

    test('a list page decodes', () {
      final f = BleProtocol.decodeNodeFilterFrame([0x16, 0xAB, 0x12, 5, 1, 3, 9, 8, 7])!;
      expect((f.id, f.seq, f.page, f.pages), ('AB12', 5, 1, 3));
      expect(f.data, [9, 8, 7]);
      expect(BleProtocol.decodeNodeFilterFrame([0x16, 1, 2]), isNull);
      expect(BleProtocol.decodeNodeFilterFrame([0x15, 1, 2, 3, 4, 5]), isNull);
    });
  });

  group('report', () {
    NodeFilterFrame frame(int seq, int page, int pages, List<int> d) =>
        (id: 'AB12', seq: seq, page: page, pages: pages, data: Uint8List.fromList(d));

    test('pages arrive in any order and join into rows', () {
      final r = NodeFilterReport('AB12', 3, 2);
      expect(r.add(frame(3, 1, 2, [0x04, 2, 0x53, 0x0D])), isTrue);
      expect(r.complete, isFalse);
      expect(r.add(frame(3, 0, 2, [0x11, 2, 0x5F, 0xFD])), isTrue);
      expect(r.complete, isTrue);
      expect([for (final x in r.rows) x.entry!.identifier], ['FD5F', '0D53']);
    });

    test('pages of another edit are refused', () {
      final r = NodeFilterReport('AB12', 3, 2);
      expect(r.add(frame(4, 0, 2, [])), isFalse);
      expect(r.add(frame(3, 0, 5, [])), isFalse);
      expect(r.add(frame(3, 2, 2, [])), isFalse);
      expect(r.received, 0);
    });

    test('an empty list is one empty page', () {
      final r = NodeFilterReport('AB12', 1, 1)..add(frame(1, 0, 1, []));
      expect(r.complete, isTrue);
      expect(r.rows, isEmpty);
    });
  });

  group('words', () {
    String label(String id) => 'NODE-$id';

    test('a node answer reads as added, skipped and held', () {
      expect(nodeFilterOpText(_res('AB12', 0, changed: 4, skipped: 2), BleProtocol.filterOpPreset),
          'added 4, skipped 2, holds 6 rows');
      expect(nodeFilterOpText(_res('AB12', 0, changed: 1), BleProtocol.filterOpDel), 'removed 1, holds 6 rows');
      expect(nodeFilterOpText(_res('AB12', 0), BleProtocol.filterOpGet), 'holds 6 rows');
      expect(nodeFilterOpText(_res('AB12', 4), BleProtocol.filterOpPreset),
          'refused: nothing it can match with its radio setting');
    });

    test('the summary names the nodes that refused, skipped or stayed silent', () {
      final op = (
        seq: 1,
        op: BleProtocol.filterOpPreset,
        expected: 4,
        results: [_res('AB12', 0), _res('CD34', 4), _res('EF56', 0, skipped: 2)],
      );
      expect(filterOpSummary(op, label),
          'On 2 of 4 nodes; NODE-CD34 refused (nothing it can match with its radio setting); NODE-EF56 skipped 2 rows; 1 did not answer (older firmware does not)');
      expect(filterOpSummary((seq: 1, op: 1, expected: 0, results: <NodeFilterResult>[]), label), isNull);
    });
  });

  group('preset panel', () {
    Widget host(Widget child) => ProviderScope(
          child: MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SingleChildScrollView(child: child))),
        );

    testWidgets('lists the ten presets', (tester) async {
      await tester.pumpWidget(host(const PresetsPanel()));
      for (final n in ['Axon', 'Meta glasses', 'i-PRO', 'Verkada', 'Trackers', 'Drones', 'Vehicles', 'Wearables', 'Flipper', 'Police']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
    });

    testWidgets('watching a preset adds its rows once', (tester) async {
      await tester.pumpWidget(host(const PresetsPanel()));
      await tester.tap(find.text('Verkada'));
      await tester.pumpAndSettle();
      expect(find.text('INSTALL ON NODES'), findsOneWidget);
      await tester.tap(find.text('WATCH ON PHONE'));
      await tester.pumpAndSettle();
      final wl = ProviderScope.containerOf(tester.element(find.byType(PresetsPanel))).read(watchlistProvider);
      expect(wl.entries.map((e) => e.matchType), [WatchlistMatchType.wifiProbe, WatchlistMatchType.wifiBeacon]);
      final again = await watchPreset(wl, detectorPresets[3]);
      expect((again.added, again.skipped), (0, 2));
      expect(watchlistBudget(wl.entries).rules, 2);
    });

    testWidgets('installing needs a manager', (tester) async {
      await tester.pumpWidget(host(const PresetsPanel()));
      await tester.tap(find.text('Axon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('INSTALL ON NODES'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to a manager to install on nodes.'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'INSTALL')).onPressed, isNull);
    });
  });
}
