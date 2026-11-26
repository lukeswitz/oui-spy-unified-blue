// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/fleet_metrics_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get radioListening => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const FleetMetricsScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  testWidgets('an empty log says there are no metrics, the mesh counters still show', (tester) async {
    await pump(tester);
    expect(find.text('FLEET METRICS'), findsOneWidget);
    expect(find.text('TX / RX'), findsOneWidget);
    expect(find.textContaining('No metrics'), findsOneWidget);
  });

  testWidgets('logged detections fill the panels', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await db.insertDetectionRow(DetectionsCompanion(
          sessionId: const drift.Value('s1'),
          nodeId: const drift.Value('default'),
          macAddress: drift.Value('02:00:00:00:00:0$i'),
          engine: const drift.Value('detector'),
          detectionMethod: const drift.Value('ble_adv'),
          rssi: const drift.Value(-60),
          channel: const drift.Value(0),
          deviceTimestampMs: drift.Value(now),
          appTimestamp: drift.Value(now - i * 60000),
        ));
      }
    });
    await pump(tester);
    expect(find.text('DETECTIONS'), findsAtLeastNWidgets(1));
    expect(find.text('OVER TIME'), findsOneWidget);
    expect(find.text('BY TYPE'), findsOneWidget);
    expect(find.text('SIGNAL'), findsOneWidget);
    expect(find.text('3'), findsAtLeastNWidgets(1));
    expect(find.text('NEW'), findsOneWidget);
  });

  Future<void> insert(String mac, int at, {String engine = 'wardrive', String method = 'wifi_ap', int channel = 6, int auth = 3, String? uav, int? alt, int? spd}) =>
      db.insertDetectionRow(DetectionsCompanion(
        sessionId: const drift.Value('s1'),
        nodeId: const drift.Value('default'),
        macAddress: drift.Value(mac),
        engine: drift.Value(engine),
        detectionMethod: drift.Value(method),
        rssi: const drift.Value(-60),
        channel: drift.Value(channel),
        deviceTimestampMs: drift.Value(at),
        appTimestamp: drift.Value(at),
        authMode: drift.Value(auth),
        uavId: drift.Value(uav),
        altitudeMsl: drift.Value(alt),
        droneSpeed: drift.Value(spd),
      ));

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets('wardrive mode shows discovered over time, security, channels and makers', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.runAsync(() async {
      await insert('02:00:00:00:01:01', now - 60000);
      await insert('02:00:00:00:01:02', now - 120000, channel: 36, auth: 0);
      await insert('02:00:00:00:01:03', now - 180000, engine: 'detector', method: 'ble_adv', channel: 0, auth: 0);
    });
    await pump(tester);
    await choose(tester, 'Wardrive');
    expect(find.text('DEVICES'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.textContaining('DISCOVERED OVER TIME'), findsOneWidget);
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('WPA2'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('CHANNELS'), findsOneWidget);
    expect(find.text('Ch 36'), findsOneWidget);
    expect(find.text('MAKERS'), findsOneWidget);
    expect(find.text('OVER TIME'), findsNothing);
  });

  testWidgets('drones mode lists each drone with its tag and peaks, and says so when there are none', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await pump(tester);
    await choose(tester, 'Drones');
    expect(find.textContaining('No metrics'), findsOneWidget);
    await tester.runAsync(() async {
      await insert('02:00:00:00:02:01', now - 5000, engine: 'skySpy', method: 'wifi_beacon', uav: 'DRONE-A', alt: 80, spd: 6);
      await insert('02:00:00:00:02:01', now - 90000, engine: 'skySpy', method: 'wifi_beacon', uav: 'DRONE-A', alt: 95, spd: 3);
      await insert('02:00:00:00:02:02', now - 600000, engine: 'detector', method: 'ble_adv', channel: 0, auth: 0);
    });
    await choose(tester, 'Detections');
    await choose(tester, 'Drones');
    expect(find.text('REPORTS'), findsOneWidget);
    expect(find.text('LIVE'), findsAtLeastNWidgets(1));
    expect(find.text('95 m'), findsOneWidget);
    expect(find.text('6 m/s'), findsOneWidget);
    expect(find.text('DRONE-A'), findsOneWidget);
    expect(find.textContaining('2 reports'), findsOneWidget);
  });

  testWidgets('drones mode with logged detections but no Remote ID reports says no drones', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.runAsync(() => insert('02:00:00:00:03:01', now - 5000, engine: 'detector', method: 'ble_adv', channel: 0, auth: 0));
    await pump(tester);
    await choose(tester, 'Drones');
    expect(find.textContaining('No drones'), findsOneWidget);
  });
}
