// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/db/session_detection_store.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';

Detection _base(Engine engine, {String mac = 'AA:BB:CC:DD:EE:01', int t = 1000, int rssi = -60}) =>
    Detection(
      id: '0',
      sessionId: 's1',
      nodeId: 'default',
      macAddress: mac,
      engine: engine,
      method: 'm',
      rssi: rssi,
      channel: 6,
      deviceTimestampMs: 5,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(t),
      deviceName: 'dev',
      ssid: 'MyNetwork',
      count: 3,
      sourceNodeId: 'N1',
      latitude: 51.4,
      longitude: -0.1,
      altitude: 1600,
      speed: 1.5,
      heading: 90,
      accuracy: 5,
      satelliteCount: 9,
      approxGps: true,
    );

const _odid = OdidExtension(
  uavId: 'UAV123',
  operatorId: 'OP9',
  droneLat: 51.401,
  droneLon: -0.102,
  altitudeMsl: 1650,
  heightAgl: 50,
  droneSpeed: 7,
  droneHeading: 180,
  pilotLat: 51.4005,
  pilotLon: -0.1006,
  selfId: 'training flight',
  altitudeBaro: 1649,
  vertSpeed: -1,
  operatorAlt: 1600,
  areaCount: 2,
  areaRadius: 30,
  areaCeiling: 120,
  areaFloor: 0,
  locTimestamp: 4242,
  uaType: 2,
  idType: 1,
  opIdType: 1,
  opLocationType: 0,
  classification: 1,
  categoryEu: 1,
  classEu: 2,
  heightType: 0,
  status: 2,
  horizAcc: 3,
  vertAcc: 4,
  baroAcc: 5,
  speedAcc: 6,
  selfIdType: 7,
);

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.upsertNode(NodesCompanion.insert(
    id: 'default',
    name: 'n',
    macAddress: 'AA:BB:CC:DD:EE:FF',
    createdAt: 0,
  ));
  for (final sid in ['s1', 's2']) {
    await db.insertSession(SessionsCompanion.insert(
      id: sid,
      name: sid,
      nodeId: 'default',
      startedAt: 0,
    ));
  }
  return db;
}

Future<List<Detection>> _load(AppDatabase db, String sid) async => [
      for (final r in await db.getDetectionMapsForSession(sid)) detectionFromDbRow(r),
    ];

