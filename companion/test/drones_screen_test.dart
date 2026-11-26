// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:drift/native.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_log.dart';
import 'package:oui_spy/core/drone_tags.dart';
import 'package:oui_spy/features/drones/drone_page.dart';
import 'package:oui_spy/features/drones/drones_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

DroneReport _r(DateTime ts, String id, {int? status, int? height, double? lat, double? lon, double? hlat, double? hlon, double? plat, double? plon, bool fpv = false, int rssi = -60, String mac = '02:00:00:00:00:01'}) =>
    DroneReport(
      ts: ts,
      id: id,
      mac: mac,
      fpv: fpv,
      status: status,
      height: height,
      lat: lat,
      lon: lon,
      hereLat: hlat,
      hereLon: hlon,
      pilotLat: plat,
      pilotLon: plon,
      rssi: rssi,
    );

class _MemoryLog extends DroneLog {
  _MemoryLog(this.rows);
  final List<DroneReport> rows;

  @override
  Future<List<DroneReport>> query({DateTime? from, DateTime? to}) async => [
        for (final r in rows)
          if ((from == null || !r.ts.isBefore(from)) && (to == null || !r.ts.isAfter(to))) r,
      ];
}

Future<(ProviderContainer, DroneLog)> _setup(WidgetTester tester, List<DroneReport> seed) async {
  SharedPreferences.setMockInitialValues({});
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final log = _MemoryLog(seed);
  final container = ProviderContainer(overrides: [
    droneLogProvider.overrideWithValue(log),
    databaseProvider.overrideWithValue(db),
  ]);
  addTearDown(container.dispose);
  return (container, log);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the Drones list shows the counts and filters by time window', (tester) async {
    final now = DateTime.now();
    final (container, log) = await _setup(tester, [
      _r(now.subtract(const Duration(seconds: 10)), 'SERIALNEW', status: 2, height: 90, lat: 10.0, lon: 20.0, plat: 10.0, plon: 20.0),
      _r(now.subtract(const Duration(hours: 3)), 'SERIALMID', height: 20),
      _r(now.subtract(const Duration(hours: 30)), 'SERIALOLD', height: 150),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronesScreen()),
    ));
    await _settle(tester);

    expect(find.byKey(const Key('drone-card-SERIALNEW')), findsOneWidget);
    expect(find.byKey(const Key('drone-card-SERIALMID')), findsOneWidget);
    expect(find.byKey(const Key('drone-card-SERIALOLD')), findsNothing);
    expect(find.textContaining('In the air now'), findsOneWidget);
    final strip = find.byKey(const Key('drone-counts'));
    expect(find.descendant(of: strip, matching: find.text('Live')), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('90m')), findsOneWidget);

    await tester.tap(find.byKey(const Key('drone-window-h1')));
    await _settle(tester);
    expect(find.byKey(const Key('drone-card-SERIALNEW')), findsOneWidget);
    expect(find.byKey(const Key('drone-card-SERIALMID')), findsNothing);

    await tester.tap(find.byKey(const Key('drone-window-all')));
    await _settle(tester);
    expect(find.byKey(const Key('drone-card-SERIALOLD')), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('150m')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());

  });

  testWidgets('the Drones list filters Remote ID and FPV and shows FPV with channel and LVL', (tester) async {
    final now = DateTime.now();
    final (container, log) = await _setup(tester, [
      _r(now.subtract(const Duration(seconds: 10)), 'SERIALRID', status: 2, height: 90, lat: 10.0, lon: 20.0, plat: 10.0, plon: 20.0),
      _r(now.subtract(const Duration(seconds: 12)), 'FPV A1 5865', fpv: true, rssi: -68, mac: '02:46:50:56:16:E9'),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronesScreen()),
    ));
    await _settle(tester);

    expect(find.byKey(const Key('drone-card-SERIALRID')), findsOneWidget);
    expect(find.byKey(const Key('drone-card-FPV A1 5865')), findsOneWidget);
    final strip = find.byKey(const Key('drone-counts'));
    expect(find.descendant(of: strip, matching: find.text('2')), findsNWidgets(2));
    expect(find.descendant(of: strip, matching: find.text('1')), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('drone-source-fpv')));
    await _settle(tester);
    final card = find.byKey(const Key('drone-card-FPV A1 5865'));
    expect(find.byKey(const Key('drone-card-SERIALRID')), findsNothing);
    expect(find.descendant(of: card, matching: find.text('A1 · 5865 MHz')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('LVL ')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('120')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('dBm')), findsNothing);
    expect(find.descendant(of: card, matching: find.textContaining('Pilot')), findsNothing);
    expect(find.descendant(of: strip, matching: find.text('0')), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('drone-source-rid')));
    await _settle(tester);
    expect(find.byKey(const Key('drone-card-SERIALRID')), findsOneWidget);
    expect(find.byKey(const Key('drone-card-FPV A1 5865')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('drone-card-SERIALRID')), matching: find.text('-60 dBm')), findsOneWidget);

    await tester.tap(find.byKey(const Key('drone-source-all')));
    await _settle(tester);
    expect(find.byKey(const Key('drone-card-FPV A1 5865')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a drone card shows the saved name with the id as its subtitle', (tester) async {
    final now = DateTime.now();
    final (container, log) = await _setup(tester, [
      _r(now.subtract(const Duration(seconds: 10)), 'SERIALNAMED', height: 5),
      _r(now.subtract(const Duration(seconds: 20)), 'SERIALPLAIN', height: 5, mac: '02:00:00:00:00:02'),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronesScreen()),
    ));
    await _settle(tester);
    final named = find.byKey(const Key('drone-card-SERIALNAMED'));
    expect(find.descendant(of: named, matching: find.text('SERIALNAMED')), findsOneWidget);

    await container
        .read(deviceNotesProvider.notifier)
        .set('02:00:00:00:00:01', const DeviceNote(name: 'Yard drone'));
    await tester.pump();
    expect(find.descendant(of: named, matching: find.text('Yard drone')), findsOneWidget);
    expect(find.descendant(of: named, matching: find.text('SERIALNAMED')), findsNothing);
    expect(find.descendant(of: named, matching: find.textContaining('SERIALNAMED · ')), findsOneWidget);
    final plain = find.byKey(const Key('drone-card-SERIALPLAIN'));
    expect(find.descendant(of: plain, matching: find.text('SERIALPLAIN')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the drone page of an FPV transmitter has no FAA record and shows LVL', (tester) async {
    final t = DateTime.now().subtract(const Duration(minutes: 1));
    final (container, log) = await _setup(tester, [
      _r(t, 'FPV A1 5865', fpv: true, rssi: -68, mac: '02:46:50:56:16:E9'),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronePage(id: 'FPV A1 5865')),
    ));
    await _settle(tester);
    expect(find.text('FAA record'), findsNothing);
    expect(find.byKey(const Key('drone-faa-lookup')), findsNothing);
    expect(find.text('LVL'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Channel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the drone page saves a name, group and notes by MAC and shows the name as its title', (tester) async {
    final t = DateTime.now().subtract(const Duration(minutes: 1));
    final (container, log) = await _setup(tester, [_r(t, 'SERIALNOTE', height: 5)]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronePage(id: 'SERIALNOTE')),
    ));
    await _settle(tester);
    expect(find.text('SERIALNOTE'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('drone-notes')));
    await tester.tap(find.byKey(const Key('drone-notes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Name & notes'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Yard drone');
    await tester.enterText(find.byType(TextField).at(2), 'seen twice');
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final note = container.read(deviceNotesProvider)['02:00:00:00:00:01'];
    expect(note?.name, 'Yard drone');
    expect(note?.notes, 'seen twice');
    expect(find.text('Yard drone'), findsOneWidget);
    expect(find.textContaining('SERIALNOTE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the drone page shows the detection location with its range and saves a tag shown in the list', (tester) async {
    final t = DateTime.now().subtract(const Duration(minutes: 1));
    final (container, log) = await _setup(tester, [
      _r(t, 'SERIALPAGE', status: 2, height: 50, lat: 10.0, lon: 20.0, hlat: 10.0, hlon: 20.001, plat: 10.0, plon: 19.999),
      _r(t.add(const Duration(seconds: 10)), 'SERIALPAGE', status: 2, height: 60, lat: 10.001, lon: 20.0, hlat: 10.0, hlon: 20.001, plat: 10.0, plon: 19.999),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronePage(id: 'SERIALPAGE')),
    ));
    await _settle(tester);

    expect(find.byKey(const Key('drone-flight-map')), findsOneWidget);
    expect(find.byKey(const Key('detection-location-pin')), findsOneWidget);
    expect(find.byKey(const Key('detection-range-label')), findsOneWidget);
    expect(find.byKey(const Key('drone-detection-range')), findsOneWidget);
    expect(find.text('Past flights'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('drone-tag-suspicious')));
    await tester.tap(find.byKey(const Key('drone-tag-suspicious')));
    await tester.pump();
    expect(container.read(droneTagsProvider)['SERIALPAGE'], DroneTag.suspicious);

    await tester.ensureVisible(find.byKey(const Key('drone-follow')));
    final follow = tester.widget<OutlinedButton>(find.byKey(const Key('drone-follow')));
    expect(follow.onPressed, isNull);
    expect(find.textContaining('Needs a live position'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DronesScreen()),
    ));
    await _settle(tester);
    expect(find.text('Suspicious'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

  });
}
