// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/wardrive/wardrive_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get scanning => false;

  @override
  bool get radioListening => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Detection _drone(double lat, double lon) => Detection(
      id: 'd1',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:01',
      engine: Engine.skySpy,
      method: 'odid_ble',
      rssi: -60,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.now(),
      odid: OdidExtension(uavId: 'UAV1', droneLat: lat, droneLon: lon),
    );

Future<ProviderContainer> _pumpFollowing(WidgetTester tester, {bool running = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
  final first = _drone(10.0, 20.0);
  container.read(appStateProvider).recentDetections.add(first);
  final wd = container.read(wardriveProvider);
  if (running) wd.state = WardriveState.running;
  wd.requestFollowDrone(first);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.darkTheme, home: const WardriveScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  testWidgets('dragging the map releases the drone lock', (tester) async {
    await _pumpFollowing(tester);
    expect(find.byKey(const Key('follow-drone-chip')), findsOneWidget);
    await tester.drag(find.byType(FlutterMap), const Offset(60, 20));
    await tester.pump();
    expect(find.byKey(const Key('follow-drone-chip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the self-follow button releases the drone lock', (tester) async {
    await _pumpFollowing(tester, running: true);
    expect(find.byKey(const Key('follow-drone-chip')), findsOneWidget);
    await tester.tap(find.byTooltip('Center on me + follow'));
    await tester.pump();
    expect(find.byKey(const Key('follow-drone-chip')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the map locks on a followed drone, tracks its new position, and the chip releases it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    ]);
    final app = container.read(appStateProvider);
    final first = _drone(10.0, 20.0);
    app.recentDetections.add(first);
    container.read(wardriveProvider).requestFollowDrone(first);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const WardriveScreen()),
    ));
    await tester.pump();
    await tester.pump();
    final controller = tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    expect(find.byKey(const Key('follow-drone-chip')), findsOneWidget);
    expect(find.text('UAV1'), findsOneWidget);
    expect(controller.camera.center.latitude, closeTo(10.0, 1e-3));
    expect(controller.camera.center.longitude, closeTo(20.0, 1e-3));
    expect(controller.camera.zoom, greaterThanOrEqualTo(16));

    app.recentDetections
      ..clear()
      ..add(_drone(10.01, 20.01));
    app.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(controller.camera.center.latitude, closeTo(10.01, 1e-3));
    expect(controller.camera.center.longitude, closeTo(20.01, 1e-3));

    await tester.tap(find.byKey(const Key('follow-drone-close')));
    await tester.pump();
    expect(find.byKey(const Key('follow-drone-chip')), findsNothing);

    app.recentDetections
      ..clear()
      ..add(_drone(10.05, 20.05));
    app.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(controller.camera.center.latitude, closeTo(10.01, 1e-3));

    await tester.pumpWidget(const SizedBox());
  });
}
