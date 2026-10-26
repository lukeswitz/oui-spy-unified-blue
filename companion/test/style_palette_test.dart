import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

const _newStyles = [
  AppStyle.paperDark,
  AppStyle.paper,
  AppStyle.graphite,
  AppStyle.black,
  AppStyle.slate,
];

List<(String, ResolvedTheme)> _allPalettes() => [
      for (final s in AppStyle.values)
        if (s.brightness != null)
          (s.name, s.palette(s.brightness!))
        else ...[
          ('standard dark', s.palette(Brightness.dark)),
          ('standard light', s.palette(Brightness.light)),
        ],
    ];

void main() {
  tearDown(() => AppTheme.applyBrightness(Brightness.dark));

  test('fresh install starts on paperDark', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(appStyleProvider), AppStyle.paperDark);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(appStyleProvider), AppStyle.paperDark);
  });

  test('saved style still wins', () async {
    SharedPreferences.setMockInitialValues({'app_style': 'terminal'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(appStyleProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(appStyleProvider), AppStyle.terminal);
  });

  test('new style palettes match spec', () {
    final p = AppStyle.paperDark.palette(Brightness.dark);
    expect(p.background, const Color(0xFF121211));
    expect(p.surface, const Color(0xFF1B1B19));
    expect(p.border, const Color(0xFF34342F));
    expect(p.rule, const Color(0xFFB4B4AE));
    expect(p.textPrimary, const Color(0xFFEDEDE8));
    expect(p.textSecondary, const Color(0xFFA9A9A2));
    expect(p.textDim, const Color(0xFF84847D));
    expect(p.fill, const Color(0xFF262622));
    expect(p.fillBorder, const Color(0xFF3A3A35));
    expect(p.onFill, const Color(0xFFEDEDE8));
    expect(p.onFillDim, const Color(0xFFA9A9A2));
    expect(p.mark, const Color(0xFFCBE642));
    expect(p.button, const Color(0xFFCBE642));

    final pa = AppStyle.paper.palette(Brightness.light);
    expect(pa.background, const Color(0xFFD8D8D4));
    expect(pa.surface, const Color(0xFFE6E6E2));
    expect(pa.border, const Color(0xFFB4B4AE));
    expect(pa.rule, const Color(0xFF0B0B0B));
    expect(pa.textPrimary, const Color(0xFF0B0B0B));
    expect(pa.textSecondary, const Color(0xFF45453F));
    expect(pa.textDim, const Color(0xFF5E5E59));
    expect(pa.fill, const Color(0xFF0B0B0B));
    expect(pa.onFill, const Color(0xFFF2F2EE));
    expect(pa.mark, const Color(0xFFCBE642));
    expect(pa.button, const Color(0xFF0B0B0B));

    final g = AppStyle.graphite.palette(Brightness.dark);
    expect(g.background, const Color(0xFF0E0F12));
    expect(g.surface, const Color(0xFF1C1D21));
    expect(g.border, const Color(0xFF2E3036));
    expect(g.rule, const Color(0xFFA9ADB6));
    expect(g.textPrimary, const Color(0xFFF2F3F4));
    expect(g.textSecondary, const Color(0xFFA9ADB6));
    expect(g.textDim, const Color(0xFF82868F));
    expect(g.fill, const Color(0xFF2A2C31));
    expect(g.onFill, const Color(0xFFF2F3F4));
    expect(g.mark, const Color(0xFFFDBA27));
    expect(g.fillBorder, const Color(0xFF3A3D44));
    expect(g.button, const Color(0xFFFDBA27));

    final b = AppStyle.black.palette(Brightness.dark);
    expect(b.background, const Color(0xFF000000));
    expect(b.surface, const Color(0xFF0B0B0B));
    expect(b.border, const Color(0xFF2A2A2A));
    expect(b.rule, const Color(0xFFB0B0B0));
    expect(b.textPrimary, const Color(0xFFFFFFFF));
    expect(b.textSecondary, const Color(0xFFB0B0B0));
    expect(b.textDim, const Color(0xFF797979));
    expect(b.fill, const Color(0xFF161616));
    expect(b.onFill, const Color(0xFFFFFFFF));
    expect(b.mark, const Color(0xFF3FD07A));
    expect(b.fillBorder, const Color(0xFF3A3A3A));
    expect(b.button, const Color(0xFFFFFFFF));

    final s = AppStyle.slate.palette(Brightness.dark);
    expect(s.background, const Color(0xFF1F262E));
    expect(s.surface, const Color(0xFF28323E));
    expect(s.border, const Color(0xFF3B4757));
    expect(s.rule, const Color(0xFFAAB6C4));
    expect(s.textPrimary, const Color(0xFFEAEFF4));
    expect(s.textSecondary, const Color(0xFFAAB6C4));
    expect(s.textDim, const Color(0xFF8F9AA7));
    expect(s.fill, const Color(0xFF2C3A47));
    expect(s.fillBorder, const Color(0xFF40505F));
    expect(s.onFill, const Color(0xFFEAEFF4));
    expect(s.onFillDim, const Color(0xFFAAB6C4));
    expect(s.mark, const Color(0xFF8DB8EA));
    expect(s.button, const Color(0xFF3775B7));
    expect(s.buttonMark, const Color(0xFFFFFFFF));
  });

  test('dark styles use dark fill roles', () {
    const expected = {
      'standard': (0xFF1A1D29, 0xFF2E3346, 0xFFF0F1F5, 0xFFB0B5C8, 0xFF7B97FF, 0xFF6B8AFF, 0xFF08090E, 0xFF08090E),
      'cyberpunk': (0xFF261447, 0xFF3D1E6D, 0xFFF5F0FF, 0xFFC9B8FF, 0xFF05D9E8, 0xFF05D9E8, 0xFF0D0221, 0xFF0D0221),
      'terminal': (0xFF0B1A0E, 0xFF1C4426, 0xFF4DFF7A, 0xFF2FD45E, 0xFF33FF66, 0xFF33FF66, 0xFF000000, 0xFF000000),
      'minimalDark': (0xFF1F1F1F, 0xFF3A3A3A, 0xFFEDEDED, 0xFFB5B5B5, 0xFFFFFFFF, 0xFFEDEDED, 0xFF0A0A0A, 0xFF0A0A0A),
    };
    for (final e in expected.entries) {
      final style = e.key == 'standard' ? AppStyle.standard : AppStyle.values.byName(e.key);
      final p = style.palette(Brightness.dark);
      final v = e.value;
      expect(
        [p.fill, p.fillBorder, p.onFill, p.onFillDim, p.mark, p.button, p.onButton, p.buttonMark],
        [for (final c in [v.$1, v.$2, v.$3, v.$4, v.$5, v.$6, v.$7, v.$8]) Color(c)],
        reason: e.key,
      );
    }
  });

  test('onFillDim reads on fill in every style', () {
    for (final (name, p) in _allPalettes()) {
      expect(AppTheme.contrast(p.onFillDim, p.fill), greaterThanOrEqualTo(4.5), reason: name);
    }
  });

  test('new styles have fixed brightness and listed order', () {
    expect(AppStyle.values.take(5), _newStyles);
    expect(AppStyle.paper.brightness, Brightness.light);
    for (final s in [AppStyle.paperDark, AppStyle.graphite, AppStyle.black, AppStyle.slate]) {
      expect(s.brightness, Brightness.dark, reason: s.name);
    }
  });

  test('text3 reaches 4.5 on page and sheet in new styles', () {
    for (final s in _newStyles) {
      final p = s.palette(s.brightness!);
      expect(AppTheme.contrast(p.textDim, p.background), greaterThanOrEqualTo(4.5), reason: s.name);
      expect(AppTheme.contrast(p.textDim, p.surface), greaterThanOrEqualTo(4.5), reason: s.name);
    }
  });

  test('mark and onFill read on fill in every style', () {
    for (final (name, p) in _allPalettes()) {
      expect(AppTheme.contrast(p.mark, p.fill), greaterThanOrEqualTo(4.5), reason: name);
      expect(AppTheme.contrast(p.onFill, p.fill), greaterThanOrEqualTo(4.5), reason: name);
      expect(AppTheme.contrast(p.onButton, p.button), greaterThanOrEqualTo(4.5), reason: name);
    }
  });

  test('accent reads on page in new styles', () {
    for (final s in _newStyles) {
      final p = s.palette(s.brightness!);
      expect(AppTheme.contrast(s.accent, p.background), greaterThanOrEqualTo(4.5), reason: s.name);
    }
  });

  test('light styles darken engine colors', () {
    const white = Color(0xFFFFFFFF);
    AppTheme.applyBrightness(Brightness.light);
    for (final e in Engine.values) {
      expect(AppTheme.contrast(e.color, white), greaterThanOrEqualTo(4.5), reason: e.name);
    }
  });
}
