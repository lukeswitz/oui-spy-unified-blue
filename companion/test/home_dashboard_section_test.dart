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
    expect(connectorStatus(DashboardConnector.meshtastic, const ConnectorInfo(enabled: true, state: 'retrying', error: 'x')),
        'Not connected: retrying');
    expect(connectorStatus(DashboardConnector.meshtastic, const ConnectorInfo()), 'Off');
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
    expect(find.text('Meshtastic'), findsOneWidget);
    expect(find.textContaining('Not connected: retrying'), findsOneWidget);
    expect(find.text('Meshtastic settings'), findsOneWidget);
    expect(find.textContaining('Connected'), findsWidgets);
    expect(find.text('14 days'), findsOneWidget);
    expect(find.textContaining("set on the dashboard's Settings tab"), findsNothing);

    await tester.tap(find.text('TAK server'));
    await tester.pump();
    expect(api.posts.last, {'tak': {'enabled': true}});

    await tester.tap(find.byTooltip('About Connectors'));
    await tester.pumpAndSettle();
    expect(find.textContaining("set on the dashboard's Settings tab"), findsOneWidget);
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

  Future<FakeApi> openMesh(WidgetTester tester, [FakeApi? given]) async {
    final api = given ?? FakeApi();
    final n = DashboardNotifier(
        api: api, discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
    await tester.runAsync(() async {
      await n.setEnabled(true);
      await n.setHost('192.0.2.5');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await pump(tester, n);
    await tester.ensureVisible(find.text('Meshtastic settings'));
    await tester.tap(find.text('Meshtastic settings'));
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('the Meshtastic sheet shows the radio, ports, channels, events, state and inbox', (tester) async {
    await openMesh(tester);
    expect(find.text('MESHTASTIC'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Radio port'), findsOneWidget);
    expect(find.textContaining('USB JTAG/serial'), findsOneWidget);
    expect(find.textContaining('an ESP32 (likely one of our nodes)'), findsOneWidget);
    expect(find.text('0: LongFast'), findsOneWidget);
    expect(find.text('Public channel: the dashboard does not send on it'), findsOneWidget);
    expect(find.text('1: Fleet'), findsOneWidget);
    for (final t in ['New devices', 'A batch a minute', 'Drones', 'When one is first heard', 'Lost nodes',
      'A lost node seen again', 'Nodes joining and dropping']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Dashboard Radio !0a1b2c3d'), findsOneWidget);
    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('Last sent'), findsOneWidget);
    expect(find.textContaining('North Gate'), findsOneWidget);
    expect(find.text('all quiet'), findsOneWidget);
    expect(find.textContaining('Meshtastic airtime is shared'), findsNothing);
    expect(find.text('Nothing heard yet. Text messages on the channel land here.'), findsNothing);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Radio port')).controller!.text, '/dev/ttyUSB0');
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Also send to nodes (optional)')).controller!.text,
        '!0b0c0d0e');
    await tester.ensureVisible(find.byTooltip('About CHANNEL'));
    await tester.tap(find.byTooltip('About CHANNEL'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Meshtastic airtime is shared'), findsOneWidget);
  });

  testWidgets('with nothing heard, no ports and no radio the sheet says so', (tester) async {
    final api = FakeApi()
      ..ports = []
      ..meshtastic = {'config': <String, dynamic>{}, 'state': 'off'};
    await openMesh(tester, api);
    expect(find.text('No serial ports.'), findsOneWidget);
    expect(find.text('Nothing heard yet. Text messages on the channel land here.'), findsOneWidget);
    expect(find.textContaining('Channel 1. The channels of the radio show here'), findsOneWidget);
    expect(find.text('Needs a connected radio'), findsOneWidget);
  });

  testWidgets('port, events and recipients are saved to the dashboard in one go', (tester) async {
    final api = await openMesh(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Radio port'), 'tcp:192.0.2.7');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Also send to nodes (optional)'), '!0b0c0d0e !4D5E6F70');
    await tapText(tester, 'Drones');
    await tapText(tester, 'Nodes joining and dropping');
    expect(find.text('Changes not saved yet'), findsOneWidget);
    await tapText(tester, 'Save');
    expect(api.posts.last, {
      'meshtastic': {
        'enabled': true,
        'port': 'tcp:192.0.2.7',
        'channel': 1,
        'recipients': ['!0b0c0d0e', '!4d5e6f70'],
        'send': {'new_devices': true, 'drones': true, 'lost_nodes': false, 'nodes': false},
      }
    });
    expect(find.text('Meshtastic settings saved'), findsOneWidget);
  });

  testWidgets('a bad recipient is not sent, and Undo puts the saved settings back', (tester) async {
    final api = await openMesh(tester);
    final recipients = find.widgetWithText(TextField, 'Also send to nodes (optional)');
    await tester.enterText(recipients, 'nope');
    await tester.pump();
    await tapText(tester, 'Save');
    expect(find.text('A node id is ! and 8 hex digits, like !0a1b2c3d'), findsOneWidget);
    expect(api.posts, isEmpty);
    await tapText(tester, 'Undo');
    expect(tester.widget<TextField>(recipients).controller!.text, '!0b0c0d0e');
    expect(find.text('Changes not saved yet'), findsNothing);
  });

  testWidgets('a refused save shows the dashboard reason', (tester) async {
    final api = await openMesh(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Radio port'), '/etc/passwd');
    await tester.pump();
    api.failWith = const DashboardError(DashboardFault.rejected, 'Meshtastic: the radio port is a serial port');
    await tapText(tester, 'Save');
    expect(find.text('Not saved: Meshtastic: the radio port is a serial port'), findsOneWidget);
  });

  testWidgets('the public channel cannot be picked, a private one can', (tester) async {
    final api = FakeApi();
    (api.meshtastic['config'] as Map<String, dynamic>)['channel'] = 3;
    (api.meshtastic['channels'] as List).add({'index': 3, 'name': 'Ops', 'role': 'secondary', 'private': true});
    await openMesh(tester, api);
    await tapText(tester, '0: LongFast');
    await tapText(tester, '1: Fleet');
    await tapText(tester, 'Save');
    expect(((api.posts.last['meshtastic'] as Map)['channel']), 1);
  });

  testWidgets('a test asks first, names the channel and recipients, and is sent as last saved', (tester) async {
    final api = await openMesh(tester);
    await tapText(tester, 'Send a test');
    expect(find.text('Send a test?'), findsOneWidget);
    expect(
        find.textContaining('"OUI-APEX Mesh: test message from the dashboard." on channel 1 and to each recipient, '
            'as last saved. Everyone on that channel sees it.'),
        findsOneWidget);
    expect(find.textContaining('not saved yet'), findsNothing);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.endsWith('/api/meshtastic/test')), isEmpty);
    await tapText(tester, 'Drones');
    await tapText(tester, 'Send a test');
    expect(find.textContaining('The changes on this screen are not saved yet, so they are not used.'), findsOneWidget);
    await tester.tap(find.text('SEND'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.endsWith('/api/meshtastic/test')), hasLength(1));
    expect(find.text('Test queued'), findsOneWidget);
  });

  testWidgets('a test the dashboard refuses shows why', (tester) async {
    final api = await openMesh(tester);
    api.failWith = const DashboardError(DashboardFault.rejected, 'the radio is not connected');
    await tapText(tester, 'Send a test');
    await tester.tap(find.text('SEND'));
    await tester.pumpAndSettle();
    expect(find.text('Test not sent: the radio is not connected'), findsOneWidget);
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
