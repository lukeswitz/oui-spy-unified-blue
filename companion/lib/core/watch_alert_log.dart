import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';

class AlertsFeed extends ChangeNotifier {
  AlertsFeed(this._db) {
    reload();
  }

  final AppDatabase _db;
  List<Map<String, dynamic>> rows = const [];
  bool loading = true;
  Timer? _debounce;
  bool _disposed = false;

  void changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), reload);
  }

  Future<void> reload() async {
    final next = await _db.getClassAlertMaps();
    if (_disposed) return;
    rows = next;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

final alertsFeedProvider = ChangeNotifierProvider<AlertsFeed>((ref) => AlertsFeed(ref.read(databaseProvider)));

typedef WatchAlertLog = void Function({
  required String kind,
  required String title,
  required String reason,
  required String subject,
  String name,
  String? body,
  bool isBle,
  int rssi,
  int channel,
  double? lat,
  double? lon,
});

final watchAlertLogProvider = Provider<WatchAlertLog>((ref) {
  final db = ref.read(databaseProvider);
  final notif = ref.read(notificationServiceProvider);
  final gps = ref.read(gpsProvider);
  return ({
    required String kind,
    required String title,
    required String reason,
    required String subject,
    String name = '',
    String? body,
    bool isBle = false,
    int rssi = 0,
    int channel = 0,
    double? lat,
    double? lon,
  }) {
    final here = lat == null || lon == null ? gps.recentPosition() : null;
    db
        .insertClassAlert(
          macAddress: subject,
          deviceName: name,
          alertClass: kind,
          title: title,
          reason: reason,
          isBle: isBle,
          rssi: rssi,
          channel: channel,
          alertedAt: DateTime.now().millisecondsSinceEpoch,
          latitude: lat ?? here?.latitude,
          longitude: lon ?? here?.longitude,
        )
        .then((_) => ref.read(alertsFeedProvider).changed())
        .catchError((Object e) => DebugLog.log('WATCH: alert log failed: $e'));
    DebugLog.log('WATCH: $kind $title · $reason');
    notif.onWatchAlert(kind: kind, title: title, subtitle: reason, body: body ?? reason, mac: subject);
  };
});
