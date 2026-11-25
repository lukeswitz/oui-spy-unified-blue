// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/find_it.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/engines/find_it_pulse.dart';
import 'package:oui_spy/features/engines/foxhunter_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/smoke_hook.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 1, 1, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interval', () {
    test('1400 ms at -95 dBm and below, 90 ms at -35 dBm and above', () {
      expect(findItInterval(-100).inMilliseconds, 1400);
      expect(findItInterval(-95).inMilliseconds, 1400);
      expect(findItInterval(-35).inMilliseconds, 90);
      expect(findItInterval(-20).inMilliseconds, 90);
      expect(findItInterval(null).inMilliseconds, 1400);
    });

    test('a stronger signal never pulses slower', () {
      var prev = findItInterval(-100);
      for (var r = -99; r <= -30; r++) {
        final i = findItInterval(r);
        expect(i <= prev, isTrue, reason: 'rssi $r');
        prev = i;
      }
      expect(findItInterval(-65).inMilliseconds, 1073);
    });
  });

  group('reading', () {
    FindItReading? pick({int board = -80, int boardMs = 500, DateTime? at, Map<String, FindItHeard> heard = const {}}) =>
        pickFindItReading(
          boardRssi: board,
          boardIntervalMs: boardMs,
          boardAt: at,
          boardNodeId: 'HUNTER',
          heard: heard,
          now: _now,
        );

    test('the board reading is used while fresh', () {
      final r = pick(at: _now.subtract(const Duration(seconds: 2)))!;
      expect((r.nodeId, r.rssi), ('HUNTER', -80));
      expect(pick(at: _now.subtract(const Duration(seconds: 6))), isNull);
      expect(pick(at: _now, boardMs: 0), isNull);
    });

    test('the node that hears it best wins, and stale nodes are ignored', () {
      final r = pick(
        at: _now,
        heard: {
          'NODE1': (rssi: -60, at: _now.subtract(const Duration(seconds: 3))),
          'NODE2': (rssi: -50, at: _now.subtract(const Duration(seconds: 30))),
          'NODE3': (rssi: -70, at: _now),
        },
      )!;
      expect((r.nodeId, r.rssi), ('NODE1', -60));
    });
  });

  testWidgets('the ring pulses faster, and calls onPulse faster, as the signal rises', (tester) async {
    Future<int> pulses(int? rssi) async {
      var n = 0;
      await tester.pumpWidget(MaterialApp(
        home: FindItPulse(
          key: UniqueKey(),
          rssi: rssi,
          color: Colors.green,
          onPulse: () => n++,
          child: const SizedBox(width: 100, height: 100),
        ),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox());
      return n;
    }

    final far = await pulses(-100);
    final mid = await pulses(-50);
    final near = await pulses(-35);
    final none = await pulses(null);
    expect(far, 2);
    expect(mid, 4);
    expect(near, greaterThanOrEqualTo(20));
    expect(none, 0);
  });

  testWidgets('FIND IT keeps the HUNT control and, on a desktop, shows why the phone cannot buzz', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const FoxhunterScreen()),
    ));
    expect(find.text('HUNT'), findsOneWidget);
    expect(find.byKey(const Key('find-it-buzz')), findsNothing);

    container.read(appStateProvider).setFoxhunterTarget('02:00:00:00:01:00', fromPhone: true);
    await tester.pump();
    expect(find.text('STOP'), findsOneWidget);
    expect(find.text('Waiting for a node to hear it.'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('find-it-buzz'))).onPressed, isNull);
    expect(find.textContaining('cannot vibrate'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('the app records each node that hears the hunted device and the best one is the reading', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    final ble = container.read(bleManagerProvider);
    final app = container.read(appStateProvider);
    const mac = '02:00:00:00:01:00';

    ble.injectDetectionFrame(smokeFrame(Engine.wardrive, mac, -90, 1, 0, List.filled(55, 0)));
    await Future<void>.delayed(Duration.zero);
    expect(app.foxhunterHeardBy, isEmpty);

    app.setFoxhunterTarget(mac, fromPhone: true);
    ble.injectDetectionFrame(smokeFrame(Engine.wardrive, mac, -55, 1, 0, List.filled(55, 0)));
    ble.injectDetectionFrame(smokeFrame(Engine.wardrive, '02:00:00:00:09:09', -30, 1, 0, List.filled(55, 0)));
    await Future<void>.delayed(Duration.zero);
    expect(app.foxhunterHeardBy.values.single.rssi, -55);
    expect(app.foxhunterReading()!.rssi, -55);

    app.clearFoxhunterTarget();
    expect(app.foxhunterHeardBy, isEmpty);
    expect(app.foxhunterReading(), isNull);
  });
}
