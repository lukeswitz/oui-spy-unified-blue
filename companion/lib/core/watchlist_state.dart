// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/classify/observation.dart';

enum WatchlistMatchType {
  oui('OUI'),
  fullMac('MAC'),
  name('NAME'),
  serviceUuid('UUID');

  const WatchlistMatchType(this.label);
  final String label;
}

class WatchlistEntry {
  WatchlistEntry({
    required this.identifier,
    this.matchType = WatchlistMatchType.oui,
    this.description = '',
    this.enabled = true,
  });

  String identifier;
  WatchlistMatchType matchType;
  String description;
  bool enabled;

  bool get isFullMac => matchType == WatchlistMatchType.fullMac;
  bool get isName => matchType == WatchlistMatchType.name;
  bool get isOui => matchType == WatchlistMatchType.oui;
  bool get isServiceUuid => matchType == WatchlistMatchType.serviceUuid;

  Map<String, dynamic> toJson() => {
        'identifier': identifier,
        'matchType': matchType.name,
        'description': description,
        'enabled': enabled,
      };

  factory WatchlistEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['matchType'];
    WatchlistMatchType type;
    if (raw is String) {
      type = WatchlistMatchType.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => WatchlistMatchType.oui,
      );
    } else if (json['isFullMac'] == true) {
      type = WatchlistMatchType.fullMac;
    } else {
      type = WatchlistMatchType.oui;
    }
    return WatchlistEntry(
      identifier: json['identifier'] as String? ?? '',
      matchType: type,
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class WatchlistState extends ChangeNotifier {
  WatchlistState() {
    _loadFuture = _load();
  }

  static const _prefsKey = 'watchlist_entries_v1';

  final List<WatchlistEntry> entries = [];
  bool _loaded = false;
  late final Future<void> _loadFuture;
  bool get isLoaded => _loaded;

  List<WatchlistEntry> get enabledEntries =>
      entries.where((e) => e.enabled).toList();

  String? labelForMac(String mac) {
    final key = MacUtil.normalize(mac);
    if (key.isEmpty) return null;
    for (final e in entries) {
      if (e.enabled && e.isFullMac && e.identifier.toUpperCase() == key) {
        final d = e.description.trim();
        return d.isEmpty ? e.identifier : d;
      }
    }
    return null;
  }

  Future<void> toggleEnabled(WatchlistEntry entry, {required bool enabled}) async {
    await _loadFuture;
    final idx = entries.indexOf(entry);
    if (idx == -1) return;
    entries[idx].enabled = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> add(WatchlistEntry entry) async {
    await _loadFuture;
    entries.add(entry);
    notifyListeners();
    await _save();
  }

  Future<void> update(WatchlistEntry old, WatchlistEntry next) async {
    await _loadFuture;
    final idx = entries.indexOf(old);
    if (idx == -1) return;
    entries[idx] = next;
    notifyListeners();
    await _save();
  }

  Future<void> remove(WatchlistEntry entry) async {
    await _loadFuture;
    entries.remove(entry);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    await _loadFuture;
    entries.clear();
    notifyListeners();
    await _save();
  }

  Future<void> replaceAll(Iterable<WatchlistEntry> next) async {
    await _loadFuture;
    entries
      ..clear()
      ..addAll(next);
    notifyListeners();
    await _save();
  }

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(entries.map((e) => e.toJson()).toList());

  Future<({int added, int skipped})> importText(String text) async {
    await _loadFuture;
    final parsed = parseWatchlistImport(text);
    final seen = entries.map(watchlistKey).toSet();
    var added = 0;
    for (final e in parsed.entries) {
      if (seen.add(watchlistKey(e))) {
        entries.add(e);
        added++;
      }
    }
    if (added > 0) {
      notifyListeners();
      await _save();
    }
    return (added: added, skipped: parsed.invalid + parsed.entries.length - added);
  }

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && entries.isEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        entries
          ..clear()
          ..addAll(list.map(WatchlistEntry.fromJson));
      } catch (_) {
        entries.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await _writeRaw(prefs);
  }

  Future<void> _writeRaw(SharedPreferences prefs) async {
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, json);
  }
}

String watchlistKey(WatchlistEntry e) =>
    '${e.matchType.name}|${e.identifier.toUpperCase()}';

