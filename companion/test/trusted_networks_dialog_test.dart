// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/trusted_networks.dart';
import 'package:oui_spy/features/trusted/trusted_networks_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the Trust a network dialog closes through its exit animation with no exception', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final registry = DeviceRegistry(vendorOf: (_) => null);
    final container = ProviderContainer(overrides: [
      deviceRegistryProvider.overrideWith((ref) => registry),
      trustedNetworksProvider.overrideWith((ref) => TrustedNetworks(persist: false)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const TrustedNetworksScreen()),
    ));

    for (final close in ['CANCEL', 'barrier']) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Trust a network'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'MyNetwork');
      if (close == 'CANCEL') {
        await tester.tap(find.text('CANCEL'));
      } else {
        await tester.tapAt(const Offset(2, 2));
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Trust a network'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(container.read(trustedNetworksProvider).networks, isEmpty);
  });
}
