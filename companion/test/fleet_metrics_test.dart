// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/metrics/fleet_metrics.dart';

MetricRow row(String mac, int atMs, {String engine = 'detector', String method = 'ble_adv', int rssi = -60, int channel = 0, String node = ''}) =>
    MetricRow(mac: mac, engine: engine, method: method, rssi: rssi, channel: channel, atMs: atMs, node: node);

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
  });

  group('queries', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> det(String mac, int ts, {String method = 'ble_adv', String ssid = '', String? node, double? lat}) =>
        db.insertDetectionRow(
          DetectionsCompanion(
            sessionId: const drift.Value('s1'),
            nodeId: const drift.Value('default'),
            macAddress: drift.Value(mac),
            engine: const drift.Value('detector'),
            detectionMethod: drift.Value(method),
            rssi: const drift.Value(-60),
            channel: const drift.Value(6),
            deviceTimestampMs: drift.Value(ts),
            appTimestamp: drift.Value(ts),
            ssid: drift.Value(ssid),
            latitude: drift.Value(lat),
            longitude: drift.Value(lat),
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