final _hexByte = RegExp(r'^[0-9A-Fa-f]{2}$');

String? normalizeWatchlistId(String raw, WatchlistMatchType type) {
  final s = raw.trim();
  switch (type) {
    case WatchlistMatchType.oui:
    case WatchlistMatchType.fullMac:
      final parts = s.replaceAll('-', ':').split(':');
      final want = type == WatchlistMatchType.oui ? 3 : 6;
      final bytes = parts.length == 1 && s.length == want * 2
          ? [for (var i = 0; i < want * 2; i += 2) s.substring(i, i + 2)]
          : parts;
      if (bytes.length != want || !bytes.every(_hexByte.hasMatch)) return null;
      return bytes.map((b) => b.toUpperCase()).join(':');
    case WatchlistMatchType.serviceUuid:
      final h = s.replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
      return RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(h) ? h.toUpperCase() : null;
    case WatchlistMatchType.name:
      final n = _cleanText(s, 32);
      return n.isEmpty ? null : n;
  }
}

String _cleanText(String s, int maxBytes) {
  final out = StringBuffer();
  var bytes = 0;
  for (final r in s.trim().runes) {
    if (r < 0x20 || (r >= 0x7f && r <= 0x9f) || (r >= 0x202a && r <= 0x202e) ||
        (r >= 0x2066 && r <= 0x2069)) {
      continue;
    }
    final n = utf8.encode(String.fromCharCode(r)).length;
    if (bytes + n > maxBytes) break;
    bytes += n;
    out.writeCharCode(r);
  }
  return out.toString();
}

WatchlistMatchType? _inferType(String id, String? typeField) {
  final t = typeField?.trim().toLowerCase() ?? '';
  for (final m in WatchlistMatchType.values) {
    if (t == m.name.toLowerCase() || t == m.label.toLowerCase()) return m;
  }
  if (t.isNotEmpty) return null;
  final hex = id.trim().replaceAll(RegExp(r'[:\-]'), '');
  if (RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(hex)) return WatchlistMatchType.fullMac;
  if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) return WatchlistMatchType.oui;
  return null;
}

({List<WatchlistEntry> entries, int invalid}) parseWatchlistImport(String text) {
  final out = <WatchlistEntry>[];
  var invalid = 0;
  void addRow(String id, String desc, String? type, bool enabled) {
    final mt = _inferType(id, type);
    final norm = mt == null ? null : normalizeWatchlistId(id, mt);
    if (mt == null || norm == null) {
      invalid++;
      return;
    }
    out.add(WatchlistEntry(
      identifier: norm,
      matchType: mt,
      description: _cleanText(desc, 31),
      enabled: enabled,
    ));
  }

  final trimmed = text.trimLeft();
  if (trimmed.startsWith('[')) {
    final list = jsonDecode(trimmed);
    if (list is! List) throw const FormatException('expected JSON array');
    for (final item in list.take(5000)) {
      if (item is! Map) {
        invalid++;
        continue;
      }
      final id = item['identifier'] ?? item['oui'] ?? item['mac'];
      if (id is! String) {
        invalid++;
        continue;
      }
      final desc = item['description'];
      final type = item['matchType'];
      addRow(id, desc is String ? desc : '', type is String ? type : null,
          item['enabled'] is bool ? item['enabled'] as bool : true);
    }
    return (entries: out, invalid: invalid);
  }

  for (final line in const LineSplitter().convert(text).take(5000)) {
    final l = line.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final cols = l.split(RegExp(r'[,;\t]')).map((c) => c.trim().replaceAll('"', '')).toList();
    if (cols.first.toLowerCase() == 'identifier' || cols.first.toLowerCase() == 'oui') continue;
    final hasType = cols.length > 2 &&
        WatchlistMatchType.values.any((m) =>
            cols.last.toLowerCase() == m.name.toLowerCase() ||
            cols.last.toLowerCase() == m.label.toLowerCase());
    final desc = cols.length > 1
        ? cols.sublist(1, hasType ? cols.length - 1 : cols.length).join(', ')
        : '';
    addRow(cols[0], desc, hasType ? cols.last : null, true);
  }
  return (entries: out, invalid: invalid);
}

final watchlistProvider =ChangeNotifierProvider<WatchlistState>((ref) {
  return WatchlistState();
});
