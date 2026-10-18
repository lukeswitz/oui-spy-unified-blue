import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

void main() {
  test('light theme semantic colors reach 4.5:1 on white, dark keeps originals', () {
    const white = Color(0xFFFFFFFF);
    AppTheme.applyBrightness(Brightness.light);
    final light = [
      AppTheme.error, AppTheme.success, AppTheme.warning, AppTheme.detector,
      AppTheme.flockBle, AppTheme.flockWifi, AppTheme.foxhunter, AppTheme.skySpy,
      AppTheme.uniPwn, AppTheme.wardrive, AppTheme.wigle, AppTheme.wdgwars,
      AppTheme.wdgwarsAlt, AppTheme.gpsGood, AppTheme.gpsFair, AppTheme.gpsPoor,
      AppTheme.gpsNone,
    ];
    for (final c in light) {
      expect(AppTheme.contrast(c, white), greaterThanOrEqualTo(4.5));
    }
    for (final e in Engine.values) {
      expect(AppTheme.contrast(e.color, white), greaterThanOrEqualTo(4.5), reason: e.name);
    }
    for (final w in WardriveTarget.values) {
      expect(AppTheme.contrast(w.color, white), greaterThanOrEqualTo(4.5), reason: w.name);
    }
    AppTheme.applyBrightness(Brightness.dark);
    expect(AppTheme.success, const Color(0xFF5AE6A1));
    expect(AppTheme.warning, const Color(0xFFE6A85A));
  });
}
