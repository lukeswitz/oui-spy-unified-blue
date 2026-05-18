import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WatchlistMatchType {
  oui('OUI'),
  fullMac('MAC'),
  name('NAME');

  const WatchlistMatchType(this.label);
  final String label;
}

class WatchlistEntry {
  WatchlistEntry({
    required this.identifier,
    this.matchType = WatchlistMatchType.oui,
    this.description = '',
  });

  String identifier;
  WatchlistMatchType matchType;
  String description;

  bool get isFullMac => matchType == WatchlistMatchType.fullMac;
  bool get isName => matchType == WatchlistMatchType.name;
  bool get isOui => matchType == WatchlistMatchType.oui;

  Map<String, dynamic> toJson() => {
        'identifier': identifier,
        'matchType': matchType.name,
        'description': description,
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
    );
  }
}

class WatchlistState extends ChangeNotifier {
  WatchlistState() {
    _load();
  }

  static const _prefsKey = 'watchlist_entries_v1';
  static const _seededKey = 'watchlist_seeded_v1';

  static final List<WatchlistEntry> _defaults = [
    WatchlistEntry(identifier: '70:c9:4e', description: 'Flock Safety'),
    WatchlistEntry(identifier: '3c:91:80', description: 'Flock Safety'),
    WatchlistEntry(identifier: 'd8:f3:bc', description: 'Flock Safety'),
    WatchlistEntry(identifier: '58:8e:81', description: 'FS Ext Battery'),
    WatchlistEntry(identifier: '80:30:49', description: 'Flock Safety'),
    WatchlistEntry(identifier: '14:5a:fc', description: 'Flock Safety'),
  ];

  final List<WatchlistEntry> entries = [];
  bool _loaded = false;
  bool get isLoaded => _loaded;

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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        entries
          ..clear()
          ..addAll(list.map(WatchlistEntry.fromJson));
      } catch (_) {
        entries.clear();
      }
    } else if (!(prefs.getBool(_seededKey) ?? false)) {
      entries
        ..clear()
        ..addAll(_defaults.map((e) => WatchlistEntry(
              identifier: e.identifier,
              matchType: e.matchType,
              description: e.description,
            )));
      await prefs.setBool(_seededKey, true);
      await _writeRaw(prefs);
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
