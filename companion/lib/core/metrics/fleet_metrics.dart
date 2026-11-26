// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

import 'package:oui_spy/core/drone_flights.dart';
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
    this.auth = 0,
    this.placed = false,
  });

  final String mac;
  final String engine;
  final String method;
  final int rssi;
  final int channel;
  final int atMs;
  final String node;
  final int auth;
  final bool placed;
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
    this.newDevices = 0,
    this.newBle = const [],
    this.newWifi = const [],
    this.openNetworks = 0,
    this.placed = 0,
    this.security = const [],
    this.channels = const [],
    this.ghz24 = 0,
    this.ghz5 = 0,
    this.makers = const [],
  });

  final int newDevices;
  final List<int> newBle;
  final List<int> newWifi;
  final int openNetworks;
  final int placed;
  final List<(String, int)> security;
  final List<(int, int)> channels;
  final int ghz24;
  final int ghz5;
  final List<(String, int)> makers;

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

const String accessPointMethod = 'wifi_ap';

/// Counts [rows] (the span ending at [toMs]) and compares the count with [previousCount], the span before it.
/// [newMacs] are the devices with no sighting before the span; [securityOf] names an access point's auth mode.
FleetMetrics computeMetrics(
  Iterable<MetricRow> rows, {
  required MetricsRange range,
  required int toMs,
  required int previousCount,
  required String Function(String mac) vendorOf,
  String Function(String node)? nodeLabel,
  String Function(int auth)? securityOf,
  Set<String> newMacs = const {},
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
  final firstAt = <String, int>{};
  final placedMacs = <String>{};
  final apAuth = <String, int>{};
  final apChannel = <String, int>{};
  var total = 0;
  for (final r in rows) {
    if (r.atMs < fromMs || r.atMs > toMs) continue;
    total++;
    final seenFirst = firstAt[r.mac];
    if (seenFirst == null || r.atMs < seenFirst) firstAt[r.mac] = r.atMs;
    if (r.placed) placedMacs.add(r.mac);
    if (r.method == accessPointMethod) {
      apAuth[r.mac] = math.max(apAuth[r.mac] ?? 0, r.auth);
      apChannel[r.mac] = math.max(apChannel[r.mac] ?? 0, r.channel);
    }
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
  final newBle = List<int>.filled(range.buckets, 0);
  final newWifi = List<int>.filled(range.buckets, 0);
  var fresh = 0;
  for (final mac in newMacs) {
    final at = firstAt[mac];
    if (at == null) continue;
    fresh++;
    final b = ((at - fromMs) ~/ bucketMs).clamp(0, newBle.length - 1);
    if (bleMacs.contains(mac)) {
      newBle[b]++;
    } else if (wifiMacs.contains(mac)) {
      newWifi[b]++;
    }
  }
  final label = securityOf ?? (int a) => '$a';
  final security = <String, int>{};
  final channels = <int, int>{};
  var open = 0, g24 = 0, g5 = 0;
  for (final e in apAuth.entries) {
    if (e.value == 0) open++;
    security[label(e.value)] = (security[label(e.value)] ?? 0) + 1;
  }
  for (final c in apChannel.values) {
    if (c <= 0) continue;
    channels[c] = (channels[c] ?? 0) + 1;
    if (c <= 14) {
      g24++;
    } else if (c >= 32 && c <= 177) {
      g5++;
    }
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
    newDevices: fresh,
    newBle: newBle,
    newWifi: newWifi,
    openNetworks: open,
    placed: placedMacs.length,
    security: _top(security, top),
    channels: [for (final e in channels.entries) (e.key, e.value)]..sort((a, b) => a.$1.compareTo(b.$1)),
    ghz24: g24,
    ghz5: g5,
    makers: _top({for (final e in vendorMacs.entries) e.key: e.value.length}, 10),
  );
}

class DroneMetrics {
  const DroneMetrics({
    required this.reports,
    required this.drones,
    required this.live,
    required this.maxAlt,
    required this.maxAgl,
    required this.maxSpeed,
    required this.bestRssi,
    required this.series,
    required this.byNode,
    required this.summaries,
  });

  final int reports;
  final int drones;
  final int live;
  final int? maxAlt;
  final int? maxAgl;
  final int? maxSpeed;
  final int? bestRssi;
  final List<int> series;
  final List<(String, int)> byNode;
  final List<DroneSummary> summaries;
}

/// Summarizes Remote ID [reports] from the span ending at [toMs]; a drone is live when heard within [droneLiveWindow] of [now].
DroneMetrics computeDroneMetrics(
  Iterable<DroneReport> reports, {
  required MetricsRange range,
  required int toMs,
  required DateTime now,
  String Function(String node)? nodeLabel,
  int top = 8,
}) {
  final fromMs = toMs - range.span.inMilliseconds;
  final bucketMs = range.bucket.inMilliseconds;
  final series = List<int>.filled(range.buckets, 0);
  final byNode = <String, int>{};
  final inSpan = <DroneReport>[];
  int? maxAlt, maxAgl, maxSpeed, bestRssi;
  int? higher(int? a, int? b) => b == null ? a : (a == null || b > a ? b : a);
  for (final r in reports) {
    final at = r.ts.millisecondsSinceEpoch;
    if (at < fromMs || at > toMs) continue;
    inSpan.add(r);
    series[((at - fromMs) ~/ bucketMs).clamp(0, series.length - 1)]++;
    final node = r.node.isEmpty ? 'This board' : (nodeLabel != null ? nodeLabel(r.node) : r.node);
    byNode[node] = (byNode[node] ?? 0) + 1;
    maxAlt = higher(maxAlt, r.alt);
    maxAgl = higher(maxAgl, r.height);
    maxSpeed = higher(maxSpeed, r.speed);
    if (r.rssi != null && r.rssi != 0) bestRssi = higher(bestRssi, r.rssi);
  }
  final summaries = summarizeDrones(inSpan, now);
  return DroneMetrics(
    reports: inSpan.length,
    drones: summaries.length,
    live: summaries.where((d) => d.live).length,
    maxAlt: maxAlt,
    maxAgl: maxAgl,
    maxSpeed: maxSpeed,
    bestRssi: bestRssi,
    series: series,
    byNode: _top(byNode, top),
    summaries: summaries,
  );
}
