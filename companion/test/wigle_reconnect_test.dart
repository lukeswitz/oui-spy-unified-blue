import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/models/detection.dart';

class MockBle extends Mock implements BleManager {}
class MockGps extends Mock implements GpsProvider {}
class MockDb extends Mock implements AppDatabase {}
class MockIgnore extends Mock implements IgnoreListState {}
class MockGeo extends Mock implements GeofenceFilter {}
class MockNotif extends Mock implements NotificationService {}
class MockLive extends Mock implements LiveActivityService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(const SessionsCompanion()));

  test('wigle deselects on reconnect when the wardrive engine is running', () async {
    SharedPreferences.setMockInitialValues({});

    final ble = MockBle();
    final conn = StreamController<NodeConnectionState>.broadcast();
    when(() => ble.connectionState).thenAnswer((_) => conn.stream);
    when(() => ble.detections)
        .thenAnswer((_) => const Stream<Detection>.empty());
    when(() => ble.importedDetections)
        .thenAnswer((_) => const Stream<Detection>.empty());
    when(() => ble.awayLiveDetections)
        .thenAnswer((_) => const Stream<Detection>.empty());
    when(() => ble.spoolImport)
        .thenAnswer((_) => const Stream<SpoolImportProgress>.empty());
    when(() => ble.isManagerConnected).thenReturn(false);
    when(() => ble.readCommandedEngineMask()).thenAnswer((_) async => 0x40);

    final gps = MockGps();
    when(() => gps.positionStream)
        .thenAnswer((_) => const Stream<GpsPosition>.empty());
    when(() => gps.start()).thenAnswer((_) async => true);
    when(() => gps.lastPosition).thenReturn(null);

    final db = MockDb();
    when(() => db.getWardriveSessions()).thenAnswer((_) async => <Session>[]);
    when(() => db.insertSession(any())).thenAnswer((_) async => 0);

    late WardriveController wd;
    await runZonedGuarded(() async {
      wd = WardriveController(
          ble, gps, db, MockIgnore(), MockGeo(), MockNotif(), MockLive());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      wd.selectedTargets
        ..clear()
        ..add(WardriveTarget.wigle);
      expect(wd.selectedTargets.contains(WardriveTarget.wigle), isTrue,
          reason: 'precondition: wigle selected before reconnect');
      conn.add(NodeConnectionState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, (e, s) {/* swallow Wakelock/LiveActivity plugin errors from logging setup */});

    expect(wd.selectedTargets.contains(WardriveTarget.wigle), isFalse,
        reason: 'wigle must be deselected on reconnect');
  });
}
