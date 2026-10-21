import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/features/onboarding/permissions_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';

void main() {
  test('only a fresh install with no saved settings sees the permission steps', () async {
    SharedPreferences.setMockInitialValues({});
    expect(needsPermissionOnboarding(await SharedPreferences.getInstance()), isTrue);
    SharedPreferences.setMockInitialValues({kPermissionsOnboardedKey: true});
    expect(needsPermissionOnboarding(await SharedPreferences.getInstance()), isFalse);
    SharedPreferences.setMockInitialValues({'map_style': 'dark'});
    expect(needsPermissionOnboarding(await SharedPreferences.getInstance()), isFalse);
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
