// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/metrics/fleet_metrics.dart';
import 'package:oui_spy/core/wardrive_report.dart';

MetricRow row(String mac, int atMs,
        {String engine = 'detector',
        String method = 'ble_adv',
        int rssi = -60,
        int channel = 0,
        String node = '',
        int auth = 0,
        bool placed = false}) =>
    MetricRow(mac: mac, engine: engine, method: method, rssi: rssi, channel: channel, atMs: atMs, node: node, auth: auth, placed: placed);

MetricRow ap(String mac, int atMs, {int channel = 6, int auth = 3, bool placed = false}) =>
    row(mac, atMs, engine: 'wardrive', method: 'wifi_ap', channel: channel, auth: auth, placed: placed);

void main() {
  final to = DateTime(2026, 3, 4, 12).millisecondsSinceEpoch;
  const hour = 3600 * 1000;

  group('computeMetrics', () {
    test('counts, buckets, nodes, vendors, types and signal', () {
      final rows = [
        row('AA:00:00:00:00:01', to - 10 * 60 * 1000, node: 'A1B2', rssi: -45),
        row('AA:00:00:00:00:01', to - 50 * 60 * 1000, node: 'A1B2', rssi: -45),
        row('AA:00:00:00:00:02', to - 3 * hour, node: 'C3D4', method: 'wifi_ap', engine: 'wardrive', channel: 6, rssi: -95),
        row('AA:00:00:00:00:03', to - 30 * hour),
      ];
      final m = computeMetrics(
        rows,
        range: MetricsRange.day,
        toMs: to,
        previousCount: 2,
        vendorOf: (mac) => mac.endsWith('1') ? 'Alpha' : 'Beta',
        nodeLabel: (n) => 'Node $n',
      );
      expect(m.detections, 3);
      expect(m.unique, 2);
      expect(m.nodesActive, 2);
      expect(m.changePercent, 50);
      expect(m.series, hasLength(24));
      expect(m.series.reduce((a, b) => a + b), 3);
      expect(m.peak, 2);
      expect(m.bleDevices, 1);
      expect(m.wifiDevices, 1);
      expect(m.byNode, [('Node A1B2', 2), ('Node C3D4', 1)]);
      expect(m.byVendor, [('Alpha', 1), ('Beta', 1)]);
      expect(m.byType.first, ('ble_adv', 2));
      expect(m.rssiHist[5], 2);
      expect(m.rssiHist[0], 1);
      expect(m.heat.expand((r) => r).reduce((a, b) => a + b), 3);
    });

    test('no earlier span means no change figure; rows outside the span are skipped', () {
      final m = computeMetrics([row('AA:00:00:00:00:01', to + hour)],
          range: MetricsRange.hour, toMs: to, previousCount: 0, vendorOf: (_) => 'x');
      expect(m.detections, 0);
      expect(m.changePercent, isNull);
      expect(m.series, hasLength(12));
    });

    test('new devices, security, channels, bands, makers and placed devices', () {
      final rows = [
        ap('AA:00:00:00:00:01', to - 2 * hour, placed: true),
        ap('AA:00:00:00:00:01', to - hour, placed: true),
        ap('AA:00:00:00:00:02', to - 5 * hour, channel: 11, auth: 0),
        ap('AA:00:00:00:00:03', to - 3 * hour, channel: 36, auth: 6, placed: true),
        ap('AA:00:00:00:00:04', to - 30 * hour, channel: 1),
        row('AA:00:00:00:00:05', to - 4 * hour),
      ];
      final m = computeMetrics(
        rows,
        range: MetricsRange.day,
        toMs: to,
        previousCount: 0,
        vendorOf: (mac) => mac.endsWith('5') ? 'Beta' : 'Alpha',
        securityOf: wifiSecurityLabel,
        newMacs: {'AA:00:00:00:00:01', 'AA:00:00:00:00:03', 'AA:00:00:00:00:05', 'AA:00:00:00:00:04', 'AA:00:00:00:00:99'},
      );
      expect(m.unique, 4);
      expect(m.newDevices, 3);
      expect(m.newBle[20], 1);
      expect(m.newWifi[21], 1);
      expect(m.newWifi[22], 1);
      expect(m.newBle.reduce((a, b) => a + b) + m.newWifi.reduce((a, b) => a + b), 3);
      expect(m.openNetworks, 1);
      expect(m.placed, 2);
      expect(m.security, [('Open', 1), ('WPA2', 1), ('WPA3', 1)]);
      expect(m.channels, [(6, 1), (11, 1), (36, 1)]);
      expect((m.ghz24, m.ghz5), (2, 1));
      expect(m.makers, [('Alpha', 3), ('Beta', 1)]);
    });

    test('a device seen as BLE or Wi-Fi without an access point adds nothing to security or channels', () {
      final m = computeMetrics([row('AA:00:00:00:00:05', to - hour, channel: 6, auth: 3)],
          range: MetricsRange.day, toMs: to, previousCount: 0, vendorOf: (_) => 'x', securityOf: wifiSecurityLabel);
      expect(m.security, isEmpty);
      expect(m.channels, isEmpty);
      expect(m.openNetworks, 0);
    });
  });

  group('computeDroneMetrics', () {
    DroneReport rep(String id, int atMs, {int? alt, int? agl, int? spd, int? rssi, String node = ''}) => DroneReport(
        ts: DateTime.fromMillisecondsSinceEpoch(atMs), id: id, mac: 'AA:00:00:00:00:0${id.length}', alt: alt, height: agl, speed: spd, rssi: rssi, node: node);

    test('counts reports and drones, live ones, peaks and the best signal', () {
      final reports = [
        rep('D1', to - 10 * 1000, alt: 100, agl: 40, spd: 5, rssi: -70, node: 'A1B2'),
        rep('D1', to - 3 * hour, alt: 120, spd: 2, rssi: -50, node: 'A1B2'),
        rep('DRONE2', to - 2 * hour, rssi: -80),
        rep('D1', to - 30 * hour, alt: 900, rssi: -10),
      ];
      final m = computeDroneMetrics(reports,
          range: MetricsRange.day, toMs: to, now: DateTime.fromMillisecondsSinceEpoch(to), nodeLabel: (n) => 'Node $n');
      expect(m.reports, 3);
      expect(m.drones, 2);
      expect(m.live, 1);
      expect((m.maxAlt, m.maxAgl, m.maxSpeed, m.bestRssi), (120, 40, 5, -50));
      expect(m.series.reduce((a, b) => a + b), 3);
      expect(m.byNode, [('Node A1B2', 2), ('This board', 1)]);
      expect(m.summaries.first.id, 'D1');
    });

    test('no reports leaves the peaks empty', () {
      final m = computeDroneMetrics(const [], range: MetricsRange.hour, toMs: to, now: DateTime.fromMillisecondsSinceEpoch(to));
      expect((m.reports, m.drones, m.live, m.maxAlt, m.bestRssi), (0, 0, 0, null, null));
      expect(m.series, hasLength(12));
    });
  });

  group('queries', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> det(
      String mac,
      int ts, {
      String method = 'ble_adv',
      String ssid = '',
      String? node,
      double? lat,
      String engine = 'detector',
      int auth = 0,
      String? uav,
      int? agl,
      int? alt,
      int? spd,
    }) =>
        db.insertDetectionRow(
          DetectionsCompanion(
            sessionId: const drift.Value('s1'),
            nodeId: const drift.Value('default'),
            macAddress: drift.Value(mac),
            engine: drift.Value(engine),
            detectionMethod: drift.Value(method),
            rssi: const drift.Value(-60),
            channel: const drift.Value(6),
            deviceTimestampMs: drift.Value(ts),
            appTimestamp: drift.Value(ts),
            ssid: drift.Value(ssid),
            authMode: drift.Value(auth),
            latitude: drift.Value(lat),
            longitude: drift.Value(lat),
            uavId: drift.Value(uav),
            heightAgl: drift.Value(agl),
            altitudeMsl: drift.Value(alt),
            droneSpeed: drift.Value(spd),
          ),
          ext: node == null ? const {} : {'sourceNodeId': node},
        );

    test('rows, counts and nodes come back per span and node', () async {
      await det('02:00:00:00:00:01', 1000, node: 'A1B2');
      await det('02:00:00:00:00:02', 2000, node: 'C3D4');
      await det('02:00:00:00:00:03', 3000);
      await det('02:00:00:00:00:04', 9000, node: 'A1B2');
      expect((await db.metricRows(500, 5000)).length, 3);
      expect((await db.metricRows(500, 5000, node: 'A1B2')).single.mac, '02:00:00:00:00:01');
      expect((await db.metricRows(500, 5000)).map((r) => r.node).toSet(), {'A1B2', 'C3D4', ''});
      expect(await db.metricCount(0, 2500), 2);
      expect(await db.metricCount(0, 10000, node: 'A1B2'), 2);
      expect(await db.metricNodes(), ['A1B2', 'C3D4']);
    });

    test('rows carry the auth mode and whether the sighting has a position', () async {
      await det('02:00:00:00:00:01', 1000, method: 'wifi_ap', engine: 'wardrive', auth: 6, lat: 10.0);
      await det('02:00:00:00:00:02', 2000, method: 'wifi_ap', engine: 'wardrive', auth: 3);
      final rows = {for (final r in await db.metricRows(0, 5000)) r.mac: r};
      expect((rows['02:00:00:00:00:01']!.auth, rows['02:00:00:00:00:01']!.placed), (6, true));
      expect((rows['02:00:00:00:00:02']!.auth, rows['02:00:00:00:00:02']!.placed), (3, false));
    });

    test('new devices are those with no earlier sighting, per node when one is chosen', () async {
      await det('02:00:00:00:00:01', 1000, node: 'A1B2');
      await det('02:00:00:00:00:01', 3000, node: 'A1B2');
      await det('02:00:00:00:00:02', 3000, node: 'A1B2');
      await det('02:00:00:00:00:03', 9000);
      await det('02:00:00:00:00:04', 500, node: 'A1B2');
      await det('02:00:00:00:00:04', 4000, node: 'C3D4');
      expect(await db.metricNewMacs(2000, 5000), {'02:00:00:00:00:02'});
      expect(await db.metricNewMacs(2000, 5000, node: 'A1B2'), {'02:00:00:00:00:02'});
      expect(await db.metricNewMacs(2000, 5000, node: 'C3D4'), {'02:00:00:00:00:04'});
      expect(await db.metricNewMacs(0, 10000), {'02:00:00:00:00:01', '02:00:00:00:00:02', '02:00:00:00:00:03', '02:00:00:00:00:04'});
    });

    test('drone reports come back from Sky Spy rows only, by id, span and node', () async {
      await det('02:00:00:00:00:0a', 1000, engine: 'skySpy', method: 'wifi_beacon', uav: 'DRONE1', agl: 30, alt: 120, spd: 7, node: 'A1B2');
      await det('02:00:00:00:00:0b', 2000, engine: 'skySpy', method: 'wifi_beacon', node: 'C3D4');
      await det('02:00:00:00:00:0c', 3000);
      await det('02:00:00:00:00:0a', 9000, engine: 'skySpy', method: 'wifi_beacon', uav: 'DRONE1');
      final all = await db.metricDrones(500, 5000);
      expect(all.map((r) => r.id), ['02:00:00:00:00:0b', 'DRONE1']);
      final d = all.last;
      expect((d.height, d.alt, d.speed, d.rssi, d.node, d.mac), (30, 120, 7, -60, 'A1B2', '02:00:00:00:00:0a'));
      expect(all.first.height, isNull);
      expect((await db.metricDrones(500, 5000, node: 'C3D4')).single.id, '02:00:00:00:00:0b');
    });

    test('wardrive summary counts access points and the placed ones', () async {
      await det('02:00:00:00:00:01', 1000, method: 'wifi_ap', ssid: 'MyNetwork', lat: 10.0);
      await det('02:00:00:00:00:01', 2000, method: 'wifi_ap', ssid: 'MyNetwork');
      await det('02:00:00:00:00:02', 3000, method: 'wifi_ap', ssid: 'MyNetwork');
      await det('02:00:00:00:00:03', 4000, method: 'wifi_ap', ssid: 'Other');
      final s = await db.wardriveSsidSummary('MyNetwork');
      expect((s.aps, s.placed, s.lastMs), (2, 1, 3000));
      expect((await db.wardriveSsidSummary('None')).aps, 0);
    });
  });
}
