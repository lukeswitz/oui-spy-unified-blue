// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/meshtastic/mesh_alerts.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meshtastic_state_test.dart' show FakeBle, FakeLink;

void main() {
  testWidgets('Data lists a Meshtastic radio page, and the radio is no longer inside Export', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      meshtasticProvider.overrideWith((ref) => MeshtasticNotifier(ble: FakeBle(FakeLink()))),
      meshAlertProvider.overrideWith((ref) => MeshAlertNotifier(send: (text, to) async => null)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DeviceConfigScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();
    expect(find.text('Meshtastic radio'), findsOneWidget);
    expect(find.text('Pair a radio, channel, messages, automatic alerts'), findsOneWidget);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('OUI database'), 300);
    expect(find.text('Home dashboard'), findsWidgets);
    expect(find.text('Find a radio'), findsNothing);
    await tester.tap(find.byTooltip('Data'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meshtastic radio'));
    await tester.pumpAndSettle();
    expect(find.text('Find a radio'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Send alerts automatically'), 300);
    expect(find.text('Automatic alerts'), findsOneWidget);
  });

  testWidgets('section opens as a page and pops back to overview', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(430, 932));
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DeviceConfigScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Detection & Alerts'), findsOneWidget);
    expect(find.text('Alerts'), findsNothing);

    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();
    expect(find.text('Capture Database'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Capture Database'), findsNothing);

    await tester.tap(find.text('App'));
    await tester.pumpAndSettle();
    expect(find.text('Cyberpunk'), findsOneWidget);
    expect(find.text('Dark Mode'), findsNothing);
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Dark Mode'), 200);
    expect(find.text('Dark Mode'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Terminal'), -200);
    await tester.tap(find.text('Terminal'));
    await tester.pumpAndSettle();
    expect(container.read(appStyleProvider), AppStyle.terminal);
    expect(find.text('Dark Mode'), findsNothing);
    final dark = AppTheme.themeFor(AppStyle.terminal, Brightness.dark);
    expect(dark.extension<ResolvedTheme>()!.background, const Color(0xFF000000));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Scanning'));
    await tester.pumpAndSettle();
    for (final sub in ['Timing & Re-log', 'Channels & Band', 'External Adapters']) {
      expect(find.text(sub), findsOneWidget, reason: sub);
    }
    await tester.tap(find.text('Timing & Re-log'));
    await tester.pumpAndSettle();
    expect(find.text('Wardrive RSSI'), findsOneWidget);
    expect(find.text('Channel range'), findsNothing);
    await tester.tap(find.byTooltip('Scanning'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Node'));
    await tester.pumpAndSettle();
    for (final sub in ['Sound & Lights', 'GPS Source', 'Flock Detection', 'Radio Privacy', 'Offline Scan', 'Mesh', 'Firmware', 'JCMK Node Hub']) {
      await tester.scrollUntilVisible(find.text(sub), 200);
      expect(find.text(sub), findsOneWidget, reason: sub);
    }
  });
}
