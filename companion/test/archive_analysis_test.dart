import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  Future<void> insert(String mac, {String ssid = '', int rssi = -70, int ts = 0, double? lat, String engine = 'wardrive'}) =>
      db.insertDetection(DetectionsCompanion(
        sessionId: const drift.Value('s1'),
        nodeId: const drift.Value('default'),
        macAddress: drift.Value(mac),
        engine: drift.Value(engine),
        detectionMethod: const drift.Value('wifi_ap'),
        rssi: drift.Value(rssi),
        channel: const drift.Value(6),
        deviceTimestampMs: drift.Value(ts),
        appTimestamp: drift.Value(ts),
        ssid: drift.Value(ssid),
        latitude: drift.Value(lat),
        longitude: drift.Value(lat),
      ));

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('search folds sightings per device and matches a MAC with any separator', () async {
    await insert('02:00:00:00:00:01', ssid: 'MyNetwork', rssi: -80, ts: 10, lat: 1);
    await insert('02:00:00:00:00:01', ssid: 'MyNetwork', rssi: -50, ts: 20);
    await insert('02:00:00:00:00:02', ssid: 'Other', ts: 30);

    final byMac = await db.searchArchive('020000000001');
    expect(byMac.length, 1);
    expect(byMac.single.sightings, 2);
    expect(byMac.single.bestRssi, -50);
    expect(byMac.single.firstMs, 10);
    expect(byMac.single.lastMs, 20);
    expect((await db.searchArchive('02-00-00-00-00-01')).length, 1);
    expect((await db.searchArchive('mynet')).single.ssid, 'MyNetwork');
    expect(await db.searchArchive('100%'), isEmpty);

    final o = await db.archiveOverview();
    expect(o.detections, 3);
    expect(o.devices, 2);
    expect(o.withGps, 1);
    expect(o.firstMs, 10);
    expect(o.lastMs, 30);
    expect(o.byEngine.single.engine, 'wardrive');
  });
}
