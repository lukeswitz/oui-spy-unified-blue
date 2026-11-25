// Copyright (c) 2026 Luke Switzer
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/features/devices/devices_screen.dart';

ClassifiedDevice _ap(int i, String ssid, {int seen = 0}) => ClassifiedDevice(
      Observation(
        key: 'WIFI:02:00:00:00:00:0$i',
        kind: RadioKind.wifi,
        mac: '02:00:00:00:00:0$i',
        name: ssid,
        rssi: -40 - i,
        isAp: true,
        authMode: 3,
        channel: 6,
        lastSeenMs: seen,
      ),
      const [],
      {'esp32'},
    );

void main() {
  test('APs with the same SSID fold into one row', () {
    final a = _ap(1, 'MyNetwork');
    final b = _ap(2, 'MyNetwork');
    final c = _ap(3, 'OtherNet');
    final d = _ap(4, 'MyNetwork');
    final hidden1 = _ap(5, '');
    final hidden2 = _ap(6, '');
    final g = groupDevicesBySsid([a, b, c, d, hidden1, hidden2]);
    expect(g.rows, [a, c, hidden1, hidden2]);
    expect(g.members[a], [a, b, d]);
    expect(g.members.containsKey(c), isFalse);
    expect(g.repKeyOf, {b.obs.key: a.obs.key, d.obs.key: a.obs.key});
  });

  testWidgets('grouped row shows MAC count, details list last 5 and are selectable', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now().millisecondsSinceEpoch;
    final devs = [for (var i = 1; i <= 7; i++) _ap(i, 'MyNetwork', seen: now - i * 1000)];
    final g = groupDevicesBySsid(devs);
    final rep = g.rows.single;
    const guess = Guess('Wi-Fi access point', '', Confidence.low);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        deviceRegistryProvider.overrideWith((ref) => DeviceRegistry(vendorOf: (_) => null)),
      ],
      child: MaterialApp(
        home: Scaffold(body: DeviceRow(device: rep, guess: guess, members: g.members[rep]!)),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('7 MACs', findRichText: true), findsOneWidget);
    await tester.tap(find.byType(DeviceRow));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('7 MACS ON THIS NETWORK'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(find.textContaining('02:00:00:00:00:0$i ·'), findsOneWidget);
    }
    expect(find.textContaining('02:00:00:00:00:06 ·'), findsNothing);
    expect(find.textContaining('02:00:00:00:00:07 ·'), findsNothing);
  });
}
