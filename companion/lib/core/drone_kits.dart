// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum KitRole {
  controller('Controller'),
  goggles('Goggles'),
  dock('Dock'),
  rid('Remote ID module'),
  dronewifi("Drone's own Wi-Fi"),
  phone('Pilot phone or tablet'),
  other('Other part');

  const KitRole(this.label);
  final String label;

  static KitRole? byName(String? n) {
    for (final r in values) {
      if (r.name == n) return r;
    }
    return null;
  }
}

class KitSignRule {
  const KitSignRule({
    required this.what,
    required this.source,
    this.role,
    this.bleName,
    this.wifiName,
  });

  final String what;
  final String source;
  final KitRole? role;
  final String? bleName;
  final String? wifiName;
}

const kitSignRules = <KitSignRule>[
  KitSignRule(
    what: 'a DJI Osmo camera, no part of a drone kit',
    bleName: r'^Osmo',
    wifiName: r'^OSMO_',
    source: 'lib-osmo-ble PROTOCOL.md (Osmo Pocket 3 by name); Kismet conf/kismet_uav.conf.yaml (OSMO_)',
  ),
  KitSignRule(
    what: "a Parrot Bebop or AR.Drone's own Wi-Fi",
    role: KitRole.dronewifi,
    wifiName: r'^(BebopDrone|Bebop2|ardrone2?)',
    source: 'Kismet conf/kismet_uav.conf.yaml; Parrot manuals',
  ),
  KitSignRule(
    what: "a Parrot ANAFI drone's own Wi-Fi",
    role: KitRole.dronewifi,
    wifiName: r'^anafi',
    source: 'Parrot ANAFI USA user manual; Parrot developer forum',
  ),
  KitSignRule(
    what: 'an ArduRemoteID Remote ID module',
    role: KitRole.rid,
    bleName: r'^ArduRemoteID_',
    source: 'ArduPilot/ArduRemoteID RemoteIDModule/BLE_TX.cpp',
  ),
  KitSignRule(
    what: "an ArduRemoteID Remote ID module's setup network",
    role: KitRole.rid,
    wifiName: r'^RID_[0-9a-f]{12}$',
    source: 'ArduPilot/ArduRemoteID RemoteIDModule/parameters.cpp, WiFi_TX.cpp, README.md',
  ),
  KitSignRule(
    what: 'a BlueMark DroneBeacon Remote ID module',
    role: KitRole.rid,
    bleName: r'^DroneBeacon_[A-Z0-9]{4}$',
    wifiName: r'^DroneBeacon_[A-Z0-9]{4}$',
    source: 'BlueMark dronebeacon_transponder_history.txt',
  ),
  KitSignRule(
    what: 'a Parrot SkyController',
    role: KitRole.controller,
    wifiName: r'^SkyController',
    source: 'Parrot SkyController manual; Kismet conf/kismet_uav.conf.yaml',
  ),
  KitSignRule(
    what: "a DJI Phantom 3 Standard's remote controller (the Wi-Fi is the controller's)",
    role: KitRole.controller,
    wifiName: r'^PHANTOM3_',
    source: 'DJI Phantom 3 Standard quick start guide; Kismet conf/kismet_uav.conf.yaml',
  ),
  KitSignRule(
    what: "a DJI Spark's remote controller (it runs the phone's Wi-Fi)",
    role: KitRole.controller,
    wifiName: r'^Spark-RC-',
    source: 'Kismet conf/kismet_uav.conf.yaml; DJI Spark remote controller guide',
  ),
];

class KitSignMatch {
  const KitSignMatch(this.rule, this.reason);
  final KitSignRule rule;
  final String reason;
}

KitSignMatch? kitSignature({String bleName = '', String wifiName = ''}) {
  for (final rule in kitSignRules) {
    final b = rule.bleName;
    if (b != null && bleName.isNotEmpty && RegExp(b).hasMatch(bleName)) {
      return KitSignMatch(rule, 'its Bluetooth name "$bleName" is ${rule.what}');
    }
    final w = rule.wifiName;
    if (w != null && wifiName.isNotEmpty && RegExp(w).hasMatch(wifiName)) {
      return KitSignMatch(rule, 'its network "$wifiName" is ${rule.what}');
    }
  }
  return null;
}

class KitMember {
  const KitMember({required this.mac, required this.role, this.label = ''});

  final String mac;
  final KitRole role;
  final String label;

  Map<String, dynamic> toJson() =>
      {'mac': mac, 'role': role.name, if (label.isNotEmpty) 'label': label};

  static KitMember? fromJson(Map<String, dynamic> j) {
    final mac = j['mac'] as String?;
    final role = KitRole.byName(j['role'] as String?);
    if (mac == null || role == null) return null;
    return KitMember(mac: mac, role: role, label: j['label'] as String? ?? '');
  }
}

String kitMacKey(String mac) => mac.toUpperCase();

class DroneKitsNotifier extends StateNotifier<Map<String, List<KitMember>>> {
  DroneKitsNotifier() : super(const {}) {
    _load();
  }

