import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';

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
  static final _macStripRegex = RegExp(r'[:\-.]');

  final List<IgnoreEntry> _entries = [];
  final Map<int, String> _ouiHexCache = {};
  void Function()? onChanged;
  List<IgnoreEntry> get entries => List.unmodifiable(_entries);

  void add(IgnoreEntry entry) {
    if (_entries.contains(entry)) return;
    _entries.add(entry);
    _rebuildOuiCache();
    notifyListeners();
    _save();
  }

  void remove(IgnoreEntry entry) {
    _entries.remove(entry);
    _rebuildOuiCache();
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
    final macLower = mac.toLowerCase().replaceAll(_macStripRegex, '');
    final macColoned = _insertColons(macLower);

    for (int i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (!e.enabled) continue;
      if (!_scopeMatches(e.scope, isBle: isBle)) continue;

      switch (e.type) {
        case IgnoreType.ssid:
          if (ssid.isNotEmpty && ssid == e.value) return true;
        case IgnoreType.mac:
          if (macColoned == e.value) return true;
        case IgnoreType.oui:
          final ouiHex = _ouiHexCache[i] ?? '';
          if (ouiHex.isNotEmpty && macLower.startsWith(ouiHex)) return true;
      }
    }
    return false;
  }

  // Wire format for firmware (matches src/ignore_list.cpp):
  //   [count:1] then per entry [type:1][scope:1][len:1][value:len]
  //   type: ssid=0 mac=1 oui=2 (IgnoreType.index); scope: both=0 wifi=1 ble=2 (IgnoreScope.index)
  List<int> serializeForFirmware() {
    final encoded = <List<int>>[];
    for (final e in _entries) {
      if (!e.enabled) continue;
      if (encoded.length >= 48) break;
      List<int> value;
      switch (e.type) {
        case IgnoreType.ssid:
          value = utf8.encode(e.value);
          if (value.length > 32) value = value.sublist(0, 32);
        case IgnoreType.mac:
          value = _hexToBytes(e.value, 6);
        case IgnoreType.oui:
          value = _hexToBytes(e.value, 3);
      }
      if (value.isEmpty) continue;
      encoded.add([e.type.index, e.scope.index, value.length, ...value]);
    }
    final out = <int>[encoded.length & 0xFF];
    for (final en in encoded) {
      out.addAll(en);
    }
    return out;
  }

  static List<int> _hexToBytes(String s, int n) {
    final hex = s.toLowerCase().replaceAll(_macStripRegex, '');
    final out = <int>[];
    for (int i = 0; i + 1 < hex.length && out.length < n; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b == null) return const [];
      out.add(b);
    }
    return out.length == n ? out : const [];
  }

  void _rebuildOuiCache() {
    _ouiHexCache.clear();
    for (int i = 0; i < _entries.length; i++) {
      if (_entries[i].type == IgnoreType.oui) {
        _ouiHexCache[i] = _entries[i].value.replaceAll(':', '');
      }
    }
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
      _rebuildOuiCache();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, json);
    onChanged?.call();
  }
}

final ignoreListProvider = ChangeNotifierProvider<IgnoreListState>((ref) {
  final state = IgnoreListState();
  state.onChanged = () {
    ref.read(bleManagerProvider).setIgnoreList(state.serializeForFirmware());
  };
  return state;
});
