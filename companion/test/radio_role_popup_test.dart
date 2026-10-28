import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/core/ble/ble_manager.dart';
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

  testWidgets('hub board shows nodes with switches; switched-off node is skipped', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const n1 = EnowHubNode(mac: '02:00:00:00:10:01', rssi: -50, paired: true, online: true, encrypted: false, records: 5, name: '');
    const n2 = EnowHubNode(mac: '02:00:00:00:10:02', rssi: -60, paired: true, online: true, encrypted: false, records: 0, name: 'Piglet:v2.65');
    ({Map<String, int> roles, Set<String> skip})? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<({Map<String, int> roles, Set<String> skip})>(
                context: context,
                builder: (_) => RadioRolePopup(
                  nodes: const ['HUB1', 'PHONE'],
                  labelFor: (id) => id,
                  initial: const {'HUB1': 0x03, 'PHONE': 0x03},
                  hubId: 'HUB1',
                  hubNodes: const [n1, n2],
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('HUB · 2 nodes'), findsOneWidget);
    expect(find.text('Piglet v2.65'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();
    expect(result?.skip, {n1.mac});
  });
}
