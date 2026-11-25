// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';

enum MetricsRange {
  hour('1 H', Duration(hours: 1), Duration(minutes: 5)),
  day('24 H', Duration(hours: 24), Duration(hours: 1)),
  week('7 D', Duration(days: 7), Duration(hours: 6)),
  month('30 D', Duration(days: 30), Duration(days: 1));

  const MetricsRange(this.label, this.span, this.bucket);
  final String label;
  final Duration span;
  final Duration bucket;

  int get buckets => span.inMilliseconds ~/ bucket.inMilliseconds;
}

class MetricRow {
  const MetricRow({
    required this.mac,
    required this.engine,
    required this.method,
    required this.rssi,
    required this.channel,
    required this.atMs,
    required this.node,
  });

  final String mac;
  final String engine;
  final String method;
  final int rssi;
  final int channel;
  final int atMs;
  final String node;
}

const int rssiFloor = -100;
const int rssiBinWidth = 10;
const int rssiBins = 7;

class FleetMetrics {
  const FleetMetrics({
    required this.detections,
    required this.previous,
    required this.unique,
    required this.nodesActive,
    required this.peak,
    required this.bleDevices,
    required this.wifiDevices,
    required this.series,
    required this.byNode,
    required this.byVendor,
    required this.byType,
    required this.rssiHist,
    required this.heat,
  });

  final int detections;
  final int previous;
  final int unique;
  final int nodesActive;
  final int peak;
  final int bleDevices;
  final int wifiDevices;
  final List<int> series;
  final List<(String, int)> byNode;
  final List<(String, int)> byVendor;
  final List<(String, int)> byType;
  final List<int> rssiHist;
  final List<List<int>> heat;

  /// Change against the previous span of the same length, in whole percent; null when there was nothing before.
  int? get changePercent => previous == 0 ? null : (((detections - previous) * 100) / previous).round();
}

List<(String, int)> _top(Map<String, int> m, int n) {
  final l = [for (final e in m.entries) (e.key, e.value)]
    ..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return l.length > n ? l.sublist(0, n) : l;
}

Engine? _engineOf(String name) {
  for (final e in Engine.values) {
    if (e.name == name) return e;
  }
  return null;
}

/// Counts [rows] (the span ending at [toMs]) and compares the count with [previousCount], the span before it.
FleetMetrics computeMetrics(
  Iterable<MetricRow> rows, {
  required MetricsRange range,
  required int toMs,
  required int previousCount,
  required String Function(String mac) vendorOf,
  String Function(String node)? nodeLabel,
  int top = 8,
}) {
  final fromMs = toMs - range.span.inMilliseconds;
  final bucketMs = range.bucket.inMilliseconds;
  final series = List<int>.filled(range.buckets, 0);
  final macs = <String>{};
  final bleMacs = <String>{};
  final wifiMacs = <String>{};
  final nodes = <String>{};
  final byNode = <String, int>{};
  final byType = <String, int>{};
  final vendorMacs = <String, Set<String>>{};
  final rssiHist = List<int>.filled(rssiBins, 0);
  final heat = List.generate(7, (_) => List<int>.filled(24, 0));
  var total = 0;
  for (final r in rows) {
    if (r.atMs < fromMs || r.atMs > toMs) continue;
    total++;
    final b = ((r.atMs - fromMs) ~/ bucketMs).clamp(0, series.length - 1);
    series[b]++;
    macs.add(r.mac);
    final engine = _engineOf(r.engine);
    if (engine != null) {
      final ble = isBleDetectionRaw(method: r.method, engine: engine, channel: r.channel);
      (ble ? bleMacs : wifiMacs).add(r.mac);
    }
    final node = r.node.isEmpty ? 'This board' : r.node;
    nodes.add(node);
    final nodeKey = nodeLabel != null && r.node.isNotEmpty ? nodeLabel(r.node) : node;
    byNode[nodeKey] = (byNode[nodeKey] ?? 0) + 1;
    byType[r.method] = (byType[r.method] ?? 0) + 1;
    (vendorMacs[vendorOf(r.mac)] ??= <String>{}).add(r.mac);
    if (r.rssi != 0) {
      final bin = ((r.rssi - rssiFloor) ~/ rssiBinWidth).clamp(0, rssiBins - 1);
      rssiHist[bin]++;
    }
    final t = DateTime.fromMillisecondsSinceEpoch(r.atMs);
    heat[t.weekday - 1][t.hour]++;
  }
  return FleetMetrics(
    detections: total,
    previous: previousCount,
    unique: macs.length,
    nodesActive: nodes.length,
    peak: series.isEmpty ? 0 : series.reduce((a, b) => a > b ? a : b),
    bleDevices: bleMacs.length,
    wifiDevices: wifiMacs.length,
    series: series,
    byNode: _top(byNode, top),
    byVendor: _top({for (final e in vendorMacs.entries) e.key: e.value.length}, top),
    byType: _top(byType, top),
    rssiHist: rssiHist,
    heat: heat,
  );
}
