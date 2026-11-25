// Copyright (c) 2026 Luke Switzer
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where you put each mesh node, by node ID. Kept on this phone.
class NodePositionsNotifier extends StateNotifier<Map<String, LatLng>> {
  NodePositionsNotifier() : super(const {}) {
    _load();
  }

  static const _key = 'node_positions';
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed) return;
    final raw = p.getString(_key);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final e in m.entries)
          e.key: LatLng((e.value['lat'] as num).toDouble(), (e.value['lon'] as num).toDouble()),
      };
    } on FormatException {
      state = const {};
    } on TypeError {
      state = const {};
    }
  }

  Future<void> _save() async {
    _changed = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        for (final e in state.entries) e.key: {'lat': e.value.latitude, 'lon': e.value.longitude},
      }),
    );
  }

  Future<void> place(String nodeId, LatLng at) async {
    state = {...state, nodeId: at};
    await _save();
  }

  Future<void> clear(String nodeId) async {
    if (!state.containsKey(nodeId)) return;
    state = {for (final e in state.entries) if (e.key != nodeId) e.key: e.value};
    await _save();
  }
}

final nodePositionsProvider =
    StateNotifierProvider<NodePositionsNotifier, Map<String, LatLng>>((ref) => NodePositionsNotifier());
