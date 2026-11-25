// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/drone_log.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/smoke_hook.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> _frame(double lat, double lon) => smokeFrame(
      Engine.skySpy,
      '02:00:00:00:06:00',
      -60,
      6,
      0,
      smokeOdidExt(
        uavId: 'SERIAL1',
        opId: 'OP1',
        lat: lat,
        lon: lon,
        pilotLat: 10.0,
        pilotLon: 20.0,
        alt: 100,
        agl: 50,
        speed: 5,
        heading: 90,
        selfId: 'test',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app keeps where this phone was when a flight was first heard and logs each report', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = Directory.systemTemp.createTempSync('dronehome');
    addTearDown(() => dir.deleteSync(recursive: true));
    final log = DroneLog(dir: () async => dir, flushDelay: const Duration(hours: 1));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      droneLogProvider.overrideWithValue(log),
    ]);
    addTearDown(container.dispose);
    final ble = container.read(bleManagerProvider);
    final app = container.read(appStateProvider);

    ble.updateGps(latitude: 10.0, longitude: 20.0, altitude: 0, accuracy: 4);
    ble.injectDetectionFrame(_frame(10.01, 20.01));
    await Future<void>.delayed(Duration.zero);
    ble.updateGps(latitude: 10.5, longitude: 20.5, altitude: 0, accuracy: 4);
    ble.injectDetectionFrame(_frame(10.02, 20.02));
    await Future<void>.delayed(Duration.zero);

    final home = app.droneHome('SERIAL1')!;
    expect(home.latitude, 10.0);
    expect(home.longitude, 20.0);
    final rows = await log.query();
    expect(rows.length, 1);
    expect(rows.single.id, 'SERIAL1');
    expect(rows.single.hereLat, 10.0);
    expect(rows.single.height, 50);
    app.resetCounts();
    expect(app.droneHome('SERIAL1'), isNull);
    log.dispose();
  });
}