void main() {
  late AppDatabase db;
  setUp(() async => db = await _db());
  tearDown(() => db.close());

  group('every engine round-trips through the database', () {
    final cases = <String, Detection>{
      'wardrive': _base(Engine.wardrive).copyWith(
        method: 'wifi_ap',
        wardrive: const WardriveExtension(ssid: 'MyNetwork', authMode: 4, deviceName: 'dev'),
      ),
      'flockBle': _base(Engine.flockBle).copyWith(
        flock: const FlockExtension(isRaven: true, ravenFirmware: '1.2', signals: 0x47),
      ),
      'skySpy': _base(Engine.skySpy).copyWith(odid: _odid),
      'detector': _base(Engine.detector).copyWith(
        method: 'deauth_storm',
        detector: const DetectorExtension(
            filterDescription: 'Deauth flood', isFullMac: true, confidence: 2),
      ),
      'uniPwn': _base(Engine.uniPwn).copyWith(
        unipwn: const UnipwnExtension(robotType: 'G1', exploited: true, serialNumber: 'SN1'),
      ),
      'flockWifi': _base(Engine.flockWifi).copyWith(
        method: 'wildcard_probe',
        flock: const FlockExtension(signals: 0x05),
        wardrive: const WardriveExtension(authMode: 3),
      ),
      'foxhunter': _base(Engine.foxhunter).copyWith(method: 'ble_proximity'),
      'pcap': _base(Engine.pcap).copyWith(method: 'pcap'),
      'sdr': _base(Engine.sdr).copyWith(method: 'sdr', ssid: '{"model":"Schrader","id":"0000"}'),
      'board-local wardrive BLE': _base(Engine.wardrive).copyWith(
        nodeId: 'OUISPY-AB12',
        sourceNodeId: '',
        ssid: '',
        method: 'ble_adv',
        channel: 0,
        wardrive: const WardriveExtension(deviceName: 'dev'),
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        final src = e.value;
        final id = await db.insertDetectionRow(
          detectionCompanion(src, 's1'),
          ext: detectionExt(src),
        );
        final back = (await _load(db, 's1')).single;
        expect(back, src.copyWith(id: '$id'));
      });
    }
  });

  group('a stored session equals the live deduped state', () {
    test('updates fold into one latest row per device and drone movement keeps a track', () async {
      final store = SessionDetectionStore(db, flushEvery: const Duration(milliseconds: 10));
      const key = 'AA:BB:CC:DD:EE:01|skySpy';
      var live = _base(Engine.skySpy, t: 1000, rssi: -70).copyWith(odid: _odid);
      store.insert(key, 's1', live);

      final moved = _base(Engine.skySpy, t: 2000, rssi: -65)
          .copyWith(odid: _odid.copyWith(droneLat: 51.402, droneLon: -0.103));
      live = mergeWardriveSighting(live, moved);
      store.insert(key, 's1', live);

      final again = _base(Engine.skySpy, t: 3000, rssi: -50)
          .copyWith(odid: _odid.copyWith(droneLat: 51.402, droneLon: -0.103, altitudeMsl: 1700));
      live = mergeWardriveSighting(live, again);
      store.update(key, 's1', live);
      await store.flush();

      final rows = await _load(db, 's1');
      expect(rows.length, 2);
      final folded = foldSessionRows(rows).values.single;
      expect(folded.odid, live.odid);
      expect(folded.count, live.count);
      expect(detectionLastSeenMs[folded], live.appTimestamp.millisecondsSinceEpoch);
      expect(observationFromDetection(folded).lastSeenMs, live.appTimestamp.millisecondsSinceEpoch);
      expect(observationFromDetection(folded).firstSeenMs, 1000);
      expect(rows.first.odid?.droneLat, 51.401);
      expect(rows.last.odid?.droneLat, 51.402);
      store.dispose();
    });

    test('BLE advertisement bytes and the RSSI range survive a reload', () async {
      final store = SessionDetectionStore(db, flushEvery: const Duration(milliseconds: 10));
      const key = 'AA:BB:CC:DD:EE:01|wardrive';
      const ext = WardriveExtension(deviceName: 'dev');
      wardriveAdvRaw[ext] = const [2, 1, 6, 3, 3, 0x6F, 0xFD];
      final first = _base(Engine.wardrive, t: 1000, rssi: -80).copyWith(method: 'ble_adv', wardrive: ext);
      store.insert(key, 's1', first);
      var live = mergeWardriveSighting(first, _base(Engine.wardrive, t: 2000, rssi: -40).copyWith(method: 'ble_adv'));
      live = mergeWardriveSighting(live, _base(Engine.wardrive, t: 3000, rssi: -60).copyWith(method: 'ble_adv'));
      store.update(key, 's1', live);
      await store.flush();

      final folded = foldSessionRows(await _load(db, 's1')).values.single;
      expect(wardriveAdvRaw[folded.wardrive!], const [2, 1, 6, 3, 3, 0x6F, 0xFD]);
      final o = observationFromDetection(folded);
      expect(o.rssiMin, -80);
      expect(o.rssiMax, -40);
      expect(o.rssi, -60);
      expect(o.serviceUuids, isNotEmpty);
      store.dispose();
    });

    test('a device first seen before the GPS fix gets the first fix it is seen with', () async {
      final store = SessionDetectionStore(db, flushEvery: const Duration(milliseconds: 10));
      const key = 'AA:BB:CC:DD:EE:03|wardrive';
      final first = _base(Engine.wardrive, mac: 'AA:BB:CC:DD:EE:03', t: 1000)
          .copyWith(method: 'ble_adv', latitude: null, longitude: null, altitude: null, accuracy: null);
      store.insert(key, 's1', first);
      final fixed = mergeWardriveSighting(first, _base(Engine.wardrive, mac: 'AA:BB:CC:DD:EE:03', t: 2000)
          .copyWith(method: 'ble_adv', latitude: 51.41, longitude: -0.11, altitude: 1612.5, accuracy: 4));
      store.update(key, 's1', fixed);
      await store.flush();
      final later = mergeWardriveSighting(fixed, _base(Engine.wardrive, mac: 'AA:BB:CC:DD:EE:03', t: 3000)
          .copyWith(method: 'ble_adv', latitude: 51.42, longitude: -0.12, altitude: 1700, accuracy: 9));
      store.update(key, 's1', later);
      await store.flush();
      final row = (await db.getDetectionMapsForSession('s1')).single;
      expect(row['latitude'], 51.41);
      expect(row['longitude'], -0.11);
      expect(row['altitude'], 1612.5);
      expect(row['accuracy'], 4);
      store.dispose();
    });

    test('a Wi-Fi client keeps the AP it was linked to after a reload', () async {
      final store = SessionDetectionStore(db, flushEvery: const Duration(milliseconds: 10));
      const key = 'AA:BB:CC:DD:EE:02|wardrive';
      final first = _base(Engine.wardrive, mac: 'AA:BB:CC:DD:EE:02', t: 1000).copyWith(method: 'wifi_client');
      detectionClientAp[first] = 'aa:bb:cc:dd:ee:10';
      store.insert(key, 's1', first);
      final live = mergeWardriveSighting(
          first, _base(Engine.wardrive, mac: 'AA:BB:CC:DD:EE:02', t: 2000).copyWith(method: 'wifi_client'));
      store.update(key, 's1', live);
      await store.flush();

      final folded = foldSessionRows(await _load(db, 's1')).values.single;
      expect(detectionClientAp[folded], 'aa:bb:cc:dd:ee:10');
      store.dispose();
    });

    test('updates never change the fields the WiGLE CSV reads', () async {
      final store = SessionDetectionStore(db, flushEvery: const Duration(milliseconds: 10));
      const key = 'AA:BB:CC:DD:EE:01|wardrive';
      final first = _base(Engine.wardrive, t: 1000, rssi: -80).copyWith(
        method: 'wifi_ap',
        count: 1,
        ssid: '',
        wardrive: const WardriveExtension(ssid: '', authMode: 0, deviceName: ''),
      );
      store.insert(key, 's1', first);
      final later = _base(Engine.wardrive, t: 9000, rssi: -40).copyWith(
        method: 'wifi_ap',
        latitude: 41.0,
        longitude: -106.0,
        ssid: 'MyNetwork',
        wardrive: const WardriveExtension(ssid: 'MyNetwork', authMode: 4, deviceName: ''),
      );
      store.update(key, 's1', mergeWardriveSighting(first, later));
      await store.flush();

      final row = (await _load(db, 's1')).single;
      expect(row.appTimestamp, first.appTimestamp);
      expect(row.rssi, first.rssi);
      expect(row.latitude, first.latitude);
      expect(row.longitude, first.longitude);
      expect(row.channel, first.channel);
      expect(row.method, 'wifi_ap');
      expect(row.count, 2);
      expect(row.ssid, 'MyNetwork');
      expect(row.wardrive?.authMode, 4);
      store.dispose();
    });

    test('rows written before counts were stored still fold to a count of rows', () {
      final rows = [
        for (var i = 0; i < 4; i++)
          _base(Engine.wardrive, t: 1000 + i).copyWith(count: 1, method: 'wifi_ap'),
      ];
      expect(foldSessionRows(rows).values.single.count, 4);
    });
  });

  group('alerts belong to a session', () {
    Future<void> alert(String sid, String kind, int at) => db.insertClassAlert(
          macAddress: 'AA:BB:CC:DD:EE:01',
          deviceName: 'dev',
          alertClass: kind,
          title: 'title $kind',
          reason: 'why',
          isBle: false,
          rssi: -50,
          channel: 6,
          alertedAt: at,
          latitude: 51.4,
          longitude: -0.1,
          sessionId: sid,
        );

    test('each session returns only its own alerts, every row kept', () async {
      await alert('s1', 'deauth_storm', 1);
      await alert('s1', 'deauth_storm', 2);
      await alert('s1', 'drone', 3);
      await alert('s2', 'deauth_storm', 4);
      final s1 = await db.getClassAlertsForSession('s1');
      expect(s1.map((r) => r['alertClass']), ['deauth_storm', 'deauth_storm', 'drone']);
      expect(s1.every((r) => r['latitude'] == 51.4), isTrue);
      expect((await db.getClassAlertsForSession('s2')).length, 1);
      expect(await db.getClassAlertsForSession(''), isEmpty);
      final global = await db.getClassAlertMaps();
      expect(global.firstWhere((r) => r['alertClass'] == 'deauth_storm')['count'], 3);
    });
  });

  test('the session GPS track is stored in order and removed with the session', () async {
    await db.insertTrackPoints('s1', [
      (ts: 2000, lat: 51.401, lon: -0.1),
      (ts: 1000, lat: 51.4, lon: -0.1),
    ]);
    await db.insertTrackPoints('s2', [(ts: 1500, lat: 41.0, lon: -106.0)]);
    expect((await db.getSessionTrack('s1')).map((p) => p.ts), [1000, 2000]);
    await db.deleteSession('s1');
    expect(await db.getSessionTrack('s1'), isEmpty);
    expect((await db.getSessionTrack('s2')).length, 1);
  });

  test('upgrade from schema 10 adds the track table', () async {
    final old = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('PRAGMA user_version = 10');
    }));
    addTearDown(old.close);
    final t = await old
        .customSelect("SELECT name FROM sqlite_master WHERE name = 'session_track'")
        .get();
    expect(t.length, 1);
  });

  test('deleting a detection removes its extra details', () async {
    final src = _base(Engine.skySpy).copyWith(odid: _odid);
    final id = await db.insertDetectionRow(detectionCompanion(src, 's1'), ext: detectionExt(src));
    await db.deleteDetectionById(id);
    final left = await db.customSelect('SELECT COUNT(*) AS c FROM detection_ext').getSingle();
    expect(left.read<int>('c'), 0);
  });

  test('upgrade from schema 9 adds the session column and details table', () async {
    final old = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE detections (id INTEGER PRIMARY KEY AUTOINCREMENT)');
      raw.execute('CREATE TABLE class_alerts (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'mac_address TEXT NOT NULL, device_name TEXT NOT NULL DEFAULT \'\', '
          'alert_class TEXT NOT NULL, title TEXT NOT NULL, reason TEXT NOT NULL DEFAULT \'\', '
          'is_ble INTEGER NOT NULL, rssi INTEGER NOT NULL, channel INTEGER NOT NULL, '
          'alerted_at INTEGER NOT NULL, latitude REAL, longitude REAL)');
      raw.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, started_at INTEGER NOT NULL, '
          'ended_at INTEGER, is_wardrive INTEGER NOT NULL DEFAULT 0)');
      raw.execute("INSERT INTO sessions VALUES ('cap', 0, 1000, 0), ('wd', 100, 200, 1), "
          "('crashed', 4000, NULL, 1)");
      raw.execute("INSERT INTO class_alerts (mac_address, alert_class, title, is_ble, rssi, channel, alerted_at) "
          "VALUES ('AA:BB:CC:DD:EE:01', 'drone', 't', 0, -50, 6, 150), "
          "('AA:BB:CC:DD:EE:02', 'drone', 't', 0, -50, 6, 500), "
          "('AA:BB:CC:DD:EE:03', 'drone', 't', 0, -50, 6, 5000)");
      raw.execute('PRAGMA user_version = 9');
    }));
    addTearDown(old.close);
    final cols = await old.customSelect('PRAGMA table_info(class_alerts)').get();
    expect(cols.map((c) => c.read<String>('name')), contains('session_id'));
    final linked = await old
        .customSelect('SELECT mac_address, session_id FROM class_alerts ORDER BY alerted_at')
        .get();
    expect(linked.map((r) => r.read<String>('session_id')), ['wd', 'cap', '']);
    final ext = await old
        .customSelect("SELECT name FROM sqlite_master WHERE name IN ('detection_ext', 'trg_detection_ext_delete')")
        .get();
    expect(ext.length, 2);
  });
}
