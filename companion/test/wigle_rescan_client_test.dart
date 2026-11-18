import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> det(String mac, String method) => db.insertDetection(DetectionsCompanion(
        sessionId: const drift.Value('s1'),
        nodeId: const drift.Value('default'),
        macAddress: drift.Value(mac),
        engine: const drift.Value('wardrive'),
        detectionMethod: drift.Value(method),
        rssi: const drift.Value(-60),
        channel: const drift.Value(6),
        deviceTimestampMs: const drift.Value(1000),
        appTimestamp: const drift.Value(1000),
      ));

  Future<Map<String, String>> methods() async => {
        for (final r in await db.getDetectionsForSession('s1')) r.macAddress: r.detectionMethod,
      };

  test('session rescan keeps WiFi client rows as clients', () async {
    await det('0a:bb:cc:dd:ee:01', 'wifi_ap');
    await det('0a:bb:cc:dd:ee:09', 'wifi_client');
    await det('0a:bb:cc:dd:ee:0a', 'ble_adv');
    await WigleCsvRescan.rescanSession(db, 's1');
    expect(await methods(), {
      '0a:bb:cc:dd:ee:01': 'wifi_ap',
      '0a:bb:cc:dd:ee:09': 'wifi_client',
      '0a:bb:cc:dd:ee:0a': 'ble_adv',
    });
  });

  test('full rescan keeps WiFi client rows as clients', () async {
    await db.into(db.sessions).insert(const Session(
          id: 's1',
          name: 'Drive',
          nodeId: 'default',
          startedAt: 0,
          endedAt: 2000,
          enginesActive: 0,
          detectionCount: 0,
          uniqueMacCount: 0,
          distanceKm: 0,
          exported: false,
          isWardrive: true,
        ));
    await det('0a:bb:cc:dd:ee:09', 'wifi_client');
    await WigleCsvRescan.rescanAll(db);
    expect((await methods())['0a:bb:cc:dd:ee:09'], 'wifi_client');
  });
}
