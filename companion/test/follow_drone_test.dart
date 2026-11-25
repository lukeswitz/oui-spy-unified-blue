// Copyright (c) 2026 Luke Switzer
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
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
  String get name => 'test';

  @override
  Stream<Observation> get observations => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Detection _drone({OdidExtension? odid, Engine engine = Engine.skySpy}) => Detection(
      id: 'd1',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:01',
      engine: engine,
      method: 'odid_ble',
      rssi: -60,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.now(),
      odid: odid,
    );

Future<ProviderContainer> _open(WidgetTester tester, Detection d) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showDetectionDetails(context, ref, d),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/wardrive', builder: (_, _) => const Scaffold(body: Text('map tab'))),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _release(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.read(deviceRegistryProvider).dispose();
}

void main() {
  testWidgets('a drone with a Remote ID position offers Follow on map, which asks the map to lock on it',
      (tester) async {
    final d = _drone(odid: const OdidExtension(uavId: 'UAV1', droneLat: 10.0, droneLon: 20.0));
    final container = await _open(tester, d);
    expect(find.text('Follow on map'), findsOneWidget);
    await tester.ensureVisible(find.text('Follow on map'));
    await tester.tap(find.text('Follow on map'));
    await tester.pumpAndSettle();
    expect(find.text('map tab'), findsOneWidget);
    expect(container.read(wardriveProvider).pendingFollowDrone, d);
    expect(container.read(wardriveProvider).consumeFollowDrone(), d);
    expect(container.read(wardriveProvider).pendingFollowDrone, isNull);
    await _release(tester, container);
  });

  testWidgets('a drone without a position has no Follow on map', (tester) async {
    final container = await _open(tester, _drone(odid: const OdidExtension(uavId: 'UAV1')));
    expect(find.text('Follow on map'), findsNothing);
    await _release(tester, container);
  });

  testWidgets('a device that is not a drone has no Follow on map', (tester) async {
    final container = await _open(
        tester, _drone(engine: Engine.flockBle, odid: const OdidExtension(droneLat: 10.0, droneLon: 20.0)));
    expect(find.text('Follow on map'), findsNothing);
    await _release(tester, container);
  });
}
