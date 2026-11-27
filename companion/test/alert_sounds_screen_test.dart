// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/melody_state.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/alert_sounds_screen.dart';
import 'package:oui_spy/features/notifications/notification_settings_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get radioListening => false;

  @override
  String get name => 'test';

  @override
  Stream<Observation> get observations => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _open(WidgetTester tester, {Widget home = const AlertSoundsScreen()}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(390, 5000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.darkTheme, home: home),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('every alert slot has a row that names its Default tune', (tester) async {
    await _open(tester);
    for (final s in kAlertSlots.where((s) => s.engine != melodyAny)) {
      expect(find.byKey(ValueKey('slot-${s.key}')), findsOneWidget, reason: s.label);
    }
    expect(find.byKey(const ValueKey('slot-255:255')), findsNothing);
    expect(find.text('Default (Chime)'), findsWidgets);
    expect(find.text('Default (Siren)'), findsOneWidget);
    expect(find.text('Default (Lub-dub)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a tune from the sheet assigns it to that alert only', (tester) async {
    final c = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('slot-0:2')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a tune. Play tries it on the board.'), findsOneWidget);
    final sheetList = find.descendant(
      of: find.ancestor(of: find.byKey(const ValueKey('pick-default')), matching: find.byType(ListView)),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.byKey(const ValueKey('pick-siren')), 100, scrollable: sheetList.first);
    await tester.tap(find.byKey(const ValueKey('pick-siren')));
    await tester.pumpAndSettle();
    final mel = c.read(melodyProvider);
    expect(mel.assignmentFor(kAlertSlots.firstWhere((s) => s.key == '0:2')), 'siren');
    expect(mel.assignmentFor(kAlertSlots.first), isNull);
    expect(find.text('Siren'), findsWidgets);
    expect(find.text('Default (Siren)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slot-0:3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-silent')));
    await tester.pumpAndSettle();
    expect(mel.assignmentFor(kAlertSlots.firstWhere((s) => s.key == '0:3')), melodySilent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notifications opens Alert sounds without a board', (tester) async {
    await _open(tester, home: const Scaffold(body: NotificationSettingsBody()));
    final row = find.byKey(const ValueKey('notif-alert-sounds'));
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slot-0:0')), findsOneWidget);
  });

  testWidgets('composer lays out on a phone and the arrows move the pitch', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Compose a tune'));
    await tester.pumpAndSettle();
    expect(find.text('C5'), findsOneWidget);
    await tester.tap(find.byTooltip('Higher'));
    await tester.pump();
    expect(find.text('C#5'), findsOneWidget);
    expect(find.text('Pause after'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
