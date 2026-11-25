// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/feed_counts.dart';
import 'package:oui_spy/core/global_search.dart';
import 'package:oui_spy/features/feed/feed_counts_strip.dart';
import 'package:oui_spy/features/feed/search_sheet.dart';
import 'package:oui_spy/theme/app_theme.dart';

SearchEntry _e(SearchArea a, String title, List<Object?> hay, {int at = 0, Object? payload}) =>
    SearchEntry(area: a, title: title, subtitle: 'sub $title', haystack: hay, atMs: at, payload: payload);

void main() {
  const track = Color(0xFF888888);

  group('search matching', () {
    test('every word must match somewhere', () {
      final h = searchHaystack(['Axon Body 3', 'AA:BB:CC:DD:EE:FF', null, '']);
      expect(searchHits(h, 'axon'), isTrue);
      expect(searchHits(h, 'axon body'), isTrue);
      expect(searchHits(h, 'body axon'), isTrue);
      expect(searchHits(h, 'axon taser'), isFalse);
      expect(searchHits(h, ''), isTrue);
    });

    test('a MAC matches with or without separators and in any case', () {
      final h = searchHaystack(['AA:BB:CC:DD:EE:FF']);
      expect(searchHits(h, 'aabbccddeeff'), isTrue);
      expect(searchHits(h, 'aa-bb-cc'), isTrue);
      expect(searchHits(h, 'AA:BB:CC:DD'), isTrue);
      expect(searchHits(h, 'aa:bb:cc:00'), isFalse);
    });

    test('a separator-free hit does not match unrelated text', () {
      expect(searchHits(searchHaystack(['ab-cd']), 'abcd'), isTrue);
      expect(searchHits(searchHaystack(['abxcd']), 'ab-cd'), isFalse);
    });
  });

  group('search results by area', () {
    final entries = [
      _e(SearchArea.devices, 'Axon camera', ['axon']),
      _e(SearchArea.alerts, 'Axon alert', ['axon', 'camera'], at: 5),
      _e(SearchArea.alerts, 'Axon older alert', ['axon'], at: 1),
      _e(SearchArea.drones, 'DJI', ['dji']),
      _e(SearchArea.nodes, 'OUISPY-AAAA', ['aaaa']),
      _e(SearchArea.wardrive, 'Axon Wi-Fi', ['axon wifi']),
    ];

    test('counts every match per area and lists areas in a fixed order', () {
      final r = searchEntries('axon', entries);
      expect(r.totals, {SearchArea.devices: 1, SearchArea.alerts: 2, SearchArea.wardrive: 1});
      expect(r.total, 4);
      expect(r.areas, [SearchArea.devices, SearchArea.alerts, SearchArea.wardrive]);
      expect(r.byArea[SearchArea.alerts]!.map((e) => e.title), ['Axon alert', 'Axon older alert']);
    });

    test('a node is found by its ID and an empty query finds nothing', () {
      expect(searchEntries('aaaa', entries).areas, [SearchArea.nodes]);
      expect(searchEntries('  ', entries).total, 0);
      expect(searchEntries('zzz', entries).total, 0);
    });

    test('lists are capped but totals are not', () {
      final many = [for (var i = 0; i < 80; i++) _e(SearchArea.devices, 'd$i', ['axon'], at: i)];
      final r = searchEntries('axon', many);
      expect(r.totals[SearchArea.devices], 80);
      expect(r.byArea[SearchArea.devices]!.length, searchPerAreaLimit);
      expect(r.byArea[SearchArea.devices]!.first.title, 'd79');
    });
  });

  group('live counts', () {
    const now = 10000000;

    test('heard now and live drones count each device once within a minute', () {
      final c = buildFeedCounts(
        nowMs: now,
        nodesOnline: 2,
        nodesTotal: 3,
        live: const [
          LiveSighting('A', now - 1000),
          LiveSighting('A', now - 2000),
          LiveSighting('B', now - 60000),
          LiveSighting('C', now - 60001),
          LiveSighting('D1', now - 5000, drone: true),
          LiveSighting('D1', now - 3000, drone: true),
        ],
        unread: 4,
        macsKept: 900,
        storedToday: 0,
        hourly: const [1, 2],
      );
      expect(c.heardNow, 3);
      expect(c.liveDrones, 1);
      expect((c.nodesOnline, c.nodesTotal, c.unread, c.macsKept), (2, 3, 4, 900));
      expect(c.hourlyTotal, 3);
    });

    test('today is never below what was heard just now', () {
      FeedCounts counts(int stored) => buildFeedCounts(
            nowMs: now,
            nodesOnline: 0,
            nodesTotal: 0,
            live: const [LiveSighting('A', now), LiveSighting('B', now)],
            unread: 0,
            macsKept: 0,
            storedToday: stored,
            hourly: const [],
          );
      expect(counts(0).today, 2);
      expect(counts(10).today, 10);
    });

    test('the local day starts at midnight', () {
      expect(startOfLocalDay(DateTime(2026, 5, 6, 17, 30)), DateTime(2026, 5, 6));
    });
  });

  group('stored counts', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> insert(String mac, int ts) => db.insertDetection(DetectionsCompanion(
          sessionId: const drift.Value('s1'),
          nodeId: const drift.Value('default'),
          macAddress: drift.Value(mac),
          engine: const drift.Value('wardrive'),
          detectionMethod: const drift.Value('ble_adv'),
          rssi: const drift.Value(-70),
          channel: const drift.Value(0),
          deviceTimestampMs: drift.Value(ts),
          appTimestamp: drift.Value(ts),
        ));

    test('MACs kept and heard since midnight count each MAC once, ignoring case', () async {
      const day = 86400000;
      await insert('AA:AA:AA:00:00:01', 10 * day);
      await insert('aa:aa:aa:00:00:01', 20 * day);
      await insert('AA:AA:AA:00:00:02', 20 * day + 5);
      final c = await db.macCounts(20 * day);
      expect((c.kept, c.since), (2, 2));
      final old = await db.macCounts(20 * day + 1);
      expect((old.kept, old.since), (2, 1));
    });

    test('the 24 hour histogram has one bar per hour, latest last, devices counted once per hour', () async {
      const hour = 3600000;
      const now = 100 * hour;
      await insert('AA:AA:AA:00:00:01', now - 10);
      await insert('AA:AA:AA:00:00:01', now - 20);
      await insert('AA:AA:AA:00:00:02', now - 30);
      await insert('AA:AA:AA:00:00:01', now - 2 * hour - 5);
      await insert('AA:AA:AA:00:00:03', now - 23 * hour - 1);
      await insert('AA:AA:AA:00:00:04', now - 24 * hour - 1);
      await insert('AA:AA:AA:00:00:05', now + 5 * hour);
      final h = await db.hourlyMacCounts(now);
      expect(h.length, 24);
      expect(h[23], 2);
      expect(h[21], 1);
      expect(h[0], 1);
      expect(h.fold(0, (a, b) => a + b), 4);
    });
  });

  group('widgets', () {
    testWidgets('the bars painter draws and repaints on new counts', (tester) async {
      final a = HourBarsPainter(const [0, 3, 6], Colors.red, track);
      expect(a.shouldRepaint(HourBarsPainter(const [0, 3, 7], Colors.red, track)), isTrue);
      expect(a.shouldRepaint(HourBarsPainter(const [0, 3, 6], Colors.red, track)), isFalse);
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(width: 120, height: 28, child: CustomPaint(painter: a, size: Size.infinite)),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the results sheet shows area chips and narrows by area', (tester) async {
      final results = searchEntries('axon', [
        _e(SearchArea.devices, 'Axon camera', ['axon']),
        _e(SearchArea.alerts, 'Axon alert', ['axon']),
        _e(SearchArea.nodes, 'Other', ['zzz']),
      ]);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showSearchResults(context, ref, results),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-chip-all')), findsOneWidget);
      expect(find.byKey(const Key('search-chip-devices')), findsOneWidget);
      expect(find.byKey(const Key('search-chip-alerts')), findsOneWidget);
      expect(find.byKey(const Key('search-chip-nodes')), findsNothing);
      expect(find.text('Axon camera'), findsOneWidget);
      expect(find.text('Axon alert'), findsOneWidget);
      await tester.tap(find.byKey(const Key('search-chip-alerts')));
      await tester.pumpAndSettle();
      expect(find.text('Axon camera'), findsNothing);
      expect(find.text('Axon alert'), findsOneWidget);
    });
  });
}
