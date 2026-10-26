import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.darkTheme, home: const DeviceConfigScreen()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('App'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('style picker lists ten rows in enum order', (tester) async {
    await _pumpApp(tester);
    final labels = tester.widgetList<ConfigActionRow>(find.byType(ConfigActionRow)).map((r) => r.label).toList();
    expect(labels, AppStyle.values.map((s) => s.label).toList());
    expect(labels.length, 10);
    expect(labels.first, 'Paper dark');
  });

  testWidgets('section headers carry no numbers', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Units'), findsOneWidget);
    expect(find.text('01'), findsNothing);
    expect(find.text('02'), findsNothing);
    expect(find.text('03'), findsNothing);
  });

  testWidgets('selecting Graphite sets the style', (tester) async {
    final container = await _pumpApp(tester);
    await tester.tap(find.text('Graphite'));
    await tester.pumpAndSettle();
    expect(container.read(appStyleProvider), AppStyle.graphite);
  });

  testWidgets('Dark Mode toggle only while Default is selected', (tester) async {
    final container = await _pumpApp(tester);
    expect(find.text('Dark Mode'), findsNothing);
    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();
    expect(container.read(appStyleProvider), AppStyle.standard);
    expect(find.text('Dark Mode'), findsOneWidget);
    await tester.tap(find.text('Black'));
    await tester.pumpAndSettle();
    expect(find.text('Dark Mode'), findsNothing);
  });

  testWidgets('destructive ConfigActionRow uses error for icon, text and hairline', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: ConfigActionRow(icon: Icons.restart_alt, label: 'Reset', destructive: true, onTap: () {}),
      ),
    ));
    final row = find.byType(ConfigActionRow);
    final icon = tester.widget<Icon>(find.descendant(of: row, matching: find.byIcon(Icons.restart_alt)));
    expect(icon.color, AppTheme.error);
    final text = tester.widget<Text>(find.descendant(of: row, matching: find.text('Reset')));
    expect(text.style?.color, AppTheme.error);
    final decos = tester
        .widgetList<Container>(find.descendant(of: row, matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    expect(decos.any((d) => d.border is Border && (d.border as Border).bottom.color == AppTheme.error), isTrue);
  });

  test('no Color(0x literals in notification settings or role-only files', () {
    for (final f in [
      'lib/features/notifications/notification_settings_screen.dart',
      'lib/features/config/config_detections_tab.dart',
      'lib/features/config/config_wardrive_settings.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('Color(0x'), isFalse, reason: f);
    }
  });

  testWidgets('ConfigActionRow has a hairline bottom border and no rounded container', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: ConfigActionRow(icon: Icons.code, label: 'Row', onTap: () {})),
    ));
    final boxes = tester
        .widgetList<Container>(find.descendant(of: find.byType(ConfigActionRow), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(boxes.any((d) => d.border is Border && (d.border as Border).bottom.width > 0), isTrue);
    expect(boxes.every((d) => d.borderRadius == null || d.borderRadius == BorderRadius.zero), isTrue);
  });
}
