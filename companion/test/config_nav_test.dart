// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/widgets/command_bar.dart';

void expectNotTruncated(WidgetTester tester, String label) {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) return;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final natural = paragraph.getMaxIntrinsicWidth(double.infinity);
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(natural - 0.5),
    reason: '"$label" is clipped: '
        '${paragraph.size.width} < $natural',
  );
}

void _noop() {}

void main() {
  const sizes = <String, Size>{
    'iphone-se': Size(320, 568),
    'iphone-13': Size(390, 844),
    'iphone-max': Size(430, 932),
    'ipad': Size(834, 1194),
  };

  testWidgets('CommandBar without a leading button fits and keeps labels',
      (tester) async {
    for (final entry in sizes.entries) {
      for (final scale in <double>[1.0, 1.3, 2.0]) {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
            size: entry.value,
            textScaler: TextScaler.linear(scale),
          ),
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  CommandBar(actions: [
                    CommandBarAction(
                        icon: Icons.filter_alt,
                        label: 'FILTER',
                        onTap: _noop),
                    CommandBarAction(
                        icon: Icons.arrow_downward,
                        label: 'TIME',
                        onTap: _noop),
                    CommandBarAction(
                        icon: Icons.more_horiz, label: 'MORE', onTap: _noop),
                  ]),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: '${entry.key} @ ${scale}x');
        for (final label in ['FILTER', 'TIME', 'MORE']) {
          if (scale == 1.0) {
            expect(find.text(label), findsOneWidget,
                reason: '$label missing at ${entry.key} @ ${scale}x');
          }
          expectNotTruncated(tester, label);
        }
      }
    }
  });
}
