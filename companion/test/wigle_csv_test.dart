import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

Detection _d(String mac, String method, {Engine engine = Engine.wardrive, int channel = 6, int? auth, String ssid = 'MyNetwork'}) =>
    Detection(
      id: mac,
      sessionId: 's',
      nodeId: 'n',
      macAddress: mac,
      engine: engine,
      method: method,
      rssi: -60,
      channel: channel,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.utc(2026, 1, 1),
      ssid: ssid,
      latitude: 10.0,
      longitude: 20.0,
      wardrive: auth == null ? null : WardriveExtension(ssid: ssid, authMode: auth),
    );

List<String> _rows(String csv) => csv.split('\n').skip(2).where((l) => l.isNotEmpty).toList();

void main() {
  test('every detection is exported, clients and detector rows included', () {
    final csv = WigleCsv.generate([
      _d('02:00:00:00:00:01', 'wifi_ap', auth: 3),
      _d('02:00:00:00:00:02', 'wifi_client', auth: 3),
      _d('02:00:00:00:00:03', 'probe_ssid', engine: Engine.detector),
      _d('02:00:00:00:00:04', 'deauth_storm', engine: Engine.detector),
      _d('02:00:00:00:00:05', 'karma', engine: Engine.detector),
    ]);
    expect(_rows(csv).length, 5);
  });

  test('a Bluetooth hit without a MAC address, such as an iPhone device ID, stays out', () {
    final rows = _rows(WigleCsv.generate([
      _d('8C4F1A2B-0000-4000-8000-000000000001', 'ble_adv', ssid: ''),
      _d('02:00:00:00:00:07', 'ble_adv', ssid: ''),
    ]));
    expect(rows.length, 1);
    expect(rows.single, startsWith('02:00:00:00:00:07,'));
  });

  test('a detection without a fix is still exported with blank coordinates', () {
    final noFix = _d('02:00:00:00:00:06', 'wifi_ap', auth: 3).copyWith(latitude: null, longitude: null);
    final row = _rows(WigleCsv.generate([noFix])).single.split(',');
    expect(row[7], '');
    expect(row[8], '');
  });

  test('auth is written as observed, never guessed', () {
    final rows = _rows(WigleCsv.generate([
      _d('02:00:00:00:00:01', 'wifi_ap', auth: 7),
      _d('02:00:00:00:00:02', 'wifi_ap', auth: 8),
      _d('02:00:00:00:00:03', 'wifi_ap', auth: 9),
      _d('02:00:00:00:00:04', 'wifi_ap', auth: 0xFF),
      _d('02:00:00:00:00:05', 'oui_addr2', engine: Engine.flockWifi),
    ]));
    expect(rows.map((r) => r.split(',')[2]).toList(),
        ['[WPA2_PSK][WPA3_SAE]', '[OWE]', '[WPA3_EAP]', '[UNKNOWN]', '[UNKNOWN]']);
  });

  test('BLE rows leave channel and frequency blank; lines end in LF like WiGLE', () {
    final csv = WigleCsv.generate([
      _d('02:00:00:00:00:01', 'ble_adv', channel: 37, ssid: ''),
      _d('02:00:00:00:00:02', 'wifi_ap', channel: 36, auth: 3),
    ]);
    expect(csv.contains('\r'), isFalse);
    final rows = _rows(csv);
    final ble = rows[0].split(',');
    expect(ble[4], '');
    expect(ble[5], '');
    final wifi = rows[1].split(',');
    expect(wifi[4], '36');
    expect(wifi[5], '5180');
  });
}
