import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/db/detection_mapper.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> log(String mac, String cls, int at, {bool ble = false}) => db.insertClassAlert(
        macAddress: mac,
        deviceName: 'DEV',
        alertClass: cls,
        title: 'Cameras: Test',
        reason: 'Signature match',
        isBle: ble,
        rssi: -70,
        channel: 6,
        alertedAt: at,
        latitude: 1.5,
      );

  test('class alerts persist, group per mac+class, newest first, delete and clear', () async {
    await log('AA:00:00:00:00:01', 'camera', 100);
    await log('AA:00:00:00:00:01', 'camera', 200);
    await log('AA:00:00:00:00:02', 'finder', 150, ble: true);

    final rows = await db.getClassAlertMaps();
    expect(rows.length, 2);
    final cam = rows.firstWhere((r) => r['alertClass'] == 'camera');
    expect(cam['count'], 2);
    expect(cam['appTimestamp'], 200);
    expect(cam['engine'], 'signature');
    expect(cam['isBle'], false);
    expect(cam['latitude'], 1.5);
    expect(cam['longitude'], isNull);
    expect(rows.firstWhere((r) => r['alertClass'] == 'finder')['isBle'], true);
    expect(detectionFromDbRow(cam).macAddress, 'AA:00:00:00:00:01');

    await db.deleteClassAlerts('AA:00:00:00:00:01', 'camera');
    expect((await db.getClassAlertMaps()).length, 1);
    expect(await db.clearClassAlerts(), 1);
    expect(await db.getClassAlertMaps(), isEmpty);
  });

  test('history merges a class alert into the engine row for the same mac', () async {
    await db.insertDetection(DetectionsCompanion(
      sessionId: const drift.Value('s1'),
      nodeId: const drift.Value('n'),
      macAddress: const drift.Value('aa:00:00:00:00:01'),
      engine: const drift.Value('detector'),
      detectionMethod: const drift.Value('camera'),
      rssi: const drift.Value(-90),
      channel: const drift.Value(6),
      deviceTimestampMs: const drift.Value(0),
      appTimestamp: const drift.Value(50),
    ));
    await log('AA:00:00:00:00:01', 'camera', 100);
    await log('AA:00:00:00:00:02', 'finder', 150, ble: true);

    final rows = await db.getAlertHistoryMaps();
    expect(rows.length, 2);
    final host = rows.firstWhere((r) => r['engine'] == 'detector');
    expect(host['mergedClasses'], [('AA:00:00:00:00:01', 'camera')]);
    expect(host['classTitle'], 'Cameras: Test');
    expect(rows.where((r) => r['engine'] == 'signature').single['alertClass'], 'finder');
    expect((await db.getClassAlertMaps()).length, 2);
  });
}
