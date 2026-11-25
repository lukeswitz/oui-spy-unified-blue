// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/wardrive/flock_panel.dart';
import 'package:oui_spy/theme/app_theme.dart';

Detection _det(
  String mac,
  Engine engine,
  String method, {
  String name = '',
  FlockExtension? flock,
  OdidExtension? odid,
  DetectorExtension? detector,
  double? lat = 40.0,
}) =>
    Detection(
      id: mac,
      sessionId: 's',
      nodeId: 'n',
      macAddress: mac,
      engine: engine,
      method: method,
      rssi: -70,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime(2026, 1, 1),
      deviceName: name,
      latitude: lat,
      longitude: lat == null ? null : -75.0,
      flock: flock,
      odid: odid,
      detector: detector,
    );

Future<void> _pumpPanel(WidgetTester tester, List<Detection> ds,
    {IconData icon = Icons.videocam,
    void Function(Detection)? onTap}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: FlockPanel(detections: ds, icon: icon, onDetectionTap: onTap),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('${ds.length}'));
  await tester.pump();
}

void main() {
  testWidgets('flock row shows a name, spelled-out type and confidence', (tester) async {
    await _pumpPanel(tester, [
      _det('aa:bb:cc:dd:ee:01', Engine.flockWifi, 'oui_addr2',
          flock: const FlockExtension(isRaven: true)),
    ]);
    expect(find.text('Flock Safety device'), findsOneWidget);
    expect(find.text('FLOCK WIFI'), findsOneWidget);
    expect(find.text('RAVEN'), findsOneWidget);
    expect(find.text('SUSPECTED'), findsOneWidget);
    expect(find.text('AA:BB:CC:DD:EE:01'), findsOneWidget);
    expect(find.text('-70'), findsOneWidget);
    expect(find.text('W'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(find.text('R'), findsNothing);
  });

  testWidgets('flock BLE row is labelled FLOCK BLE', (tester) async {
    await _pumpPanel(tester, [
      _det('aa:bb:cc:dd:ee:02', Engine.flockBle, 'name_match',
          name: 'FS-1234',
          flock: const FlockExtension(signals: FlockSignal.name)),
    ]);
    expect(find.text('FS-1234'), findsOneWidget);
    expect(find.text('FLOCK BLE'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
  });

  testWidgets('drone row shows UAS ID and DRONE, not W', (tester) async {
    await _pumpPanel(
        tester,
        [
          _det('02:00:00:00:06:02', Engine.skySpy, 'odid',
              odid: const OdidExtension(uavId: 'F1234567890')),
          _det('02:00:00:00:06:01', Engine.skySpy, 'odid'),
        ],
        icon: Icons.flight);
    expect(find.text('UAS F1234567890'), findsOneWidget);
    expect(find.text('Drone'), findsOneWidget);
    expect(find.text('DRONE'), findsNWidgets(2));
    expect(find.text('02:00:00:00:06:02'), findsOneWidget);
    expect(find.text('W'), findsNothing);
  });

  testWidgets('detector rows show description and method label', (tester) async {
    await _pumpPanel(
        tester,
        [
          _det('aa:bb:cc:dd:ee:03', Engine.detector, 'tracker',
              detector: const DetectorExtension(filterDescription: 'AirTag')),
          _det('aa:bb:cc:dd:ee:04', Engine.detector, 'flipper'),
        ],
        icon: Icons.radar);
    expect(find.text('AirTag'), findsOneWidget);
    expect(find.text('TRACKER'), findsOneWidget);
    expect(find.text('FLIPPER'), findsOneWidget);
    expect(find.text('AA:BB:CC:DD:EE:04'), findsNWidgets(2));
    expect(find.text('W'), findsNothing);
  });

  testWidgets('tap on a row with GPS fires onDetectionTap', (tester) async {
    Detection? tapped;
    await _pumpPanel(
        tester,
        [_det('aa:bb:cc:dd:ee:05', Engine.flockWifi, 'oui_addr2', flock: const FlockExtension())],
        onTap: (d) => tapped = d);
    await tester.tap(find.text('Flock Safety device'));
    expect(tapped?.macAddress, 'aa:bb:cc:dd:ee:05');
  });

  testWidgets('row text is at least 11 and title 13', (tester) async {
    await _pumpPanel(tester, [
      _det('aa:bb:cc:dd:ee:06', Engine.flockWifi, 'oui_addr2', flock: const FlockExtension()),
    ]);
    expect(tester.widget<Text>(find.text('Flock Safety device')).style!.fontSize, 13);
    expect(tester.widget<Text>(find.text('FLOCK WIFI')).style!.fontSize, 11);
    expect(tester.widget<Text>(find.text('AA:BB:CC:DD:EE:06')).style!.fontSize, 11);
  });
}
