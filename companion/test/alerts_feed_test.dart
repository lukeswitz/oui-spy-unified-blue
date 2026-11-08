import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/watch_alert_log.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> alert(String subject, String kind, int at, {String title = 'T', String reason = 'R'}) =>
      db.insertClassAlert(
        macAddress: subject,
        deviceName: '',
        alertClass: kind,
        title: title,
        reason: reason,
        isBle: false,
        rssi: 0,
        channel: 0,
        alertedAt: at,
      );

  test('feed lists alerts newest first, one row per subject and kind', () async {
    await alert('GPS', 'gps_watch', 1000, reason: 'first');
    await alert('GPS', 'gps_watch', 3000, reason: 'second');
    await alert('02:00:00:00:00:01', 'trusted_network', 2000);
    final feed = AlertsFeed(db);
    await feed.reload();
    expect(feed.loading, isFalse);
    expect(feed.rows.map((r) => r['alertClass']), ['gps_watch', 'trusted_network']);
    expect(feed.rows.first['count'], 2);
    expect(feed.rows.first['detectionMethod'], 'second');
    await db.deleteClassAlerts('GPS', 'gps_watch');
    await feed.reload();
    expect(feed.rows.single['alertClass'], 'trusted_network');
    feed.dispose();
  });

  test('new alert kinds have their own label and icon', () {
    expect(alertKindLabel('cell_watch'), 'CELL NETWORK');
    expect(alertKindLabel('beacon_flood'), 'BEACON FLOOD');
    expect(alertKindIcon('car_follow'), Icons.directions_car);
    expect(alertKindLabel('flock'), 'FLOCK');
    expect(alertKindLabel('unknown_kind'), 'SIGNATURE');
  });
}
