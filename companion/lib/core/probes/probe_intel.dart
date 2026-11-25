// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

const int probeBand24 = 1;
const int probeBand5 = 2;

const String randomMakerLabel = 'Random address, maker hidden';
const String unregisteredMakerLabel = 'Unregistered prefix';

class ProbeDev {
  ProbeDev({
    required this.mac,
    required this.first,
    required this.last,
    this.count = 0,
    this.rssi = 0,
    this.bands = 0,
    Map<String, int>? ssids,
    Map<String, int>? ssidLast,
  })  : ssids = ssids ?? <String, int>{},
        ssidLast = ssidLast ?? <String, int>{};

  final String mac;
  int first;
  int last;
  int count;
  int rssi;
  int bands;
  final Map<String, int> ssids;
  final Map<String, int> ssidLast;

  bool get asksByName => ssids.isNotEmpty;
  bool get isRandom => isRandomMac(mac);

  Map<String, dynamic> toJson() => {
        'mac': mac,
        'first': first,
        'last': last,
        'count': count,
        'rssi': rssi,
        'bands': bands,
        'ssids': ssids,
        'ssidLast': ssidLast,
      };

  static ProbeDev? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final mac = raw['mac'];
    final first = raw['first'];
    final last = raw['last'];
    if (mac is! String || first is! int || last is! int) return null;
    Map<String, int> ints(Object? v) => v is Map
        ? {
            for (final e in v.entries)
              if (e.key is String && e.value is int) e.key as String: e.value as int,
          }
        : <String, int>{};
    return ProbeDev(
      mac: mac,
      first: first,
      last: last,
      count: raw['count'] is int ? raw['count'] as int : 0,
      rssi: raw['rssi'] is int ? raw['rssi'] as int : 0,
      bands: raw['bands'] is int ? raw['bands'] as int : 0,
      ssids: ints(raw['ssids']),
      ssidLast: ints(raw['ssidLast']),
    );
  }
}

String normalizeMac(String mac) {
  final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length != 12) return mac.trim().toUpperCase();
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
}

bool isRandomMac(String mac) {
  final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  if (hex.length < 2) return false;
  return ((int.tryParse(hex.substring(0, 2), radix: 16) ?? 0) & 0x02) != 0;
}

int bandOfChannel(int channel) {
  if (channel >= 1 && channel <= 14) return probeBand24;
  if (channel >= 32) return probeBand5;
  return 0;
}

int bandOfFreq(int mhz) {
  if (mhz >= 2400 && mhz < 2500) return probeBand24;
  if (mhz >= 4900 && mhz < 5950) return probeBand5;
  return 0;
}

String bandsLabel(int bands) => switch (bands & 3) {
      1 => '2.4 GHz',
      2 => '5 GHz',
      3 => '2.4 + 5 GHz',
      _ => '',
    };

String? cleanSsid(List<int> raw) {
  if (raw.isEmpty || raw.every((b) => b == 0)) return null;
  final s = utf8.decode(raw, allowMalformed: true).replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
  return s.isEmpty ? null : s;
}

final RegExp _makerSuffix = RegExp(
  r'[\s,]+(inc\.?|incorporated|co\.?,?\s*ltd\.?|co\.?|ltd\.?|limited|corporation|corp\.?|llc|gmbh|ag|s\.a\.?|b\.v\.?|pty|plc|oy)$',
  caseSensitive: false,
);

String shortMaker(String maker) {
  var s = maker.trim();
  for (var i = 0; i < 3; i++) {
    final next = s.replaceFirst(_makerSuffix, '');
    if (next == s || next.isEmpty) break;
    s = next;
  }
  return s;
}

String makerOf(String mac, String? Function(String mac) lookup) {
  if (isRandomMac(mac)) return randomMakerLabel;
  final v = lookup(mac);
  return v == null || v.isEmpty ? unregisteredMakerLabel : v;
}

class ProbeTwins {
  ProbeTwins(Iterable<ProbeDev> devs, {this.minNetworks = 2}) {
    for (final d in devs) {
      final sig = signature(d, minNetworks);
      if (sig == null) continue;
      (_bySig[sig] ??= <String>[]).add(d.mac);
    }
  }

  final int minNetworks;
  final Map<String, List<String>> _bySig = {};

  static String? signature(ProbeDev d, int minNetworks) {
    if (d.ssids.length < minNetworks) return null;
    final names = d.ssids.keys.toList()..sort();
    return jsonEncode(names);
  }

  int count(ProbeDev d) {
    final sig = signature(d, minNetworks);
    if (sig == null) return 0;
    final n = _bySig[sig]?.length ?? 0;
    return n > 0 ? n - 1 : 0;
  }
}
