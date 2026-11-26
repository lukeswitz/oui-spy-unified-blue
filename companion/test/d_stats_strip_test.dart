// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_stats_strip.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<(String, String)> items, {double width = 360}) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: DStatsStrip(items: items)),
      ),
    ));
  }

  testWidgets('long labels wrap to a second row instead of being cut off', (tester) async {
    const labels = ['Live', 'Airborne', 'Pilots', 'Top height', 'In window'];
    await pump(tester, [for (final l in labels) ('0', l)]);
    for (final l in labels) {
      final p = tester.renderObject<RenderParagraph>(find.text(l));
      expect(p.didExceedMaxLines, isFalse, reason: l);
    }
    expect(tester.getTopLeft(find.text('In window')).dy, greaterThan(tester.getTopLeft(find.text('Live')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no label is cut off at any phone width', (tester) async {
    const labels = ['Detections', 'Change vs before', 'Unique devices', 'First seen', 'Active nodes', 'Peak per 1 h'];
    for (var w = 300.0; w <= 480; w += 2) {
      await pump(tester, [for (final l in labels) ('0', l)], width: w);
      for (final l in labels) {
        final p = tester.renderObject<RenderParagraph>(find.text(l));
        expect(p.didExceedMaxLines, isFalse, reason: '$l at width $w');
      }
    }
  });

  testWidgets('labels that fit stay on one row', (tester) async {
    const labels = ['Unique', 'Engines', 'Per min', 'Nodes'];
    await pump(tester, [for (final l in labels) ('0', l)], width: 600);
    final y = tester.getTopLeft(find.text('Unique')).dy;
    for (final l in labels) {
      expect(tester.getTopLeft(find.text(l)).dy, y, reason: l);
    }
  });
}
