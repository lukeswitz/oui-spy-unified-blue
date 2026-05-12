import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IgnoreType {
  ssid('SSID'),
  mac('MAC'),
  oui('OUI');

  const IgnoreType(this.label);
  final String label;
}

enum IgnoreScope {
  both('WiFi + BLE'),
  wifi('WiFi only'),
  ble('BLE only');

  const IgnoreScope(this.label);
  final String label;
}

class IgnoreEntry {
  IgnoreEntry({
    required this.type,
    required this.value,
    this.scope = IgnoreScope.both,
    this.label = '',
    this.enabled = true,
  });

  final IgnoreType type;
  final String value;
  IgnoreScope scope;
  String label;
  bool enabled;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': value,
        'scope': scope.name,
        'label': label,
        'enabled': enabled,
      };

  factory IgnoreEntry.fromJson(Map<String, dynamic> json) {
    return IgnoreEntry(
      type: IgnoreType.values.byName(json['type'] as String),
      value: json['value'] as String,
      scope: _parseScope(json['scope']),
      label: json['label'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static IgnoreScope _parseScope(dynamic raw) {
    if (raw is String) {
      for (final s in IgnoreScope.values) {
        if (s.name == raw) return s;
      }
    }
    return IgnoreScope.both;
  }

  static String normalize(IgnoreType type, String raw) {
    final trimmed = raw.trim();
    if (type == IgnoreType.ssid) return trimmed;
    final hex = trimmed.toLowerCase().replaceAll(RegExp(r'[:\-.]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < hex.length; i++) {
      if (i > 0 && i.isEven) buf.write(':');
      buf.write(hex[i]);
    }
    return buf.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IgnoreEntry && type == other.type && value == other.value;

  @override
  int get hashCode => Object.hash(type, value);
}

class IgnoreListState extends ChangeNotifier {
  IgnoreListState() {
    _load();
  }

  static const _prefsKey = 'privacy_ignore_list';

  final List<IgnoreEntry> _entries = [];
  List<IgnoreEntry> get entries => List.unmodifiable(_entries);

  void add(IgnoreEntry entry) {
    if (_entries.contains(entry)) return;
    _entries.add(entry);
    notifyListeners();
    _save();
  }

  void remove(IgnoreEntry entry) {
    _entries.remove(entry);
    notifyListeners();
    _save();
  }

  void toggleEnabled(IgnoreEntry entry, {required bool enabled}) {
    final idx = _entries.indexOf(entry);
    if (idx == -1) return;
    _entries[idx].enabled = enabled;
    notifyListeners();
    _save();
  }

  void updateEntry(IgnoreEntry entry, {
    String? label,
    IgnoreScope? scope,
  }) {
    final idx = _entries.indexOf(entry);
    if (idx == -1) return;
    if (label != null) _entries[idx].label = label;
    if (scope != null) _entries[idx].scope = scope;
    notifyListeners();
    _save();
  }

  bool shouldSuppress({
    required String mac,
    String ssid = '',
    required bool isBle,
  }) {
    final macLower = mac.toLowerCase().replaceAll(RegExp(r'[:\-.]'), '');
    final macColoned = _insertColons(macLower);

    for (final e in _entries) {
      if (!e.enabled) continue;
      if (!_scopeMatches(e.scope, isBle: isBle)) continue;

      switch (e.type) {
        case IgnoreType.ssid:
          if (ssid.isNotEmpty && ssid == e.value) return true;
        case IgnoreType.mac:
          if (macColoned == e.value) return true;
        case IgnoreType.oui:
          final ouiHex = e.value.replaceAll(':', '');
          if (macLower.startsWith(ouiHex)) return true;
      }
    }
    return false;
  }

  static bool _scopeMatches(IgnoreScope scope, {required bool isBle}) {
    if (scope == IgnoreScope.both) return true;
    if (scope == IgnoreScope.ble && isBle) return true;
    if (scope == IgnoreScope.wifi && !isBle) return true;
    return false;
  }

  static String _insertColons(String hex) {
    final buf = StringBuffer();
    for (int i = 0; i < hex.length; i++) {
      if (i > 0 && i.isEven) buf.write(':');
      buf.write(hex[i]);
    }
    return buf.toString();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _entries
        ..clear()
        ..addAll(list.map(IgnoreEntry.fromJson));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, json);
  }
}

final ignoreListProvider = ChangeNotifierProvider<IgnoreListState>((ref) {
  return IgnoreListState();
});
