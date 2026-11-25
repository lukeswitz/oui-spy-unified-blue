// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DroneTag { friendly, neutral, suspicious, hostile }

extension DroneTagX on DroneTag {
  String get label => switch (this) {
        DroneTag.friendly => 'Friendly',
        DroneTag.neutral => 'Neutral',
        DroneTag.suspicious => 'Suspicious',
        DroneTag.hostile => 'Hostile',
      };

  Color get color => switch (this) {
        DroneTag.friendly => const Color(0xFF3DDC84),
        DroneTag.neutral => const Color(0xFF5AA9E6),
        DroneTag.suspicious => const Color(0xFFE6A85A),
        DroneTag.hostile => const Color(0xFFE5484D),
      };

  IconData get icon => switch (this) {
        DroneTag.friendly => Icons.shield_outlined,
        DroneTag.neutral => Icons.remove_circle_outline,
        DroneTag.suspicious => Icons.help_outline,
        DroneTag.hostile => Icons.dangerous_outlined,
      };
}

class DroneTagsNotifier extends StateNotifier<Map<String, DroneTag>> {
  DroneTagsNotifier() : super(const {}) {
    _load();
  }

  static const _key = 'drone_tags';
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || _changed) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = <String, DroneTag>{};
      json.forEach((id, name) {
        for (final t in DroneTag.values) {
          if (t.name == name) loaded[id] = t;
        }
      });
      if (!_changed) state = loaded;
    } on FormatException {
      return;
    }
  }

  Future<void> set(String id, DroneTag? tag) async {
    _changed = true;
    final next = {...state};
    if (tag == null) {
      next.remove(id);
    } else {
      next[id] = tag;
    }
    state = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key, jsonEncode({for (final e in next.entries) e.key: e.value.name}));
  }
}

final droneTagsProvider =
    StateNotifierProvider<DroneTagsNotifier, Map<String, DroneTag>>(
        (ref) => DroneTagsNotifier());
