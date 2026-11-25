// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/node_watch.dart';
import 'package:oui_spy/core/notifications/alert_gate.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.after, this.fire);
  final Duration after;
  final void Function() fire;
  bool canceled = false;
  bool fired = false;

  @override
  void cancel() => canceled = true;

  @override
  bool get isActive => !canceled && !fired;

  @override
  int get tick => 0;

  void run() {
    if (canceled) return;
    fired = true;
    fire();
  }
}

void main() {
  const mac = 'AA:BB:CC:DD:EE:FF';

  group('AlertGate re-arm', () {
    test('first sighting alerts, continuous presence does not', () {
      final g = AlertGate();
      expect(g.check(mac, 0), AlertVerdict.fire);
      for (var t = 10000; t <= 300000; t += 10000) {
        expect(g.check(mac, t), AlertVerdict.notDue, reason: 'at $t');
      }
    });

    test('alerts again once the device was unheard for more than a minute', () {
      final g = AlertGate();
      expect(g.check(mac, 0), AlertVerdict.fire);
      expect(g.check(mac, 60000), AlertVerdict.notDue);
      expect(g.check(mac, 120001), AlertVerdict.fire);
      expect(g.check(mac, 125000), AlertVerdict.notDue);
    });

    test('the stored last-seen time counts as hearing the device', () {
      final g = AlertGate();
      expect(g.check(mac, 0), AlertVerdict.fire);
      expect(g.due(mac, 200000, lastSeenMs: 190000), isFalse);
      expect(g.due('11:22:33:44:55:66', 5000, lastSeenMs: 4000), isFalse);
      expect(g.due('11:22:33:44:55:77', 100000, lastSeenMs: 4000), isTrue);
    });

    test('gap follows the setting', () {
      final g = AlertGate(gapSeconds: 300);
      expect(g.check(mac, 0), AlertVerdict.fire);
      expect(g.check(mac, 200000), AlertVerdict.notDue);
      expect(g.check(mac, 600000), AlertVerdict.fire);
    });

    test('heard map is bounded', () {
      final g = AlertGate();
      for (var i = 0; i <= AlertGate.heardCap + 5; i++) {
        g.due('k$i', 1000);
      }
      expect(g.due('k0', 1000), isTrue);
    });
  });

  group('AlertGate mute, watch and silence', () {
    test('a muted device is blocked, a watched one is not', () {
      final g = AlertGate()..mutedDevices.add(mac);
      expect(g.check(mac, 0), AlertVerdict.muted);
      expect(g.check(mac, 200000, watchLabel: 'Front door'), AlertVerdict.fire);
      expect(g.check(mac, 400000, kindMuted: true), AlertVerdict.muted);
      expect(g.check(mac, 600000, watchLabel: 'Front door', kindMuted: true), AlertVerdict.fire);
    });

    test('silence all blocks even a watched device, and lifts when switched off', () {
      final g = AlertGate()..silenced = true;
      expect(g.check(mac, 0, watchLabel: 'Front door'), AlertVerdict.silenced);
      g.silenced = false;
      expect(g.check(mac, 200000, watchLabel: 'Front door'), AlertVerdict.fire);
    });

    test('device keys ignore MAC formatting and case', () {
      final g = AlertGate();
      g.mutedDevices.add(AlertGate.keyOf('aa-bb-cc-dd-ee-ff'));
      expect(g.isDeviceMuted('AA:BB:CC:DD:EE:FF'), isTrue);
      expect(g.isDeviceMuted('aabbccddeeff'), isTrue);
    });

    test('sound slot follows the event type', () {
      expect(alertSfxFor(), AlertSfx.hit);
      expect(alertSfxFor(tracker: true), AlertSfx.tracker);
      expect(alertSfxFor(drone: true), AlertSfx.drone);
      expect(alertSfxFor(watchLabel: 'x', drone: true, tracker: true), AlertSfx.watch);
      expect({for (final s in AlertSfx.values) s.prefKey}.length, AlertSfx.values.length);
    });
  });

  group('NodeWatch', () {
    late List<_FakeTimer> timers;
    late List<String> events;
    late DateTime clock;
    late NodeWatch w;

    setUp(() {
      timers = [];
      events = [];
      clock = DateTime(2026);
      w = NodeWatch(
        onDown: (id) => events.add('down $id'),
        onUp: (id) => events.add('up $id'),
        now: () => clock,
        timer: (d, f) {
          final t = _FakeTimer(d, f);
          timers.add(t);
          return t;
        },
      );
    });

    test('a node missing for 45 s is reported down, then back', () {
      w.update({'AAAA', 'BBBB'});
      w.update({'AAAA'});
      expect(timers.single.after, const Duration(seconds: 45));
      expect(events, isEmpty);
      timers.single.run();
      expect(events, ['down BBBB']);
      w.update({'AAAA'});
      expect(timers.length, 1);
      clock = clock.add(const Duration(minutes: 1));
      w.update({'AAAA', 'BBBB'});
      expect(events, ['down BBBB', 'up BBBB']);
      expect(w.down, isEmpty);
    });

    test('a node that returns before 45 s is never reported', () {
      w.update({'AAAA', 'BBBB'});
      w.update({'AAAA'});
      w.update({'AAAA', 'BBBB'});
      expect(timers.single.canceled, isTrue);
      timers.single.run();
      expect(events, isEmpty);
    });

    test('a node never seen live is not reported, and updates do not re-arm', () {
      w.update({'AAAA'});
      w.update({'AAAA'});
      expect(timers, isEmpty);
      w.update({'AAAA', 'BBBB'});
      w.update({'AAAA'});
      w.update({'AAAA'});
      expect(timers.length, 1);
    });

    test('the same direction is not repeated within 30 s', () {
      w.update({'AAAA', 'BBBB'});
      w.update({'AAAA'});
      timers.last.run();
      w.update({'AAAA', 'BBBB'});
      w.update({'AAAA'});
      timers.last.run();
      expect(events, ['down BBBB', 'up BBBB']);
      clock = clock.add(const Duration(seconds: 31));
      w.update({'AAAA', 'BBBB'});
      expect(events, ['down BBBB', 'up BBBB', 'up BBBB']);
    });

    test('reset drops pending reports', () {
      w.update({'AAAA', 'BBBB'});
      w.update({'AAAA'});
      w.reset();
      expect(timers.single.canceled, isTrue);
      w.update({'AAAA'});
      expect(timers.length, 1);
      expect(events, isEmpty);
    });
  });

  group('registry re-arm trigger', () {
    final engine = SignatureEngine(
      Signature.parseCatalog(File('assets/fieldwatch-signatures-v2.json').readAsStringSync()),
    );

    Observation seen(int at) => observationFromDetection(Detection(
          id: 'x',
          sessionId: 's',
          nodeId: 'n',
          macAddress: '02:00:00:00:00:09',
          engine: Engine.wardrive,
          method: 'ble_adv',
          rssi: -60,
          channel: 0,
          deviceTimestampMs: 0,
          appTimestamp: DateTime.fromMillisecondsSinceEpoch(at),
        ));

    test('a sighting after the gap re-runs classification with the previous last-seen time', () {
      final reg = DeviceRegistry(engine: engine);
      final prev = <int?>[];
      reg.onClassified = (d) => prev.add(d.prevSeenMs);
      reg.ingest(seen(1000), source: 'phone');
      reg.ingest(seen(20000), source: 'phone');
      expect(prev, [null]);
      reg.ingest(seen(81001), source: 'phone');
      expect(prev, [null, 20000]);
      reg.dispose();
    });

    test('the gap follows the setting', () {
      final reg = DeviceRegistry(engine: engine)..rearmGapMs = () => 10000;
      var fired = 0;
      reg.onClassified = (_) => fired++;
      reg.ingest(seen(1000), source: 'phone');
      reg.ingest(seen(12000), source: 'phone');
      expect(fired, 2);
      reg.dispose();
    });
  });

  group('unread alerts', () {
    late AppDatabase db;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    Future<void> alert(String subject, int at) => db.insertClassAlert(
          macAddress: subject,
          deviceName: '',
          alertClass: 'camera',
          title: 'T',
          reason: 'R',
          isBle: false,
          rssi: 0,
          channel: 0,
          alertedAt: at,
        );

    test('alerts newer than the last dismissal are unread, dismiss all clears them', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('alertsReadAtMs', 1000);
      await alert('02:00:00:00:00:01', 500);
      await alert('02:00:00:00:00:02', 2000);
      await alert('02:00:00:00:00:03', 3000);
      final feed = AlertsFeed(db, prefs: prefs);
      await feed.reload();
      expect(feed.unread, 2);
      expect(feed.isUnread(feed.rows.last), isFalse);
      await feed.markAllRead();
      expect(feed.unread, 0);
      expect(prefs.getInt('alertsReadAtMs')! > 3000, isTrue);
      feed.dispose();
    });

    test('first run treats stored alerts as read', () async {
      await alert('02:00:00:00:00:01', 500);
      final prefs = await SharedPreferences.getInstance();
      final feed = AlertsFeed(db, prefs: prefs);
      await feed.reload();
      expect(feed.unread, 0);
      expect(prefs.containsKey('alertsReadAtMs'), isTrue);
      feed.dispose();
    });
  });

  group('watched label', () {
    test('an enabled full-MAC entry gives its label; others give none', () async {
      SharedPreferences.setMockInitialValues({});
      final w = WatchlistState();
      await w.add(WatchlistEntry(
          identifier: mac, matchType: WatchlistMatchType.fullMac, description: 'Front door'));
      await w.add(WatchlistEntry(identifier: '11:22:33', matchType: WatchlistMatchType.oui, description: 'Maker'));
      await w.add(WatchlistEntry(
          identifier: '11:22:33:44:55:66', matchType: WatchlistMatchType.fullMac, enabled: false, description: 'Off'));
      await w.add(WatchlistEntry(identifier: '66:55:44:33:22:11', matchType: WatchlistMatchType.fullMac));
      expect(w.labelForMac('aa-bb-cc-dd-ee-ff'), 'Front door');
      expect(w.labelForMac('11:22:33:99:99:99'), isNull);
      expect(w.labelForMac('11:22:33:44:55:66'), isNull);
      expect(w.labelForMac('66:55:44:33:22:11'), '66:55:44:33:22:11');
      w.dispose();
    });
  });
}
