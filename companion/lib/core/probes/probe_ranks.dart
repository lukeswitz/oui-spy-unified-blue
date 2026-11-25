// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:oui_spy/core/probes/probe_intel.dart';

enum DevSort {
  networks('Most networks'),
  recent('Recent'),
  signal('Signal'),
  probes('Probes'),
  maker('Maker');

  const DevSort(this.label);
  final String label;
}

enum NetSort {
  devices('Most devices'),
  recent('Recent'),
  asked('Asked'),
  name('A-Z');

  const NetSort(this.label);
  final String label;
}

class NetRank {
  const NetRank({required this.name, required this.devices, required this.asked, required this.first, required this.last});
  final String name;
  final int devices;
  final int asked;
  final int first;
  final int last;
}

class NetSummary {
  const NetSummary({required this.makers});
  final List<(String, int)> makers;
}

bool _heardSince(ProbeDev d, int? sinceMs) => sinceMs == null || d.last >= sinceMs;

bool deviceMatches(ProbeDev d, String query, String Function(String mac) maker) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (d.mac.toLowerCase().contains(q)) return true;
  if (maker(d.mac).toLowerCase().contains(q)) return true;
  return d.ssids.keys.any((n) => n.toLowerCase().contains(q));
}

List<ProbeDev> rankDevices(
  Iterable<ProbeDev> devs, {
  required DevSort sort,
  required String Function(String mac) maker,
  String query = '',
  int? sinceMs,
  bool namedOnly = false,
}) {
  final out = [
    for (final d in devs)
      if (_heardSince(d, sinceMs) && (!namedOnly || d.asksByName) && deviceMatches(d, query, maker)) d,
  ];
  int byRecent(ProbeDev a, ProbeDev b) => b.last != a.last ? b.last.compareTo(a.last) : a.mac.compareTo(b.mac);
  int then(int primary, ProbeDev a, ProbeDev b) => primary != 0 ? primary : byRecent(a, b);
  out.sort(switch (sort) {
    DevSort.networks => (a, b) => then(b.ssids.length.compareTo(a.ssids.length), a, b),
    DevSort.recent => byRecent,
    DevSort.signal => (a, b) => then((b.rssi == 0 ? -999 : b.rssi).compareTo(a.rssi == 0 ? -999 : a.rssi), a, b),
    DevSort.probes => (a, b) => then(b.count.compareTo(a.count), a, b),
    DevSort.maker => (a, b) => then(maker(a.mac).toLowerCase().compareTo(maker(b.mac).toLowerCase()), a, b),
  });
  return out;
}

List<NetRank> rankNetworks(
  Iterable<ProbeDev> devs, {
  required NetSort sort,
  String query = '',
  int? sinceMs,
}) {
  final q = query.trim().toLowerCase();
  final acc = <String, ({int devices, int asked, int first, int last})>{};
  for (final d in devs) {
    if (!_heardSince(d, sinceMs)) continue;
    d.ssids.forEach((name, n) {
      final seen = d.ssidLast[name] ?? d.last;
      final cur = acc[name];
      acc[name] = cur == null
          ? (devices: 1, asked: n, first: seen, last: seen)
          : (
              devices: cur.devices + 1,
              asked: cur.asked + n,
              first: seen < cur.first ? seen : cur.first,
              last: seen > cur.last ? seen : cur.last,
            );
    });
  }
  final out = [
    for (final e in acc.entries)
      if (q.isEmpty || e.key.toLowerCase().contains(q))
        NetRank(name: e.key, devices: e.value.devices, asked: e.value.asked, first: e.value.first, last: e.value.last),
  ];
  int byName(NetRank a, NetRank b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  int then(int primary, NetRank a, NetRank b) => primary != 0 ? primary : byName(a, b);
  out.sort(switch (sort) {
    NetSort.devices => (a, b) => then(b.devices.compareTo(a.devices), a, b),
    NetSort.recent => (a, b) => then(b.last.compareTo(a.last), a, b),
    NetSort.asked => (a, b) => then(b.asked.compareTo(a.asked), a, b),
    NetSort.name => byName,
  });
  return out;
}

List<ProbeDev> askersOf(String ssid, Iterable<ProbeDev> devs, {int? sinceMs}) {
  final out = [
    for (final d in devs)
      if (d.ssids.containsKey(ssid) && _heardSince(d, sinceMs)) d,
  ];
  out.sort((a, b) => (b.ssidLast[ssid] ?? b.last).compareTo(a.ssidLast[ssid] ?? a.last));
  return out;
}

List<(String, int)> namesOf(ProbeDev d) {
  final out = [for (final e in d.ssids.entries) (e.key, e.value)];
  out.sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
  return out;
}

NetSummary summarizeNetwork(Iterable<ProbeDev> askers, String Function(String mac) maker) {
  final counts = <String, int>{};
  for (final d in askers) {
    final m = isRandomMac(d.mac) ? randomMakerLabel : shortMaker(maker(d.mac));
    counts[m] = (counts[m] ?? 0) + 1;
  }
  final makers = [for (final e in counts.entries) (e.key, e.value)]
    ..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return NetSummary(makers: makers);
}
