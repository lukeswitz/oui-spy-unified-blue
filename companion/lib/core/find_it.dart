// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io' show Platform;

const findItFarMs = 1400;
const findItNearMs = 90;
const findItBoardFresh = Duration(seconds: 5);
const findItNodeFresh = Duration(seconds: 20);

/// 0 at -95 dBm and below, 1 at -35 dBm and above.
double findItNear(int rssi) => ((rssi + 95) / 60).clamp(0.0, 1.0);

/// Time between pulses: 1400 ms when the signal is weak, quickening to 90 ms as it climbs.
Duration findItInterval(int? rssi) {
  if (rssi == null) return const Duration(milliseconds: findItFarMs);
  final n = findItNear(rssi);
  final ms = findItFarMs - n * n * (findItFarMs - findItNearMs);
  return Duration(milliseconds: ms.round());
}

bool findItHapticsAvailable() => Platform.isAndroid || Platform.isIOS;

typedef FindItHeard = ({int rssi, DateTime at});

class FindItReading {
  const FindItReading({required this.rssi, required this.nodeId});
  final int rssi;
  final String nodeId;
}

/// The strongest fresh reading of the hunted device: the hunting board's own, or any node that heard it.
FindItReading? pickFindItReading({
  required int boardRssi,
  required int boardIntervalMs,
  required DateTime? boardAt,
  required String boardNodeId,
  required Map<String, FindItHeard> heard,
  required DateTime now,
}) {
  FindItReading? best;
  if (boardAt != null &&
      boardIntervalMs != 0 &&
      now.difference(boardAt) <= findItBoardFresh) {
    best = FindItReading(rssi: boardRssi, nodeId: boardNodeId);
  }
  for (final e in heard.entries) {
    if (now.difference(e.value.at) > findItNodeFresh) continue;
    if (best == null || e.value.rssi > best.rssi) {
      best = FindItReading(rssi: e.value.rssi, nodeId: e.key);
    }
  }
  return best;
}
