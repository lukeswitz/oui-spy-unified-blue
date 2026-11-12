import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';

Detection _sighting(String method, {double? lat, double? lon, String ssid = '', int auth = 0, int rssi = -60}) =>
    Detection(
      id: 'AA:BB:CC:DD:EE:FF_$method$rssi',
      sessionId: 's',
      nodeId: 'usb-wifi',
      macAddress: 'AA:BB:CC:DD:EE:FF',
      engine: Engine.wardrive,
      method: method,
      rssi: rssi,
      channel: 6,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.utc(2026, 1, 1),
      ssid: ssid,
      latitude: lat,
      longitude: lon,
      wardrive: WardriveExtension(ssid: ssid, authMode: auth),
    );

void main() {
  test('an AP later seen in a data frame stays an AP and is exported', () {
    final ap = _sighting('wifi_ap', lat: 1, lon: 2);
    final merged = mergeWardriveSighting(ap, _sighting('wifi_client', lat: 1, lon: 2, rssi: -50));
    expect(merged.method, 'wifi_ap');
    expect(merged.count, ap.count + 1);
    expect(merged.rssi, -50);
    final csv = WigleCsv.generate([merged]);
    expect(csv.split('\n').where((l) => l.startsWith('AA:BB:CC:DD:EE:FF')).length, 1);
  });

  test('a later sighting without a fix keeps the stored location', () {
    final merged = mergeWardriveSighting(_sighting('wifi_ap', lat: 1, lon: 2), _sighting('wifi_ap'));
    expect(merged.latitude, 1);
    expect(merged.longitude, 2);
  });

  test('a client later seen as an AP becomes an AP', () {
    final merged = mergeWardriveSighting(_sighting('wifi_client', lat: 1, lon: 2), _sighting('wifi_ap', lat: 1, lon: 2));
    expect(merged.method, 'wifi_ap');
  });

  test('a later SSID and auth fill in an empty stored record', () {
    final merged = mergeWardriveSighting(
        _sighting('wifi_ap', lat: 1, lon: 2), _sighting('wifi_ap', lat: 1, lon: 2, ssid: 'MyNetwork', auth: 3));
    expect(merged.wardrive!.ssid, 'MyNetwork');
    expect(merged.wardrive!.authMode, 3);
  });
}
