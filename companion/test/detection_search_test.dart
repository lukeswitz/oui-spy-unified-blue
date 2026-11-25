// Copyright (c) 2026 Luke Switzer
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/models/engine.dart';

void main() {
  late AppDatabase db;

  Future<void> insert({
    required String mac,
    String name = '',
    String ssid = '',
    String method = 'ble_watchlist',
    String engine = 'detector',
    String nodeId = 'default',
    int ts = 0,
  }) =>
      db.insertDetection(DetectionsCompanion(
        sessionId: const drift.Value('s1'),
        nodeId: drift.Value(nodeId),
        macAddress: drift.Value(mac),
        deviceName: drift.Value(name),
        engine: drift.Value(engine),
        detectionMethod: drift.Value(method),
        rssi: const drift.Value(-70),
        channel: const drift.Value(6),
        deviceTimestampMs: drift.Value(ts),
        appTimestamp: drift.Value(ts),
        ssid: drift.Value(ssid),
      ));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('searches beyond the 500-row live buffer across every indexed field',
      () async {
    for (var i = 0; i < 600; i++) {
      await insert(mac: 'FF:FF:FF:00:00:${i.toRadixString(16).padLeft(2, '0')}', ts: i);
    }
    await insert(mac: '00:25:DF:9A:E4:F0', name: 'AxonTaser', ts: 5);
    await insert(mac: 'AA:BB:CC:11:22:33', ssid: 'FlockCam-1', engine: 'wardrive', ts: 6);
    await insert(mac: 'AA:BB:CC:44:55:66', method: 'pwnagotchi', ts: 7);
    await insert(mac: 'AA:BB:CC:77:88:99', nodeId: 'node-alpha', ts: 8);

    expect((await db.searchDetectionMaps('00:25:DF')).length, 1);
    expect((await db.searchDetectionMaps('axontaser')).length, 1);
    expect((await db.searchDetectionMaps('flockcam')).length, 1);
    expect((await db.searchDetectionMaps('pwnagotchi')).length, 1);
    expect((await db.searchDetectionMaps('node-alpha')).length, 1);
  });

  test('oldest rows stay reachable once the live buffer would have evicted them',
      () async {
    await insert(mac: '00:25:DF:00:00:01', name: 'AxonTaser', ts: 1);
    for (var i = 0; i < 600; i++) {
      await insert(mac: 'FF:FF:FF:00:00:${i.toRadixString(16).padLeft(2, '0')}', ts: 100 + i);
    }
    final hits = await db.searchDetectionMaps('AxonTaser');
    expect(hits, hasLength(1));
    final det = detectionFromDbRow(hits.first);
    expect(det.macAddress, '00:25:DF:00:00:01');
    expect(det.engine, Engine.detector);
    expect(det.method, 'ble_watchlist');
  });

  test('LIKE wildcards in the query are literal, empty query returns nothing',
      () async {
    await insert(mac: 'AA:BB:CC:00:00:01', name: 'kitchen%cam');
    await insert(mac: 'AA:BB:CC:00:00:02', name: 'kitchen-cam');

    expect((await db.searchDetectionMaps('kitchen%')).length, 1);
    expect((await db.searchDetectionMaps('kitchen')).length, 2);
    expect(await db.searchDetectionMaps('   '), isEmpty);
  });

  test('honours the row limit and returns newest first', () async {
    for (var i = 0; i < 50; i++) {
      await insert(mac: 'AA:BB:CC:00:00:01', name: 'target', ts: i);
    }
    final hits = await db.searchDetectionMaps('target', limit: 10);
    expect(hits, hasLength(10));
    expect(hits.first['appTimestamp'], 49);
    expect(hits.last['appTimestamp'], 40);
  });
}
