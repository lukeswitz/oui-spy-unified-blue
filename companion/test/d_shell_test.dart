import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/app.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/home/engine_card.dart';
import 'package:oui_spy/features/home/home_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get scanning => false;

  @override
  bool get radioListening => false;

  @override
  int get radioMask => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
}

void main() {
  testWidgets('disconnected view: title, primary connect, every engine preview', (tester) async {
    final container = await _container(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
    ));
    await tester.pump();

    final title = find.byWidgetPredicate((w) => w is Text && w.data == 'OUI-APEX' && w.style?.fontSize == 28);
    expect(title, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'CONNECT'), findsOneWidget);
    for (final e in Engine.values) {
      expect(find.text(e.label), findsWidgets, reason: e.name);
    }
    expect(find.byType(EngineCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disconnected view is a centered column with a three-circle radar', (tester) async {
    final container = await _container(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
    ));
    await tester.pump();

    final titleFinder = find.byWidgetPredicate((w) => w is Text && w.data == 'OUI-APEX' && w.style?.fontSize == 28);
    expect(tester.widget<Text>(titleFinder).textAlign, TextAlign.center);
    final column = tester.widget<Column>(find.ancestor(of: titleFinder, matching: find.byType(Column)).first);
    expect(column.crossAxisAlignment, CrossAxisAlignment.center);

    final radar = find.ancestor(of: find.byIcon(Icons.radar), matching: find.byType(Stack)).first;
    final circles = tester
        .widgetList<Container>(find.descendant(of: radar, matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(circles.length, 3);

    final connect = tester.getSize(find.widgetWithText(OutlinedButton, 'CONNECT'));
    expect(connect.height, 52);
    final shape = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'CONNECT')).style!.shape!.resolve({});
    expect((shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.card));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bottom nav has four tabs and routes to each page', (tester) async {
    final container = await _container(tester);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            for (final p in ['/home', '/detections', '/wardrive', '/config'])
              GoRoute(path: p, builder: (_, _) => Text('page $p')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    final nav = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(nav.items.map((i) => i.label), ['Home', 'Detections', 'Map', 'Settings']);
    expect(find.byKey(const ValueKey('nav-active-bar')), findsOneWidget);

    final expected = {
      'Detections': '/detections',
      'Map': '/wardrive',
      'Settings': '/config',
      'Home': '/home',
    };
    for (final entry in expected.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.value);
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('pcap banner and shell use style roles, no literal colors or radii', () {
    final src = File('lib/app.dart').readAsStringSync();
    expect(src.contains('0xFF1E2A28'), isFalse);
    expect(src.contains('0xFF4AFFCC'), isFalse);
    expect(src.contains('Color(0x'), isFalse);
    expect(src.contains('BorderRadius.circular('), isFalse);
    expect(src.contains('elevation:'), isFalse);
    expect(src.contains('.fill'), isTrue);
  });
}
