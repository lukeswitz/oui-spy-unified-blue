import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WatchlistEntry {
  WatchlistEntry({required this.identifier, this.isFullMac = false, this.description = ''});
  String identifier;
  bool isFullMac;
  String description;
}

class WatchlistState extends ChangeNotifier {
  final List<WatchlistEntry> entries = [
    WatchlistEntry(identifier: '70:c9:4e', description: 'Flock Safety'),
    WatchlistEntry(identifier: '3c:91:80', description: 'Flock Safety'),
    WatchlistEntry(identifier: 'd8:f3:bc', description: 'Flock Safety'),
    WatchlistEntry(identifier: '58:8e:81', description: 'FS Ext Battery'),
    WatchlistEntry(identifier: '80:30:49', description: 'Flock Safety'),
    WatchlistEntry(identifier: '14:5a:fc', description: 'Flock Safety'),
  ];

  void add(WatchlistEntry entry) {
    entries.add(entry);
    notifyListeners();
  }

  void remove(WatchlistEntry entry) {
    entries.remove(entry);
    notifyListeners();
  }

  void clear() {
    entries.clear();
    notifyListeners();
  }
}

final watchlistProvider = ChangeNotifierProvider<WatchlistState>((ref) {
  return WatchlistState();
});
