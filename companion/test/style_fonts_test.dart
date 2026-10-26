import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/features/onboarding/permissions_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';

void main() {
  tearDown(() {
    AppTheme.applyBrightness(Brightness.dark);
    AppTheme.mono = AppStyle.standard.monoFamily;
  });

  test('body family follows the style', () {
    expect(AppTheme.themeFor(AppStyle.paperDark, Brightness.dark).textTheme.bodyLarge!.fontFamily, 'Inter');
    expect(AppTheme.themeFor(AppStyle.terminal, Brightness.dark).textTheme.bodyLarge!.fontFamily, 'Menlo');
  });

  test('mono family follows the style', () {
    expect(AppStyle.terminal.monoFamily, 'Menlo');
    expect(AppStyle.graphite.monoFamily, 'JetBrainsMono');
  });

  test('font assets exist', () {
    for (final f in [
      'Inter-Regular.ttf',
      'Inter-Medium.ttf',
      'Inter-SemiBold.ttf',
      'JetBrainsMono-Regular.ttf',
      'JetBrainsMono-Medium.ttf',
    ]) {
      expect(File('assets/fonts/$f').existsSync(), isTrue, reason: f);
    }
  });

  testWidgets('AppTheme.mono tracks the watched style', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: PermissionsOnboardingApp(onDone: () {}),
    ));
    container.read(appStyleProvider.notifier).state = AppStyle.paperDark;
    await tester.pump();
    expect(AppTheme.mono, 'JetBrainsMono');
    container.read(appStyleProvider.notifier).state = AppStyle.terminal;
    await tester.pump();
    expect(AppTheme.mono, 'Menlo');
  });
}
