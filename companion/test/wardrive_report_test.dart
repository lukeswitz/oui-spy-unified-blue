import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/wardrive_report.dart';
import 'package:oui_spy/theme/app_theme.dart';

const _session = Session(
  id: 's1',
  name: 'Drive',
  nodeId: 'default',
  startedAt: 4000,
  endedAt: 4000 + 3600000 + 12 * 60000,
  enginesActive: 0,
  detectionCount: 0,
  uniqueMacCount: 0,
  distanceKm: 10,
  exported: false,
  isWardrive: true,
);

void main() {
  group('queries', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> det(String sid, String mac, int ts,
            {String method = 'wifi_ap', String ssid = 'MyNetwork', int auth = 3, int ch = 6, double? lat, bool approx = false}) =>
        db.insertDetection(DetectionsCompanion(
          sessionId: drift.Value(sid),
          nodeId: const drift.Value('default'),
          macAddress: drift.Value(mac),
          engine: const drift.Value('wardrive'),
          detectionMethod: drift.Value(method),
          rssi: const drift.Value(-60),
          channel: drift.Value(ch),
          deviceTimestampMs: drift.Value(ts),
          appTimestamp: drift.Value(ts),
          ssid: drift.Value(ssid),
          authMode: drift.Value(auth),
          latitude: drift.Value(lat),
          longitude: drift.Value(lat),
          approxGps: drift.Value(approx),
        ));

    test('session APs are flagged when an earlier session already logged them', () async {
      await det('s0', '02:00:00:00:00:01', 1000);
      await det('s1', '02:00:00:00:00:01', 5000);
      await det('s1', '02:00:00:00:00:01', 6000);
      await det('s1', '02:00:00:00:00:02', 5000, ssid: '', auth: 0, ch: 36);
      await det('s2', '02:00:00:00:00:02', 9000);
      await det('s1', '02:00:00:00:00:03', 5000, method: 'ble_adv');
      final aps = {for (final a in await db.sessionAps('s1', 4000)) a.mac: a};
      expect(aps.keys, unorderedEquals(['02:00:00:00:00:01', '02:00:00:00:00:02']));
      expect(aps['02:00:00:00:00:01']!.seenBefore, isTrue);
      expect(aps['02:00:00:00:00:02']!.seenBefore, isFalse);
      expect((aps['02:00:00:00:00:02']!.ssid, aps['02:00:00:00:00:02']!.auth, aps['02:00:00:00:00:02']!.channel), ('', 0, 36));
    });

    test('route averages 10 s buckets and skips approximate and missing fixes', () async {
      await det('s1', '02:00:00:00:00:01', 1000, lat: 1.0);
      await det('s1', '02:00:00:00:00:02', 2000, lat: 1.0002);
      await det('s1', '02:00:00:00:00:01', 21000, lat: 1.01);
      await det('s1', '02:00:00:00:00:01', 31000, lat: 1.5, approx: true);
      await det('s1', '02:00:00:00:00:01', 41000);
      await det('s1', '02:00:00:00:00:01', 51000, lat: 0);
      await det('s2', '02:00:00:00:00:01', 1000, lat: 2.0);
      final route = await db.sessionRoute('s1');
      expect(route, hasLength(2));
      expect(route.first.$1, closeTo(1.0001, 1e-9));
      expect(route.last.$1, closeTo(1.01, 1e-9));
    });

    test('alert counts cover only the session window, one per radio', () async {
      Future<void> alert(String mac, String cls, int at) => db.insertClassAlert(
            macAddress: mac,
            deviceName: '',
            alertClass: cls,
            title: cls,
            reason: '',
            isBle: true,
            rssi: -60,
            channel: 0,
            alertedAt: at,
          );
      await alert('02:00:00:00:00:01', 'finder', 5000);
      await alert('02:00:00:00:00:01', 'finder', 6000);
      await alert('02:00:00:00:00:02', 'finder', 7000);
      await alert('02:00:00:00:00:03', 'camera', 8000);
      await alert('02:00:00:00:00:04', 'camera', 99999);
      expect(await db.classAlertCountsBetween(4000, 9000), {'finder': 2, 'camera': 1});
    });
  });

  test('report counts bands, security, makers and new networks', () {
    final r = WardriveReport.build(
      session: _session,
      aps: [
        (mac: '00:11:22:00:00:01', ssid: 'MyNetwork', auth: 3, channel: 6, seenBefore: true),
        (mac: '00:11:22:00:00:02', ssid: '', auth: 3, channel: 36, seenBefore: false),
        (mac: '02:00:00:00:00:03', ssid: 'MyNetwork', auth: 0, channel: 11, seenBefore: false),
      ],
      ble: 7,
      route: const [],
      alertCounts: const {'finder': 2},
      flock: 1,
      drones: 0,
      watchlist: 3,
      vendorOf: (mac) => mac.startsWith('00:11:22') ? 'Example Vendor' : 'Should not count',
      wigleUploaded: true,
      wdgwarsUploaded: false,
    );
    expect((r.networks, r.newNetworks, r.seenNetworks, r.hidden), (3, 2, 1, 1));
    expect((r.ghz24, r.ghz5), (2, 1));
    expect(r.security.map((e) => (e.key, e.value)), [('WPA2', 2), ('Open', 1)]);
    expect(r.makers.map((e) => (e.key, e.value)), [('Example Vendor', 2)]);
    expect(r.duration, const Duration(hours: 1, minutes: 12));
    final text = r.shareText(UnitSystem.metric);
    expect(text, contains('Duration 1h 12m · Distance 10.0 km'));
    expect(text, contains('Wi-Fi networks 3 (2 new, 1 seen before)'));
    expect(text, contains('Security: WPA2 2 · Open 1'));
    expect(text, contains('Top makers: Example Vendor 2'));
    expect(text, contains('Flock cameras 1 · Drones 0 · Watchlist hits 3'));
    expect(text, contains('WiGLE uploaded · WDGWars not uploaded'));
    expect(text, isNot(contains('MyNetwork')));
    expect(text, isNot(contains('00:11:22')));
  });
}
