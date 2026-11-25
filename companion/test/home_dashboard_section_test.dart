// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';
import 'package:oui_spy/core/dashboard/dashboard_state.dart';
import 'package:oui_spy/features/config/home_dashboard_section.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_state_test.dart' show FakeApi, FakeDiscovery, FakeTokens;

Future<void> pump(WidgetTester tester, DashboardNotifier n) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [dashboardProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: SingleChildScrollView(child: HomeDashboardSection())),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('connector status text', () {
    expect(connectorStatus(DashboardConnector.tak, const ConnectorInfo()), 'Off');
    expect(connectorStatus(DashboardConnector.tak, const ConnectorInfo(enabled: true, state: 'connected', sent: 12)),
        'Connected, 12 sent');
    expect(connectorStatus(DashboardConnector.mqtt, const ConnectorInfo(enabled: true, state: 'error', detail: 'refused: 5')),
        'Down: refused: 5');
    expect(connectorStatus(DashboardConnector.rns, const ConnectorInfo(enabled: true, state: 'error')), 'Down');
    expect(connectorStatus(DashboardConnector.tak, const ConnectorInfo(enabled: true, state: 'connecting')), 'Connecting');
  });

  testWidgets('off: only the switch shows', (tester) async {
    final n = DashboardNotifier(
        api: FakeApi(), discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
    await pump(tester, n);
    expect(find.text('Home dashboard'), findsOneWidget);
    expect(find.text('Link'), findsNothing);
    expect(find.text('Connectors'), findsNothing);
  });

  testWidgets('live: link, connectors and history rows, and a connector switch reaches the dashboard',
      (tester) async {
    final api = FakeApi();
    final n = DashboardNotifier(
        api: api, discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
    await tester.runAsync(() async {
      await n.setEnabled(true);
      await n.setHost('192.0.2.5');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pump(tester, n);
    expect(n.state.link, DashboardLink.live);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('3 of 4 online'), findsOneWidget);
    expect(find.text('MQTT'), findsOneWidget);
    expect(find.text('TAK server'), findsOneWidget);
    expect(find.text('Reticulum'), findsOneWidget);
    expect(find.textContaining('Connected'), findsWidgets);
    expect(find.text('14 days'), findsOneWidget);
    expect(find.textContaining("set on the dashboard's Settings tab"), findsOneWidget);

    await tester.tap(find.text('TAK server'));
    await tester.pump();
    expect(api.posts.last, {'tak': {'enabled': true}});
  });

  testWidgets('a refused change shows the dashboard reason', (tester) async {
    final api = FakeApi();
    final n = DashboardNotifier(
        api: api, discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
    await tester.runAsync(() async {
      await n.setEnabled(true);
      await n.setHost('192.0.2.5');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pump(tester, n);
    api.failWith = const DashboardError(DashboardFault.rejected, 'a TAK server address is needed');
    await tester.tap(find.text('TAK server'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Not changed: a TAK server address is needed'), findsOneWidget);
  });

  testWidgets('history retention is edited in a dialog and sent as days', (tester) async {
    final api = FakeApi();
    final n = DashboardNotifier(
        api: api, discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
    await tester.runAsync(() async {
      await n.setEnabled(true);
      await n.setHost('192.0.2.5');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pump(tester, n);
    await tester.ensureVisible(find.text('History kept'));
    await tester.tap(find.text('History kept'));
    await tester.pumpAndSettle();
    expect(find.text('Keep history for'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '30');
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(api.posts.last, {'retention_days': 30});
    expect(find.text('History kept 30 days'), findsOneWidget);
  });

  testWidgets('clearing history asks twice', (tester) async {
    final api = FakeApi();
    final n = DashboardNotifier(
        api: api, discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
    await tester.runAsync(() async {
      await n.setEnabled(true);
      await n.setHost('192.0.2.5');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pump(tester, n);
    await tester.ensureVisible(find.text('Clear detection history'));
    await tester.tap(find.text('Clear detection history'));
    await tester.pumpAndSettle();
    expect(find.text('Clear detection history?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(api.posts, isEmpty);
    await tester.tap(find.text('Clear detection history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTINUE'));
    await tester.pumpAndSettle();
    expect(find.text('Delete it all?'), findsOneWidget);
    await tester.tap(find.text('DELETE HISTORY'));
    await tester.pumpAndSettle();
    expect(api.posts.last, <String, dynamic>{});
    expect(find.text('Cleared 5 detections'), findsOneWidget);
  });
}
