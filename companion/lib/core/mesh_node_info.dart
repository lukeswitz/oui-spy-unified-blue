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

MeshChannelState channelState(MeshChannelStatus s) => MeshChannelState.values[s.state];

bool channelChangeRunning(MeshChannelStatus? s) =>
    s != null && (channelState(s) == MeshChannelState.confirming || channelState(s) == MeshChannelState.switching);

/// The status line for the latest channel change; null when there has been none.
String? channelChangeSummary(MeshChannelStatus s, String Function(String id) label) {
  final total = s.rows.length;
  final confirmed = s.rows.where((r) => r.confirmed).length;
  final followed = s.rows.where((r) => r.followed).length;
  return switch (channelState(s)) {
    MeshChannelState.idle => null,
    MeshChannelState.confirming => 'Asking the nodes to move to channel ${s.target}: $confirmed of $total confirmed',
    MeshChannelState.switching => 'Moving to channel ${s.target}: $confirmed of $total nodes confirmed',
    MeshChannelState.done => total == 0
        ? 'Moved to channel ${s.target}'
        : followed == total
            ? 'Moved to channel ${s.target}: all $total ${total == 1 ? 'node follows' : 'nodes follow'}'
            : 'Moved to channel ${s.target}: $followed of $total nodes follow; '
                '${s.rows.where((r) => !r.followed).map((r) => label(r.id)).join(', ')} will find the fleet again on its own',
    MeshChannelState.failed => 'Stayed on channel ${s.current}: '
        '${s.rows.where((r) => !r.confirmed).map((r) => label(r.id)).join(', ')} did not answer',
  };
}

/// The ids of the nodes that did not confirm a failed change; empty otherwise.
List<String> channelChangeUnanswered(MeshChannelStatus s) =>
    channelState(s) == MeshChannelState.failed ? [for (final r in s.rows) if (!r.confirmed) r.id] : const [];

/// A node's own result line for the latest change, or null when it was not part of one.
String? nodeChannelText(MeshChannelStatus? s, String id) {
  if (s == null) return null;
  MeshChannelRow? row;
  for (final r in s.rows) {
    if (r.id == id) row = r;
  }
  if (row == null) return null;
  return switch (channelState(s)) {
    MeshChannelState.idle => null,
    MeshChannelState.confirming || MeshChannelState.switching =>
      row.confirmed ? 'channel ${s.target}: confirmed' : 'channel ${s.target}: waiting',
    MeshChannelState.done => row.followed ? 'on channel ${s.target}' : 'not on channel ${s.target} yet',
    MeshChannelState.failed => row.confirmed ? 'channel move canceled' : 'did not answer the channel move',
  };
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

/// One entry per node a reporting node hears, in report order.
List<({String from, String to, int? rssi})> signalLinks(List<MeshSignalRow> rows) => [
      for (final r in rows)
        for (final h in r.hears)
          if (h.id != r.id) (from: r.id, to: h.id, rssi: h.rssi),
    ];

String signalLinkValue(int? rssi) => rssi == null ? 'Heard' : '$rssi dBm';

/// The lines shown in a node's dialog after a status read.
List<String> nodeDetailLines(MeshNodeDetail d, int ageS) => [
      'Build ${formatFwVersion(d.fwVersion)}',
      'Filters ${d.filterMacs} MAC, ${d.filterUuids} service UUID',
      'Uptime ${formatUptime(d.uptimeS)}',
      'Hears ${d.peerCount} ${d.peerCount == 1 ? 'peer' : 'peers'}',
      'Read ${formatAge(ageS)}',
    ];
