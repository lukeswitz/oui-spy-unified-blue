// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:oui_spy/core/ble/ble_protocol.dart';

String formatFwVersion(int v) => '${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';

String formatUptime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  if (h < 48) return '${h}h ${m % 60}m';
  return '${h ~/ 24}d ${h % 24}h';
}

String formatAge(int seconds) {
  if (seconds < 10) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m ago';
  return '${m ~/ 60}h ago';
}

String filterCountText(MeshNodeDetail d) {
  final total = d.filterMacs + d.filterUuids;
  return total == 1 ? '1 filter' : '$total filters';
}

/// One short line for a node row: build, filters, uptime.
String nodeDetailSummary(MeshNodeDetail d) =>
    '${filterCountText(d)}  ·  up ${formatUptime(d.uptimeS)}';

String filterRefusalText(int status) => switch (status) {
      1 => 'detector not on this build',
      2 => 'detector turned off for it',
      3 => 'list too long for it',
      _ => 'refused',
    };

/// A node's own result line, such as "watchlist: 6 filters" or "watchlist refused: list too long for it".
String nodeFilterResultText(MeshFilterResult r) => r.status == 0
    ? 'watchlist: ${r.filterMacs + r.filterUuids} ${r.filterMacs + r.filterUuids == 1 ? 'filter' : 'filters'}'
    : 'watchlist refused: ${filterRefusalText(r.status)}';

/// "On 3 of 4 nodes; NODE2 refused (list too long for it)". Null when no node was expected to answer.
String? filterPushSummary(MeshFilterPush p, String Function(String id) label) {
  if (p.expected == 0) return null;
  final took = p.results.where((r) => r.status == 0).length;
  final parts = <String>[
    'On $took of ${p.expected} ${p.expected == 1 ? 'node' : 'nodes'}',
    for (final r in p.results)
      if (r.status != 0) '${label(r.id)} refused (${filterRefusalText(r.status)})',
  ];
  final silent = p.expected - p.results.length;
  if (silent > 0) parts.add('$silent did not answer');
  return parts.join('; ');
}

enum SignalLevel { strong, good, weak, poor, heard }

/// Strong from -60 dBm up, good from -70, weak from -80, poor below; heard when a node hears a peer but cannot measure it.
SignalLevel signalLevel(int? rssi) {
  if (rssi == null) return SignalLevel.heard;
  if (rssi >= -60) return SignalLevel.strong;
  if (rssi >= -70) return SignalLevel.good;
  if (rssi >= -80) return SignalLevel.weak;
  return SignalLevel.poor;
}

String signalLevelName(SignalLevel l) => switch (l) {
      SignalLevel.strong => 'Strong',
      SignalLevel.good => 'Good',
      SignalLevel.weak => 'Weak',
      SignalLevel.poor => 'Poor',
      SignalLevel.heard => 'Heard',
    };

/// Grid axes: every node that reports, then every peer that is heard but does not report.
List<String> signalGridIds(List<MeshSignalRow> rows) {
  final ids = <String>[for (final r in rows) r.id];
  for (final r in rows) {
    for (final h in r.hears) {
      if (!ids.contains(h.id)) ids.add(h.id);
    }
  }
  return ids;
}

/// What [row] hears of [col]: null when it does not hear it, otherwise the reading.
({int? rssi})? signalCell(List<MeshSignalRow> rows, String row, String col) {
  for (final r in rows) {
    if (r.id != row) continue;
    for (final h in r.hears) {
      if (h.id == col) return (rssi: h.rssi);
    }
  }
  return null;
}

/// The lines shown in a node's dialog after a status read.
List<String> nodeDetailLines(MeshNodeDetail d, int ageS) => [
      'Build ${formatFwVersion(d.fwVersion)}',
      'Filters ${d.filterMacs} MAC, ${d.filterUuids} service UUID',
      'Uptime ${formatUptime(d.uptimeS)}',
      'Hears ${d.peerCount} ${d.peerCount == 1 ? 'peer' : 'peers'}',
      'Read ${formatAge(ageS)}',
    ];
