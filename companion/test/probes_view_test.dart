// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/probes/probe_store.dart';
import 'package:oui_spy/features/pcap/probes_view.dart';

void main() {
  late Directory dir;
  late ProbeStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('probes_view');
    store = ProbeStore(file: () async => File('${dir.path}/probes.json'));
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        overrides: [probeStoreProvider.overrideWith((ref) => store)],
        child: const MaterialApp(home: Scaffold(body: ProbesView())),
      ));

  testWidgets('empty database says so', (tester) async {
    await pump(tester);
    expect(find.textContaining('No device heard asking yet'), findsOneWidget);
    expect(find.text('0 OF 0 DEVICES'), findsOneWidget);
  });

  testWidgets('lists devices, names and networks', (tester) async {
    store.add(mac: '00:11:22:33:44:01', ssid: 'MyNetwork', rssi: -55, channel: 6);
    store.add(mac: '00:11:22:33:44:01', ssid: 'MyNetwork');
    store.add(mac: '00:11:22:33:44:02');
    await pump(tester);
    expect(find.text('00:11:22:33:44:01'), findsOneWidget);
    expect(find.text('MyNetwork  x2'), findsOneWidget);
    expect(find.text('Asks for any network, never one by name'), findsOneWidget);
    expect(find.text('2 OF 2 DEVICES'), findsOneWidget);

    await tester.tap(find.text('NAMED'));
    await tester.pump();
    expect(find.text('1 OF 1 DEVICES'), findsOneWidget);

    await tester.tap(find.text('NETWORKS'));
    await tester.pump();
    expect(find.text('1 OF 1 NETWORKS'), findsOneWidget);
    expect(find.text('ONLY ONE DEVICE ASKS FOR IT'), findsOneWidget);
  });

  testWidgets('tapping a name explores that network', (tester) async {
    store.add(mac: '00:11:22:33:44:01', ssid: 'MyNetwork');
    await pump(tester);
    await tester.tap(find.text('MyNetwork'));
    await tester.pump();
    expect(find.text('1 OF 1 NETWORKS'), findsOneWidget);
  });

  testWidgets('clear asks first', (tester) async {
    store.add(mac: '00:11:22:33:44:01', ssid: 'MyNetwork');
    await pump(tester);
    await tester.tap(find.text('CLEAR'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the probe database?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(store.deviceCount, 1);
    await tester.tap(find.text('CLEAR'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'CLEAR').last);
      await tester.pump();
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.deviceCount, 0);
  });
}
