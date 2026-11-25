// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AssistantGrant {
  devices('devices', 'DEVICES', 'Detections: devices seen, alerts, names, watchlist', ''),
  drones('drones', 'DRONES', 'Remote ID drones and pilots', ''),
  wardrive('wardrive', 'WARDRIVE', 'Wardrive counts and sightings', ''),
  mesh('mesh', 'MESH', 'Mesh nodes: status, firmware, signal', ''),
  files('files', 'CAPTURES', 'Saved PCAP capture files: names and sizes', ''),
  loc(
    'loc',
    'LOCATION',
    'Positions (sightings, drones and pilots, nodes). Off: every position is taken out of what the model is sent',
    'Positions go to the model you connect: where you, your nodes, the devices you saw and the drones and their pilots were.',
  ),
  control(
    'control',
    'CONTROL',
    'Change things: turn engines on or off, start or stop a capture, restart the board, name devices',
    'The model can ask for changes. Each change that reaches the board still waits for your OK, one call at a time.',
  ),
  danger(
    'danger',
    'IRREVERSIBLE',
    'Factory reset and wiping the board\'s saved Wi-Fi login',
    'The model can ask to erase the board\'s settings or its saved Wi-Fi login. Each call still waits for your OK.',
  );

  const AssistantGrant(this.id, this.label, this.summary, this.warning);
  final String id;
  final String label;
  final String summary;
  final String warning;

  bool get needsConfirmToEnable => warning.isNotEmpty;

  static AssistantGrant? byId(String id) {
    for (final g in values) {
      if (g.id == id) return g;
    }
    return null;
  }
}

class AssistantAccess {
  const AssistantAccess({this.on = false, this.granted = const {}});
  final bool on;
  final Set<AssistantGrant> granted;

  bool has(AssistantGrant g) => on && granted.contains(g);

  AssistantAccess copyWith({bool? on, Set<AssistantGrant>? granted}) =>
      AssistantAccess(on: on ?? this.on, granted: granted ?? this.granted);
}

class AssistantAccessNotifier extends StateNotifier<AssistantAccess> {
  AssistantAccessNotifier() : super(const AssistantAccess()) {
    _load();
  }

  static const keyOn = 'assistant_on';
  static String keyGrant(AssistantGrant g) => 'assistant_grant.${g.id}';
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed) return;
    state = AssistantAccess(
      on: p.getBool(keyOn) ?? false,
      granted: {for (final g in AssistantGrant.values) if (p.getBool(keyGrant(g)) ?? false) g},
    );
  }

  Future<void> setOn(bool on) async {
    _changed = true;
    state = state.copyWith(on: on);
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyOn, on);
  }

  Future<void> setGrant(AssistantGrant g, bool on) async {
    _changed = true;
    final next = {...state.granted};
    on ? next.add(g) : next.remove(g);
    state = state.copyWith(granted: next);
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyGrant(g), on);
  }
}

final assistantAccessProvider =
    StateNotifierProvider<AssistantAccessNotifier, AssistantAccess>((ref) => AssistantAccessNotifier());

const locationOff = '[location off]';

final _keyedPosition =
    RegExp(r'"([A-Za-z_]*(?:lat|lon|lng|latitude|longitude)[A-Za-z_]*)"\s*:\s*-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?');
final _pairPosition = RegExp(r'(?<![\w.])-?\d{1,2}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}(?![\w.])');
final _longDecimal = RegExp(r'(?<![\w.])-?\d{1,3}\.\d{5,}(?![\w])');

String hidePositions(String s) => s
    .replaceAllMapped(_keyedPosition, (m) => '"${m[1]}":"$locationOff"')
    .replaceAll(_pairPosition, locationOff)
    .replaceAll(_longDecimal, locationOff);
