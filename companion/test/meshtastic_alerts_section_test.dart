// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/meshtastic/mesh_alerts.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/features/config/meshtastic_alerts_section.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meshtastic_state_test.dart' show FakeBle, FakeLink, channel, myInfo, nodeInfo;

Future<void> pump(WidgetTester tester, MeshtasticNotifier mesh, MeshAlertNotifier alerts) async {
  await tester.binding.setSurfaceSize(const Size(400, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      meshtasticProvider.overrideWith((ref) => mesh),
      meshAlertProvider.overrideWith((ref) => alerts),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: MeshtasticSettingsPage()),
    ),
  ));
  await tester.pump();
}

bool on(WidgetTester tester, String label) => tester.widget<ConfigToggleRow>(find.widgetWithText(ConfigToggleRow, label)).value;

void main() {
  late FakeLink link;
  late FakeBle ble;
  late List<(String, List<int>)> sent;
  late DateTime now;

  MeshAlertNotifier alerts() => MeshAlertNotifier(
        send: (text, to) async {
          sent.add((text, to));
          return null;
        },
        clock: () => now,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    link = FakeLink()..setup = [myInfo(1), nodeInfo(2, 'North Gate'), channel(0, 1, 1, ''), channel(1, 2, 32, 'Team')];
    ble = FakeBle(link);
    sent = [];
    now = DateTime(2026, 3, 1, 12);
  });

  testWidgets('the page holds the radio section and the automatic alerts, with auto-send off', (tester) async {
    await pump(tester, MeshtasticNotifier(ble: ble), alerts());
    expect(find.text('Meshtastic radio'), findsOneWidget);
    expect(find.text('Find a radio'), findsOneWidget);
    expect(find.text('Automatic alerts'), findsOneWidget);
    expect(find.text('Send alerts automatically'), findsOneWidget);
    expect(on(tester, 'Send alerts automatically'), isFalse);
    expect(find.text('Messages only go out when you send them'), findsOneWidget);
    for (final type in MeshAlertType.values) {
      expect(find.text(type.label), findsOneWidget, reason: type.label);
    }
    expect(find.text('Flock'), findsOneWidget);
    expect(find.text('Drones'), findsOneWidget);
    expect(find.text('Detector and watchlist'), findsOneWidget);
    expect(find.text('Foxhunt'), findsOneWidget);
    expect(find.text('Node down and up'), findsOneWidget);
    expect(find.text('Minimum gap between messages'), findsOneWidget);
    expect(find.text('1 min'), findsOneWidget);
    expect(find.text('Messages per day'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('0 of 50 · skipped 0'), findsOneWidget);
    expect(find.text('Send to'), findsOneWidget);
    expect(find.text('The private channel'), findsOneWidget);
    await tester.tap(find.byTooltip('About Automatic alerts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A position is never sent'), findsOneWidget);
  });

  testWidgets('turning auto-send on asks first, and cancel leaves it off', (tester) async {
    final a = alerts();
    await pump(tester, MeshtasticNotifier(ble: ble), a);
    await tester.tap(find.text('Send alerts automatically'));
    await tester.pumpAndSettle();
    expect(find.text('Send alerts automatically?'), findsOneWidget);
    expect(find.textContaining('without a tap'), findsOneWidget);
    expect(find.textContaining('Everyone on the channel can read it'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(a.state.enabled, isFalse);
    expect(on(tester, 'Send alerts automatically'), isFalse);

    await tester.tap(find.text('Send alerts automatically'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TURN ON'));
    await tester.pumpAndSettle();
    expect(a.state.enabled, isTrue);
    expect(on(tester, 'Send alerts automatically'), isTrue);
    expect((await SharedPreferences.getInstance()).getBool('mt_alert_on'), isTrue);
    expect(find.textContaining('Alerts are skipped until the radio is connected'), findsOneWidget);

    await tester.tap(find.text('Send alerts automatically'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(a.state.enabled, isFalse);
  });

  testWidgets('the type toggles, sliders and destination change what the notifier holds', (tester) async {
    final a = alerts();
    await pump(tester, MeshtasticNotifier(ble: ble), a);
    expect(on(tester, 'Foxhunt'), isFalse);
    await tester.tap(find.text('Foxhunt'));
    await tester.pumpAndSettle();
    expect(a.state.types, contains(MeshAlertType.foxhunt));
    expect(on(tester, 'Foxhunt'), isTrue);
    await tester.tap(find.text('Drones'));
    await tester.pumpAndSettle();
    expect(a.state.types, isNot(contains(MeshAlertType.drone)));

    final gap = find.byType(Slider).at(0);
    await tester.drag(gap, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(a.state.gapSeconds, 10);
    expect(find.text('10 s'), findsOneWidget);
    final cap = find.byType(Slider).at(1);
    await tester.drag(cap, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(a.state.dailyCap, 1);
    expect(find.text('0 of 1 · skipped 0'), findsOneWidget);

    await tester.tap(find.text('Send to'));
    await tester.pumpAndSettle();
    expect(find.text('Send to nodes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '!0A1B2C3D, nope');
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE')).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '!0A1B2C3D, !01020304');
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(a.state.nodes, ['!0a1b2c3d', '!01020304']);
    expect(find.text('!0a1b2c3d, !01020304'), findsOneWidget);
    expect(find.text('The private channel'), findsNothing);
  });

  testWidgets('the sent and skipped counts show on the page', (tester) async {
    final a = alerts();
    await pump(tester, MeshtasticNotifier(ble: ble), a);
    await a.setEnabled(true);
    await tester.runAsync(() async {
      await a.handle(const AlertEvent(title: 'Flock camera', detail: 'x', channel: NotifChannel.flock));
      now = now.add(const Duration(seconds: 5));
      await a.handle(const AlertEvent(title: 'Flock camera', detail: 'x', channel: NotifChannel.flock));
    });
    await tester.pump();
    expect(sent, hasLength(1));
    expect(find.text('1 of 50 · skipped 1'), findsOneWidget);
  });
}
