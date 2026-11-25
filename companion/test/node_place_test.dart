// Copyright (c) 2026 Luke Switzer
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/node_positions.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/node_rename_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGps extends GpsProvider {
  _FakeGps(super.ble, super.geofence);

  GpsPosition? fix;

  @override
  GpsPosition? recentPosition([Duration maxAge = const Duration(minutes: 3)]) => fix;
}

void main() {
  testWidgets('Place at my position needs a recent fix, then saves it; Clear position removes it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    late _FakeGps gps;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      gpsProvider.overrideWith((ref) {
        gps = _FakeGps(ref.watch(bleManagerProvider), ref.read(geofenceFilterProvider));
        ref.onDispose(gps.dispose);
        return gps;
      }),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showNodeRenameDialog(context, ref.read(appStateProvider), 'AAAA', ref: ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Position: not placed'), findsOneWidget);
    expect(find.text('Clear position'), findsNothing);

    await tester.tap(find.text('Place at my position'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No recent GPS fix'), findsOneWidget);
    expect(container.read(nodePositionsProvider), isEmpty);

    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
    gps.fix = GpsPosition(
      latitude: 10.0,
      longitude: 20.0,
      altitude: 0,
      speed: 0,
      heading: 0,
      accuracy: 6,
      satelliteCount: 8,
      timestamp: DateTime.now(),
    );
    await tester.tap(find.text('Place at my position'));
    await tester.pumpAndSettle();
    expect(container.read(nodePositionsProvider)['AAAA'], const LatLng(10.0, 20.0));
    expect(find.text('Position: 10.00000, 20.00000'), findsOneWidget);
    expect(find.textContaining('±6 m'), findsOneWidget);

    await tester.tap(find.text('Clear position'));
    await tester.pumpAndSettle();
    expect(container.read(nodePositionsProvider), isEmpty);
    expect(find.text('Position: not placed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without a ref the dialog has no position controls', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showNodeRenameDialog(context, ref.read(appStateProvider), 'AAAA'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Place at my position'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
