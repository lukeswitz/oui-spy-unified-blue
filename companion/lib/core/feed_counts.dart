// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

const liveWindowMs = 60 * 1000;

class LiveSighting {
  const LiveSighting(this.key, this.atMs, {this.drone = false});
  final String key;
  final int atMs;
  final bool drone;
}

class FeedCounts {
  const FeedCounts({
    this.nodesOnline = 0,
    this.nodesTotal = 0,
    this.heardNow = 0,
    this.liveDrones = 0,
    this.today = 0,
    this.unread = 0,
    this.macsKept = 0,
    this.hourly = const [],
  });

  final int nodesOnline;
  final int nodesTotal;
  final int heardNow;
  final int liveDrones;
  final int today;
  final int unread;
  final int macsKept;
  final List<int> hourly;

  int get hourlyTotal => hourly.fold(0, (a, b) => a + b);
}

DateTime startOfLocalDay(DateTime now) => DateTime(now.year, now.month, now.day);

FeedCounts buildFeedCounts({
  required int nowMs,
  required int nodesOnline,
  required int nodesTotal,
  required Iterable<LiveSighting> live,
  required int unread,
  required int macsKept,
  required int storedToday,
  required List<int> hourly,
}) {
  final now = <String>{};
  final drones = <String>{};
  for (final s in live) {
    if (nowMs - s.atMs > liveWindowMs || s.atMs > nowMs + liveWindowMs) continue;
    now.add(s.key);
    if (s.drone) drones.add(s.key);
  }
  return FeedCounts(
    nodesOnline: nodesOnline,
    nodesTotal: nodesTotal,
    heardNow: now.length,
    liveDrones: drones.length,
    today: storedToday < now.length ? now.length : storedToday,
    unread: unread,
    macsKept: macsKept,
    hourly: hourly,
  );
}