  static const _key = 'drone_kits';
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || _changed) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = <String, List<KitMember>>{};
      json.forEach((id, list) {
        final members = <KitMember>[];
        for (final m in list as List<dynamic>) {
          final km = KitMember.fromJson(m as Map<String, dynamic>);
          if (km != null) members.add(km);
        }
        if (members.isNotEmpty) loaded[id] = members;
      });
      if (!_changed) state = loaded;
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key,
        jsonEncode({
          for (final e in state.entries)
            e.key: [for (final m in e.value) m.toJson()],
        }));
  }

  Future<void> add(String droneId, KitMember member) async {
    _changed = true;
    final key = kitMacKey(member.mac);
    final next = <String, List<KitMember>>{
      for (final e in state.entries)
        e.key: [
          for (final m in e.value)
            if (kitMacKey(m.mac) != key) m,
        ],
    };
    next[droneId] = [...?next[droneId], member];
    next.removeWhere((_, v) => v.isEmpty);
    state = next;
    await _save();
  }

  Future<void> remove(String droneId, String mac) async {
    _changed = true;
    final key = kitMacKey(mac);
    final next = {...state};
    next[droneId] = [
      for (final m in next[droneId] ?? const <KitMember>[])
        if (kitMacKey(m.mac) != key) m,
    ];
    if (next[droneId]!.isEmpty) next.remove(droneId);
    state = next;
    await _save();
  }

  String? droneOf(String mac) {
    final key = kitMacKey(mac);
    for (final e in state.entries) {
      if (e.value.any((m) => kitMacKey(m.mac) == key)) return e.key;
    }
    return null;
  }
}

final droneKitsProvider =
    StateNotifierProvider<DroneKitsNotifier, Map<String, List<KitMember>>>(
        (ref) => DroneKitsNotifier());

class KitSighting {
  const KitSighting({required this.ts, this.point, this.node = ''});
  final DateTime ts;
  final LatLng? point;
  final String node;
}

class KitDevice {
  const KitDevice({
    required this.mac,
    required this.sightings,
    this.bleName = '',
    this.wifiName = '',
  });

  final String mac;
  final List<KitSighting> sightings;
  final String bleName;
  final String wifiName;

  String get label => bleName.isNotEmpty
      ? bleName
      : wifiName.isNotEmpty
          ? wifiName
          : mac.toUpperCase();
}

class KitSuggestion {
  const KitSuggestion({
    required this.device,
    required this.role,
    required this.score,
    required this.reasons,
  });

  final KitDevice device;
  final KitRole? role;
  final double score;
  final List<String> reasons;
}

const kitFlightPad = Duration(minutes: 10);
const kitNearMeters = 300.0;
const kitMinScore = 0.6;
const kitMinSightings = 3;

List<KitSuggestion> kitSuggest({
  required List<DroneFlight> flights,
  required Iterable<KitDevice> devices,
  Set<String> skip = const {},
  int limit = 5,
}) {
  if (flights.isEmpty) return const [];
  final anchors = <LatLng>[
    for (final f in flights) ...[
      if (f.lastPilotPoint != null) f.lastPilotPoint!,
      if (f.path.isNotEmpty) f.path.first,
    ],
  ];
  final out = <KitSuggestion>[];
  for (final dev in devices) {
    if (skip.contains(kitMacKey(dev.mac)) || dev.sightings.isEmpty) continue;
    final sign = kitSignature(bleName: dev.bleName, wifiName: dev.wifiName);
    if (sign != null && sign.rule.role == null) continue;
    final reasons = <String>[];
    var score = 0.0;
    if (sign != null) {
      reasons.add(sign.reason);
      score += 0.6;
    }
    final inFlight = <int>{};
    var around = 0;
    for (final s in dev.sightings) {
      for (var i = 0; i < flights.length; i++) {
        final f = flights[i];
        if (!s.ts.isBefore(f.start.subtract(kitFlightPad)) &&
            !s.ts.isAfter(f.end.add(kitFlightPad))) {
          inFlight.add(i);
          around++;
          break;
        }
      }
    }
    final share = around / dev.sightings.length;
    final coverage = inFlight.length / flights.length;
    if (inFlight.isNotEmpty && share >= 0.5 && dev.sightings.length >= kitMinSightings) {
      score += 0.4 * share + 0.2 * coverage;
      reasons.add(flights.length == 1
          ? 'heard during its flight'
          : 'heard in ${inFlight.length} of its ${flights.length} flights');
      if (share >= 0.9) reasons.add('heard almost only around its flights');
    }
    double? nearest;
    for (final s in dev.sightings) {
      final p = s.point;
      if (p == null) continue;
      for (final a in anchors) {
        final m = metersBetween(p, a);
        if (nearest == null || m < nearest) nearest = m;
      }
    }
    if (nearest != null && nearest <= kitNearMeters && inFlight.isNotEmpty) {
      score += 0.15;
      reasons.add('heard within ${nearest.round()} m of its pilot or take-off');
    }
    if (sign != null || score >= kitMinScore) {
      out.add(KitSuggestion(
        device: dev,
        role: sign?.rule.role,
        score: score.clamp(0.0, 1.0),
        reasons: reasons,
      ));
    }
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out.take(limit).toList();
}
