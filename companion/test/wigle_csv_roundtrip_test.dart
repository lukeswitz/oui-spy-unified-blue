import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

Detection _ap(int i, int auth) => Detection(
      id: '$i',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:${i.toRadixString(16).padLeft(2, '0')}',
      engine: Engine.wardrive,
      method: 'wifi_ap',
      rssi: -60,
      channel: 6,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.utc(2026, 11, 23, 12, 0, i),
      ssid: 'MyNetwork$i',
      latitude: 51.4,
      longitude: -0.1,
      wardrive: WardriveExtension(ssid: 'MyNetwork$i', authMode: auth),
    );

void main() {
  test('every auth mode and BLE survive an export and re-import', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const modes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xFF];
    final csv = WigleCsv.generate([
      for (var i = 0; i < modes.length; i++) _ap(i, modes[i]),
      _ap(0x20, 0).copyWith(macAddress: '02:00:00:00:00:20', method: 'ble_adv', channel: 0, ssid: ''),
    ]);
    await WigleCsvImport.importString(db, csv, fileName: 'roundtrip.csv');
    final rows = await db.customSelect('SELECT mac_address, auth_mode, detection_method FROM detections').get();
    final byMac = {for (final r in rows) r.read<String>('mac_address').toLowerCase(): r};
    for (var i = 0; i < modes.length; i++) {
      final r = byMac['02:00:00:00:00:${i.toRadixString(16).padLeft(2, '0')}']!;
      expect(r.read<int>('auth_mode'), modes[i], reason: 'auth ${modes[i]}');
    }
    expect(byMac['02:00:00:00:00:20']!.read<String>('detection_method'), 'ble_adv');
    await db.close();
  });
}
