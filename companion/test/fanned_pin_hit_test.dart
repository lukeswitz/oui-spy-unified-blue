// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/features/wardrive/drone_markers.dart';

void main() {
  testWidgets('a pin head under a later pin box still gets the tap', (tester) async {
    var under = 0;
    var over = 0;
    Widget pin(VoidCallback onTap, Key key) => FannedPin(
          geo: const FanGeometry(0, 20),
          lineColor: Colors.blue,
          headExtent: 25,
          head: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const SizedBox(width: 30, height: 30),
          ),
        );
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [
          Positioned(left: 100, top: 100, child: pin(() => under++, const Key('under'))),
          Positioned(left: 130, top: 100, child: pin(() => over++, const Key('over'))),
        ],
      ),
    ));
    await tester.tap(find.byKey(const Key('under')));
    expect(under, 1);
    expect(over, 0);
    await tester.tap(find.byKey(const Key('over')));
    expect(over, 1);
  });
}
