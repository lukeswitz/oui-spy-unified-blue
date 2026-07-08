import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _load();
  }

  static const _prefsKey = 'watchlist_entries_v1';

  final List<WatchlistEntry> entries = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  List<WatchlistEntry> get enabledEntries =>
      entries.where((e) => e.enabled).toList();

  void toggleEnabled(WatchlistEntry entry, {required bool enabled}) {
    final idx = entries.indexOf(entry);
    if (idx == -1) return;
    entries[idx].enabled = enabled;
    notifyListeners();
    _save();
  }

  void add(WatchlistEntry entry) {
    entries.add(entry);
    notifyListeners();
    _save();
  }

  void remove(WatchlistEntry entry) {
    entries.remove(entry);
    notifyListeners();
    _save();
  }

  void clear() {
    entries.clear();
    notifyListeners();
    _save();
  }

  void replaceAll(Iterable<WatchlistEntry> next) {
    entries
      ..clear()
      ..addAll(next);
    notifyListeners();
    _save();
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

final watchlistProvider = ChangeNotifierProvider<WatchlistState>((ref) {
  return WatchlistState();
});
