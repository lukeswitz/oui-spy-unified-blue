// Copyright (c) 2026 Luke Switzer
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

/// The lines shown in a node's dialog after a status read.
List<String> nodeDetailLines(MeshNodeDetail d, int ageS) => [
      'Build ${formatFwVersion(d.fwVersion)}',
      'Filters ${d.filterMacs} MAC, ${d.filterUuids} service UUID',
      'Uptime ${formatUptime(d.uptimeS)}',
      'Hears ${d.peerCount} ${d.peerCount == 1 ? 'peer' : 'peers'}',
      'Read ${formatAge(ageS)}',
    ];
