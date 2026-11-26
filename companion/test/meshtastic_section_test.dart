// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/features/config/meshtastic_section.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meshtastic_state_test.dart' show FakeBle, FakeLink, channel, myInfo, nodeInfo;

Future<void> pump(WidgetTester tester, MeshtasticNotifier n) async {
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [meshtasticProvider.overrideWith((ref) => n)],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: SingleChildScrollView(child: MeshtasticSection())),
    ),
  ));
  await tester.pump();
}

Future<void> later(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pump();
}

void main() {
  late FakeLink link;
  late FakeBle ble;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    link = FakeLink()
      ..setup = [myInfo(1), nodeInfo(2, 'North Gate'), channel(0, 1, 1, ''), channel(1, 2, 32, 'Team')];
    ble = FakeBle(link);
  });

  Future<MeshtasticNotifier> connected(WidgetTester tester) async {
    final n = MeshtasticNotifier(ble: ble);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await n.connect(radio: ble.found.first);
    });
    return n;
  }

  testWidgets('no radio: it offers to find one and says nothing is sent without a tap', (tester) async {
    final n = MeshtasticNotifier(ble: ble);
    await pump(tester, n);
    expect(find.text('Find a radio'), findsOneWidget);
    expect(find.text('No radio'), findsOneWidget);
    expect(find.textContaining('never the public one'), findsNothing);
    await tester.tap(find.byTooltip('About Meshtastic radio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('never the public one'), findsOneWidget);
    expect(find.text('Send a message'), findsNothing);
  });

  testWidgets('finding a radio lists it and picking it connects', (tester) async {
    final n = MeshtasticNotifier(ble: ble);
    await pump(tester, n);
    await tester.tap(find.text('Find a radio'));
    await tester.pumpAndSettle();
    expect(find.text('Meshtastic radios nearby'), findsOneWidget);
    expect(find.text('Meshtastic_a1b2'), findsOneWidget);
    await tester.tap(find.text('Meshtastic_a1b2'));
    await later(tester);
    expect(n.state.link, MtLinkState.ready);
    expect(find.text('Ready  ·  Meshtastic_a1b2'), findsOneWidget);
  });

  testWidgets('connected: a message cannot be sent until a private channel is picked, then it goes out', (tester) async {
    final n = await connected(tester);
    await pump(tester, n);
    expect(find.text('Pick a private channel'), findsOneWidget);
    await tester.tap(find.text('Send a message'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Channel'));
    await tester.pumpAndSettle();
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('LongFast'), findsNothing);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send a message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'meet at the gate');
    await tester.pump();
    await tester.tap(find.text('SEND'));
    await later(tester);
    expect(link.writes, hasLength(2));
    expect(n.state.sent, 1);
    expect(find.text('Sent on the mesh'), findsOneWidget);
  });

  testWidgets('forgetting asks first', (tester) async {
    final n = await connected(tester);
    await pump(tester, n);
    await tester.ensureVisible(find.text('Forget this radio'));
    await tester.tap(find.text('Forget this radio'));
    await tester.pumpAndSettle();
    expect(find.text('Forget this radio?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(n.state.hasRadio, isTrue);
    await tester.tap(find.text('Forget this radio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FORGET'));
    await later(tester);
    expect(n.state.hasRadio, isFalse);
    expect(link.closedCalled, isTrue);
  });
}
