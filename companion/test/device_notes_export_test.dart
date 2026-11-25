// Copyright (c) 2026 Luke Switzer
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/export/device_export.dart';
import 'package:oui_spy/core/export/kmz.dart';
import 'package:oui_spy/features/feed/detection_row.dart' show detectionHeadline;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  Future<void> insert(String mac, int ts, {String name = ''}) => db.insertDetection(DetectionsCompanion(
        sessionId: const drift.Value('s1'),
        nodeId: const drift.Value('default'),
        macAddress: drift.Value(mac),
        deviceName: drift.Value(name),
        engine: const drift.Value('detector'),
        detectionMethod: const drift.Value('glasses'),
        rssi: const drift.Value(-70),
        channel: const drift.Value(0),
        deviceTimestampMs: drift.Value(ts),
        appTimestamp: drift.Value(ts),
        latitude: const drift.Value(10.0),
        longitude: const drift.Value(20.0),
      ));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => db.close());

  test('crc32 matches the standard check value', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });

  test('one device exports only its own sightings, oldest first, in every format', () async {
    await insert('AA:BB:CC:DD:EE:01', 2000, name: 'Cam <"x">');
    await insert('aa:bb:cc:dd:ee:01', 1000);
    await insert('AA:BB:CC:DD:EE:02', 1500);
    final rows = (await db.getDetectionMapsForMac('AA:BB:CC:DD:EE:01')).map(detectionFromDbRow).toList();
    expect(rows.map((d) => d.appTimestamp.millisecondsSinceEpoch), [1000, 2000]);

    final j = jsonDecode(DeviceExport.json(rows, name: 'Van "2"', notes: 'line1\nline2')) as Map;
    expect(j['name'], 'Van "2"');
    expect((j['sightings'] as List), hasLength(2));

    final kml = DeviceExport.kml(rows, title: 'Van <2>');
    expect(kml, contains('<name>Van &lt;2&gt;</name>'));
    expect('<Placemark>'.allMatches(kml), hasLength(2));

    final dir = await Directory.systemTemp.createTemp('kmz');
    final f = File('${dir.path}/t.kmz')..writeAsBytesSync(kmzFromKml(kml));
    final unzip = await Process.run('unzip', ['-p', f.path, 'doc.kml']);
    expect(unzip.exitCode, 0);
    expect(unzip.stdout, kml);
    final check = await Process.run('unzip', ['-t', f.path]);
    expect(check.stdout, contains('No errors detected'));
    await dir.delete(recursive: true);
  });

  test('a device name replaces the headline everywhere it is used', () async {
    await insert('AA:BB:CC:DD:EE:03', 1, name: 'Broadcast name');
    final d = detectionFromDbRow((await db.getDetectionMapsForMac('AA:BB:CC:DD:EE:03')).single);
    expect(detectionHeadline(d), 'Broadcast name');
    final notes = DeviceNotesNotifier();
    await notes.set('aa:bb:cc:dd:ee:03', const DeviceNote(name: 'Neighbor dashcam', group: 'Street'));
    expect(detectionHeadline(d), 'Neighbor dashcam');
    expect(notes.groups, ['Street']);
    await notes.set('AA:BB:CC:DD:EE:03', const DeviceNote());
    expect(detectionHeadline(d), 'Broadcast name');
    final p = await SharedPreferences.getInstance();
    expect(jsonDecode(p.getString('device_notes')!), isEmpty);
  });
}
