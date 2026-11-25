// Copyright (c) 2026 Luke Switzer
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceNote {
  const DeviceNote({this.name = '', this.group = '', this.notes = ''});

  final String name;
  final String group;
  final String notes;

  bool get isEmpty => name.trim().isEmpty && group.trim().isEmpty && notes.trim().isEmpty;

  Map<String, String> toJson() => {'name': name, 'group': group, 'notes': notes};

  factory DeviceNote.fromJson(Map<String, dynamic> j) => DeviceNote(
        name: (j['name'] as String?) ?? '',
        group: (j['group'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
      );
}

/// Your own name, group and notes for a device, by MAC, kept on this phone.
class DeviceNotesNotifier extends StateNotifier<Map<String, DeviceNote>> {
  DeviceNotesNotifier() : super(const {}) {
    _load();
  }

  static const _key = 'device_notes';
  static Map<String, DeviceNote> current = const {};
  bool _changed = false;

  static String keyOf(String mac) => mac.trim().toUpperCase();

  static String? nameFor(String mac) {
    final n = current[keyOf(mac)]?.name.trim() ?? '';
    return n.isEmpty ? null : n;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed) return;
    final raw = p.getString(_key);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      state = current = {
        for (final e in m.entries) e.key: DeviceNote.fromJson(Map<String, dynamic>.from(e.value as Map)),
      };
    } on FormatException {
      state = current = const {};
    }
  }

  Future<void> set(String mac, DeviceNote note) async {
    _changed = true;
    final next = Map<String, DeviceNote>.from(state);
    if (note.isEmpty) {
      next.remove(keyOf(mac));
    } else {
      next[keyOf(mac)] = note;
    }
    state = current = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}));
  }

  List<String> get groups => {for (final n in state.values) if (n.group.trim().isNotEmpty) n.group.trim()}.toList()..sort();
}

final deviceNotesProvider =
    StateNotifierProvider<DeviceNotesNotifier, Map<String, DeviceNote>>((ref) => DeviceNotesNotifier());
