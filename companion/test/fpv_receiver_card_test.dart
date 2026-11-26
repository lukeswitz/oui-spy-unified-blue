// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_log.dart';
import 'package:oui_spy/features/drones/drones_screen.dart';
import 'package:oui_spy/features/fpv/fpv_state.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _golden =
    '0103030499163c520a0c020004030201ffff1fff7fff10020000000000050a0f14191e23282d32373c41464b50555a5f64'
    'ffffff787d82878c91969ba0a5aaafb4b9beff00050a0f14191e2300070e151c232a31383f464d545b62040b12192027'
    '000000434a51585f01080f161d242b323940004e555c63050c131a';

FpvState _state() => FpvState.decode([
      for (var i = 0; i < _golden.length; i += 2) int.parse(_golden.substring(i, i + 2), radix: 16),
    ])!;

class _FpvBle extends BleManager {
  _FpvBle({this.available = true, this.boardName = 'ESP32-C5', FpvState? state}) : _state = state ?? FpvState.empty;
  final bool available;
  final String boardName;
  final FpvState _state;

  @override
  String get board => boardName;

  @override
  bool get fpvAvailable => available;

  @override
  FpvState get latestFpvState => _state;

  @override
  Stream<FpvState> get fpvState => const Stream<FpvState>.empty();
}

class _EmptyLog extends DroneLog {
  @override
  Future<List<DroneReport>> query({DateTime? from, DateTime? to}) async => const [];
}

Future<List<String>> _pump(WidgetTester tester, BleManager ble) async {
  SharedPreferences.setMockInitialValues({});
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    droneLogProvider.overrideWithValue(_EmptyLog()),
    databaseProvider.overrideWithValue(db),
    bleManagerProvider.overrideWith((ref) {
      ref.onDispose(ble.dispose);
      return ble;
    }),
  ]);
  addTearDown(container.dispose);
  final opened = <String>[];
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const DronesScreen()),
    GoRoute(
      path: '/fpv',
      builder: (_, _) {
        opened.add('/fpv');
        return const Scaffold(body: Text('fpv screen'));
      },
    ),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
  ));
  await tester.pump();
  await tester.pump();
  return opened;
}

void main() {
  testWidgets('the Drones list shows the FPV receiver state and opens the FPV screen', (tester) async {
    final opened = await _pump(tester, _FpvBle(state: _state()));
    final card = find.byKey(const Key('fpv-receiver-card'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('FPV RECEIVER')), findsOneWidget);
    expect(find.byKey(const Key('fpv-receiver-state')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('fpv-receiver-state'))).data, 'LOCKED');
    expect(find.descendant(of: card, matching: find.text('A5 · 5785 MHz')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('60')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('drone-source-rid')));
    await tester.pump();
    expect(card, findsNothing);
    await tester.tap(find.byKey(const Key('drone-source-fpv')));
    await tester.pump();
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, ['/fpv']);
    expect(find.text('fpv screen'), findsOneWidget);
  });

  testWidgets('an off receiver shows OFF with no channel', (tester) async {
    await _pump(tester, _FpvBle());
    expect(tester.widget<Text>(find.byKey(const Key('fpv-receiver-state'))).data, 'OFF');
    expect(find.text('Channel '), findsNothing);
  });

  testWidgets('the card is absent when the board has no FPV receiver', (tester) async {
    await _pump(tester, _FpvBle(available: false));
    expect(find.byKey(const Key('fpv-receiver-card')), findsNothing);
  });

  testWidgets('the card is absent on a board that is not a C5', (tester) async {
    await _pump(tester, _FpvBle(boardName: 'ESP32-S3'));
    expect(find.byKey(const Key('fpv-receiver-card')), findsNothing);
  });
}
