import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/features/wardrive/session_launch.dart';

void main() {
  testWidgets('radio dialog with many nodes scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nodes = ['AAAA', 'BBBB', 'CCCC', 'DDDD', 'EEEE', 'PHONE'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RadioRolePopup(
          nodes: nodes,
          labelFor: (id) => 'OUISPY-$id',
          initial: {for (final n in nodes) n: 0x03},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('START'), findsOneWidget);
  });
}
