import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get scanning => false;

  @override
  bool get radioListening => false;

  @override
  int get radioMask => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ResolvedTheme> _pump(WidgetTester tester, AppStyle style) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
  container.read(wardriveProvider).selectedTargets.add(WardriveTarget.wigle);
  final brightness = style.brightness ?? Brightness.dark;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.themeFor(style, brightness),
      home: const Scaffold(body: SessionTargets()),
    ),
  ));
  await tester.pump();
  return style.palette(brightness);
}

Container _chip(WidgetTester tester, WardriveTarget m) =>
    tester.widget<Container>(find.byKey(ValueKey('target-chip-${m.name}')));

void main() {
  for (final style in [AppStyle.paperDark, AppStyle.paper]) {
    testWidgets('${style.name}: unselected tile is surfaceLight with readable label, no border', (tester) async {
      final p = await _pump(tester, style);
      final deco = _chip(tester, WardriveTarget.drone).decoration! as BoxDecoration;
      expect(deco.color, p.surfaceLight);
      expect(deco.border, isNull);
      expect(deco.borderRadius, BorderRadius.circular(AppRadius.chip));
      final label = tester.widget<Text>(find.text('DRONE'));
      expect(label.style!.color, p.textPrimary);
      expect(AppTheme.contrast(label.style!.color!, p.surfaceLight), greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('${style.name}: selected tile is textPrimary with background label', (tester) async {
      final p = await _pump(tester, style);
      final deco = _chip(tester, WardriveTarget.wigle).decoration! as BoxDecoration;
      expect(deco.color, p.textPrimary);
      final label = tester.widget<Text>(find.text('WIGLE'));
      expect(label.style!.color, p.background);
      expect(AppTheme.contrast(label.style!.color!, p.textPrimary), greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('tiles are equal width, 60 high, gap 8', (tester) async {
    await _pump(tester, AppStyle.paperDark);
    final rects = [
      for (final m in WardriveController.selectableTargets)
        tester.getRect(find.byKey(ValueKey('target-chip-${m.name}'))),
    ];
    expect(rects.map((r) => r.height).toSet(), {60.0});
    expect(rects.map((r) => r.width.roundToDouble()).toSet().length, 1);
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left - rects[i - 1].right, closeTo(8, 0.01));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('radio picker is a borderless rounded track with the three segments inside', (tester) async {
    final p = await _pump(tester, AppStyle.paperDark);
    final control = find.byKey(const ValueKey('radio-control'));
    expect(control, findsOneWidget);
    final box = tester.widget<Container>(control);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, p.surfaceLight);
    expect(deco.border, isNull);
    expect(deco.borderRadius, BorderRadius.circular(AppRadius.control));
    expect(box.padding, const EdgeInsets.all(3));
    for (final l in ['WiFi', 'BLE', 'WiFi+BLE']) {
      expect(find.descendant(of: control, matching: find.text(l)), findsOneWidget, reason: l);
    }
    expect(tester.getSize(control).height, 40);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selected radio segment is a textPrimary pill with background text', (tester) async {
    final p = await _pump(tester, AppStyle.paperDark);
    final control = find.byKey(const ValueKey('radio-control'));
    final selected = find.descendant(
      of: control,
      matching: find.byWidgetPredicate((w) => w is Material && w.color == p.textPrimary),
    );
    expect(selected, findsOneWidget);
    expect(tester.getSize(selected).height, closeTo(34, 1));
    final both = tester.widget<Text>(find.descendant(of: control, matching: find.text('WiFi+BLE')));
    expect(both.style!.color, p.background);
    final wifi = tester.widget<Text>(find.descendant(of: control, matching: find.text('WiFi')));
    expect(wifi.style!.color, p.textSecondary);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the SESSION eyebrow is gone from the widget', (tester) async {
    await _pump(tester, AppStyle.paperDark);
    expect(find.text('SESSION'), findsNothing);
    expect(find.text('IDLE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final c in [(AppStyle.paperDark, 'Inter'), (AppStyle.terminal, 'Menlo')]) {
    testWidgets('${c.$1.name}: elevated, outlined and segmented labels use ${c.$2}', (tester) async {
      final theme = AppTheme.themeFor(c.$1, c.$1.brightness ?? Brightness.dark);
      expect(theme.elevatedButtonTheme.style!.textStyle!.resolve({})!.fontFamily, c.$2);
      expect(theme.outlinedButtonTheme.style!.textStyle!.resolve({})!.fontFamily, c.$2);
      expect(theme.segmentedButtonTheme.style!.textStyle!.resolve({})!.fontFamily, c.$2);
    });
  }
}
