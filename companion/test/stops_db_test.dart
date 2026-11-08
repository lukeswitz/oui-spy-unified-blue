import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  Future<void> insert(String mac, int ts, double? lat, {bool approx = false, String name = ''}) =>
      db.insertDetection(DetectionsCompanion(
        sessionId: const drift.Value('s1'),
        nodeId: const drift.Value('default'),
        macAddress: drift.Value(mac),
        deviceName: drift.Value(name),
        engine: const drift.Value('detector'),
        detectionMethod: const drift.Value('ble_watchlist'),
        rssi: const drift.Value(-60),
        channel: const drift.Value(0),
        deviceTimestampMs: drift.Value(ts),
        appTimestamp: drift.Value(ts),
        latitude: drift.Value(lat),
        longitude: drift.Value(lat),
        approxGps: drift.Value(approx),
      ));

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('stops input groups the track by minute and sightings by cell', () async {
    await insert('02:00:00:00:00:01', 60000, 1.0, name: 'Tag');
    await insert('02:00:00:00:00:02', 61000, 1.0002);
    await insert('02:00:00:00:00:01', 120000, 1.0);
    await insert('02:00:00:00:00:01', 180000, 1.02);
    await insert('02:00:00:00:00:03', 240000, 1.5, approx: true);
    await insert('02:00:00:00:00:04', 300000, null);
    await insert('02:00:00:00:00:05', 1000, 1.0);

    final (track, cells) = await db.stopsReportInput(60000);
    expect([for (final p in track) p.$1], [60000, 120000, 180000]);
    expect(track.first.$2, closeTo(1.0001, 1e-9));
    final tag = cells.where((c) => c.mac == '02:00:00:00:00:01').toList();
    expect(tag.length, 2);
    expect(tag.map((c) => c.name), contains('Tag'));
    expect(cells.map((c) => c.mac), isNot(contains('02:00:00:00:00:03')));
    expect(cells.map((c) => c.mac), isNot(contains('02:00:00:00:00:04')));
    expect(cells.map((c) => c.mac), isNot(contains('02:00:00:00:00:05')));
  });

  test('trusted seed lists each access point of one network name', () async {
    Future<void> ap(String mac, String ssid, int auth, double? lat) => db.insertDetection(DetectionsCompanion(
          sessionId: const drift.Value('s1'),
          nodeId: const drift.Value('default'),
          macAddress: drift.Value(mac),
          engine: const drift.Value('wardrive'),
          detectionMethod: const drift.Value('wifi_ap'),
          rssi: const drift.Value(-60),
          channel: const drift.Value(6),
          deviceTimestampMs: const drift.Value(0),
          appTimestamp: const drift.Value(0),
          ssid: drift.Value(ssid),
          authMode: drift.Value(auth),
          latitude: drift.Value(lat),
          longitude: drift.Value(lat),
        ));
    await ap('AA:BB:CC:00:00:01', 'MyNetwork', 3, 1.0);
    await ap('AA:BB:CC:00:00:01', 'MyNetwork', 3, 1.0001);
    await ap('AA:BB:CC:00:00:02', 'MyNetwork', 3, null);
    await ap('AA:BB:CC:00:00:03', 'Other', 0, 1.0);
    final seed = await db.trustedSeed('MyNetwork');
    expect(seed.map((s) => s.mac).toSet(), {'AA:BB:CC:00:00:01', 'AA:BB:CC:00:00:02'});
    expect(seed.firstWhere((s) => s.mac == 'AA:BB:CC:00:00:01').auth, 3);
    expect(seed.firstWhere((s) => s.mac == 'AA:BB:CC:00:00:02').lat, isNull);
  });
}
