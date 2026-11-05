import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/features/onboarding/permissions_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';

void main() {
  group('pendingPermissionSteps', () {
    PermissionStep step(String name, [bool? granted]) => PermissionStep(
          icon: Icons.check,
          title: name,
          body: '$name body',
          request: (_) async {},
          done: granted == null ? null : () async => granted,
        );
    final steps = [step('Bluetooth'), step('Always', false), step('Battery', true)];
    Future<List<String>> pending(Map<String, Object> saved) async {
      SharedPreferences.setMockInitialValues(saved);
      final prefs = await SharedPreferences.getInstance();
      return (await pendingPermissionSteps(prefs, steps)).map((s) => s.title).toList();
    }

    test('fresh install gets every step', () async {
      expect(await pending({}), ['Bluetooth', 'Always', 'Battery']);
    });

    test('existing install gets only the steps not granted yet', () async {
      expect(await pending({'map_style': 'dark'}), ['Always']);
      expect(await pending({'permissions_onboarded': true}), ['Always']);
    });

    test('nothing again after this flow has run', () async {
      expect(await pending({kPermissionsOnboardedKey: true}), isEmpty);
    });
  });

  testWidgets('each Continue asks for one permission, in order, then finishes', (tester) async {
    final asked = <String>[];
    var done = false;
    PermissionStep step(String name) => PermissionStep(
          icon: Icons.check,
          title: name,
          body: '$name body',
          request: (_) async => asked.add(name),
        );

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.themeFor(AppStyle.standard, Brightness.dark),
        home: PermissionsScreen(
          onDone: () => done = true,
          steps: [step('Bluetooth'), step('Location'), step('Notifications')],
        ),
      ),
    ));

    for (final (i, name) in ['Bluetooth', 'Location', 'Notifications'].indexed) {
      expect(find.text(name), findsOneWidget);
      expect(find.textContaining('Step ${i + 1} of 3'), findsOneWidget);
      expect(asked.length, i);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump();
    }
    expect(asked, ['Bluetooth', 'Location', 'Notifications']);
    expect(done, isTrue);
  });
}
