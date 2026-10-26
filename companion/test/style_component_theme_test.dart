import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/theme/app_theme.dart';

const _cases = [
  (AppStyle.paperDark, Brightness.dark),
  (AppStyle.paper, Brightness.light),
];

RoundedRectangleBorder _round(double r) =>
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(r)));

final _control = _round(AppRadius.control);

void main() {
  for (final (style, brightness) in _cases) {
    group('${style.name} ${brightness.name}', () {
      final t = AppTheme.themeFor(style, brightness);
      final p = style.palette(brightness);

      test('elevated button', () {
        final s = t.elevatedButtonTheme.style!;
        expect(s.backgroundColor!.resolve({}), p.button);
        expect(s.foregroundColor!.resolve({}), p.onButton);
        expect(s.shape!.resolve({}), _control);
        expect(s.minimumSize!.resolve({})!.height, 52);
      });

      test('outlined button', () {
        final s = t.outlinedButtonTheme.style!;
        final side = s.side!.resolve({})!;
        expect(side.color, p.textPrimary);
        expect(side.width, 1);
        expect(s.shape!.resolve({}), _control);
      });

      test('switch', () {
        expect(t.switchTheme.thumbColor!.resolve({WidgetState.selected}), p.mark);
        final track = t.switchTheme.trackColor!.resolve({WidgetState.selected});
        expect(track, p.mark.withValues(alpha: 0.35));
        expect(track, isNot(p.fill));
        expect(t.switchTheme.trackOutlineColor!.resolve({WidgetState.selected}), p.mark);
      });

      test('card', () {
        expect(t.cardTheme.shape,
            const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)), side: BorderSide.none));
        expect(t.cardTheme.elevation, 0);
      });

      test('bottom nav', () {
        expect(t.bottomNavigationBarTheme.selectedItemColor, p.textPrimary);
        expect(t.bottomNavigationBarTheme.unselectedItemColor, p.textDim);
      });

      test('tab bar', () {
        final ind = t.tabBarTheme.indicator as UnderlineTabIndicator;
        expect(ind.borderSide.color, p.textPrimary);
        expect(ind.borderSide.width, 1.5);
      });

      test('bottom sheet', () {
        expect(t.bottomSheetTheme.backgroundColor, p.surface);
        expect(t.bottomSheetTheme.shape,
            const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))));
      });

      test('dialog and input', () {
        final ds = t.dialogTheme.shape as RoundedRectangleBorder;
        expect(ds.borderRadius, BorderRadius.circular(16));
        expect(ds.side, BorderSide.none);
        for (final b in [
          t.inputDecorationTheme.border,
          t.inputDecorationTheme.enabledBorder,
          t.inputDecorationTheme.focusedBorder,
        ]) {
          expect((b as OutlineInputBorder).borderRadius, BorderRadius.circular(AppRadius.control));
        }
      });

      test('chip', () {
        expect(t.chipTheme.side, BorderSide(color: p.border));
        expect((t.chipTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppRadius.chip));
        expect(t.chipTheme.selectedColor, p.fill);
      });

      test('segmented button', () {
        final s = t.segmentedButtonTheme.style!;
        const sel = {WidgetState.selected};
        expect(s.shape!.resolve({}), _control);
        expect(s.backgroundColor!.resolve(sel), p.textPrimary);
        expect(s.foregroundColor!.resolve(sel), p.background);
        expect(s.backgroundColor!.resolve({}), p.surfaceLight);
        expect(s.foregroundColor!.resolve({}), p.textSecondary);
        expect(s.side!.resolve({}), BorderSide.none);
        expect(s.side!.resolve(sel), BorderSide.none);
      });

      test('type ramp', () {
        final tt = t.textTheme;
        expect(tt.displaySmall!.fontSize, 34);
        expect(tt.displaySmall!.fontWeight, FontWeight.w500);
        expect(tt.displaySmall!.letterSpacing, closeTo(-1.02, 1e-9));
        expect(tt.labelSmall!.fontSize, 11);
        expect(tt.labelSmall!.letterSpacing, closeTo(1.1, 1e-9));
        expect(tt.titleMedium!.fontSize, 17);
        expect(tt.bodyMedium!.fontSize, 14);
        expect(tt.labelLarge!.fontSize, 15);
        expect(tt.labelLarge!.fontWeight, FontWeight.w500);
      });
    });
  }
}
