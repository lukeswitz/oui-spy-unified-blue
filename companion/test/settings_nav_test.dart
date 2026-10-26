import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
    expect(find.text('Detection & alerts'), findsOneWidget);
    expect(find.text('Alerts'), findsNothing);

    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();
    expect(find.text('Capture database'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Capture database'), findsNothing);

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
  });
}
