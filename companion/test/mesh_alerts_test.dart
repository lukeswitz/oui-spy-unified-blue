// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' show AndroidFlutterLocalNotificationsPlugin;
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/meshtastic/mesh_alerts.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_proto.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AlertEvent ev(String channel, {String? kind, String title = 'Flock camera', String detail = 'Signature match'}) =>
    AlertEvent(title: title, detail: detail, channel: channel, kind: kind);

class Radio {
  final sent = <(String, List<int>)>[];
  String? refuse;
  Completer<String?>? hold;

  Future<String?> send(String text, List<int> to) async {
    if (hold != null) return hold!.future;
    if (refuse != null) return refuse;
    sent.add((text, to));
    return null;
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Radio radio;
  late DateTime now;

  MeshAlertNotifier make() => MeshAlertNotifier(send: radio.send, clock: () => now);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    radio = Radio();
    now = DateTime(2026, 3, 1, 12);
  });

  group('type of an alert', () {
    test('each notification channel maps to one type, and the silent channel to none', () {
      expect(meshAlertTypeOf(ev(NotifChannel.flock)), MeshAlertType.flock);
      expect(meshAlertTypeOf(ev(NotifChannel.drone)), MeshAlertType.drone);
      expect(meshAlertTypeOf(ev(NotifChannel.detector)), MeshAlertType.detector);
      expect(meshAlertTypeOf(ev(NotifChannel.detector, kind: 'watchlist')), MeshAlertType.detector);
      expect(meshAlertTypeOf(ev(NotifChannel.foxhunt)), MeshAlertType.foxhunt);
      expect(meshAlertTypeOf(ev(NotifChannel.nodes)), MeshAlertType.nodes);
      expect(meshAlertTypeOf(ev(NotifChannel.detectorQuiet)), isNull);
      expect(meshAlertTypeOf(ev(NotifChannel.quiet)), isNull);
      expect(meshAlertTypeOf(ev(NotifChannel.wardrive)), isNull);
    });

    test('a drone class alert on the detector channel is a drone alert', () {
      expect(meshAlertTypeOf(ev(NotifChannel.detector, kind: 'drone')), MeshAlertType.drone);
    });
  });

  group('message text', () {
    test('is OUI-APEX, the title and the detail on one line', () {
      expect(meshAlertText('Node down: North Gate', 'North Gate dropped off the mesh'),
          'OUI-APEX Node down: North Gate: North Gate dropped off the mesh');
      expect(meshAlertText('Flock camera', 'Signature match · -60 dBm\nBluetooth\n  AA:BB:CC:DD:EE:FF'),
          'OUI-APEX Flock camera: Signature match · -60 dBm · Bluetooth · AA:BB:CC:DD:EE:FF');
      expect(meshAlertText('Drone', ''), 'OUI-APEX Drone');
    });

    test('is cut to one packet and never inside a character', () {
      final long = meshAlertText('Flock camera', 'x' * 500);
      expect(utf8.encode(long).length, lessThanOrEqualTo(MeshtasticProto.maxTextBytes));
      expect(long, startsWith('OUI-APEX Flock camera: xxx'));
      expect(long, endsWith('…'));
      final wide = meshAlertText('T', 'é' * 300);
      expect(utf8.encode(wide).length, lessThanOrEqualTo(MeshtasticProto.maxTextBytes));
      expect(() => utf8.decode(utf8.encode(wide)), returnsNormally);
      expect(wide, isNot(contains('�')));
      final emoji = meshAlertText('T', '😀' * 100);
      expect(utf8.encode(emoji).length, lessThanOrEqualTo(MeshtasticProto.maxTextBytes));
      expect(emoji.runes.where((r) => r == 0xFFFD), isEmpty);
    });

    test('a message that fits is left alone', () {
      final exact = 'a' * (MeshtasticProto.maxTextBytes - 'OUI-APEX T: '.length);
      expect(meshAlertText('T', exact), 'OUI-APEX T: $exact');
    });
  });

  group('destination', () {
    test('node ids are read from spaces, commas and semicolons, lowercased, without repeats', () {
      final r = parseMeshNodeIds('!0A1B2C3D, !01020304;!0a1b2c3d\n!aabbccdd');
      expect(r.bad, isEmpty);
      expect(r.nodes, [0x0A1B2C3D, 0x01020304, 0xAABBCCDD]);
    });

    test('bad ids are named and none is guessed', () {
      final r = parseMeshNodeIds('0a1b2c3d !12345 !zzzzzzzz !0a1b2c3d1 !ffffffff !00000000 !0a1b2c3d');
      expect(r.bad, ['0a1b2c3d', '!12345', '!zzzzzzzz', '!0a1b2c3d1', '!ffffffff', '!00000000']);
      expect(r.nodes, [0x0A1B2C3D]);
      expect(parseMeshNodeIds('   ').nodes, isEmpty);
    });

    test('saving rejects a bad id and more than four nodes, and an empty list clears it', () async {
      final n = make();
      await settle();
      expect(await n.setNodes('!0a1b2c3d nope'), contains('like !0a1b2c3d'));
      expect(n.state.nodes, isEmpty);
      expect(await n.setNodes('!00000001 !00000002 !00000003 !00000004 !00000005'), 'Up to 4 nodes');
      expect(await n.setNodes('!0A1B2C3D !01020304'), isNull);
      expect(n.state.nodes, ['!0a1b2c3d', '!01020304']);
      expect(await n.setNodes(''), isNull);
      expect(n.state.nodes, isEmpty);
      n.dispose();
    });

    test('alerts go to the channel by default and to the named nodes when there are any', () async {
      final n = make();
      await settle();
      await n.setEnabled(true);
      expect(await n.handle(ev(NotifChannel.flock)), isTrue);
      expect(radio.sent.single.$2, isEmpty);
      await n.setNodes('!0a1b2c3d !01020304');
      now = now.add(const Duration(minutes: 5));
      expect(await n.handle(ev(NotifChannel.flock)), isTrue);
      expect(radio.sent.last.$2, [0x0A1B2C3D, 0x01020304]);
      n.dispose();
    });
  });

  group('gate', () {
    test('nothing is sent until it is turned on, and it is off by default', () async {
      final n = make();
      await settle();
      expect(n.state.enabled, isFalse);
      expect(await n.handle(ev(NotifChannel.flock)), isFalse);
      expect(radio.sent, isEmpty);
      expect(n.state.skipped, 0);
      n.dispose();
    });

    test('only the chosen types go out, and an unchosen type is not counted as skipped', () async {
      final n = make();
      await settle();
      await n.setEnabled(true);
      expect(n.state.types, {MeshAlertType.flock, MeshAlertType.drone, MeshAlertType.detector, MeshAlertType.nodes});
      expect(await n.handle(ev(NotifChannel.foxhunt)), isFalse);
      expect(await n.handle(ev(NotifChannel.detectorQuiet)), isFalse);
      expect(radio.sent, isEmpty);
      expect(n.state.skipped, 0);
      await n.setType(MeshAlertType.foxhunt, true);
      expect(await n.handle(ev(NotifChannel.foxhunt)), isTrue);
      await n.setType(MeshAlertType.drone, false);
      now = now.add(const Duration(minutes: 5));
      expect(await n.handle(ev(NotifChannel.detector, kind: 'drone')), isFalse);
      expect(await n.handle(ev(NotifChannel.drone)), isFalse);
      expect(await n.handle(ev(NotifChannel.detector, kind: 'camera')), isTrue);
      n.dispose();
    });

    test('a second alert inside the minimum gap is skipped and counted, then one after it goes out', () async {
      final n = make();
      await settle();
      await n.setEnabled(true);
      expect(n.state.gapSeconds, 60);
      expect(await n.handle(ev(NotifChannel.flock)), isTrue);
      now = now.add(const Duration(seconds: 59));
      expect(await n.handle(ev(NotifChannel.nodes)), isFalse);
      expect(n.state.skipped, 1);
      now = now.add(const Duration(seconds: 1));
      expect(await n.handle(ev(NotifChannel.nodes)), isTrue);
      expect((n.state.sent, n.state.skipped), (2, 1));
      await n.setGap(10);
      now = now.add(const Duration(seconds: 10));
      expect(await n.handle(ev(NotifChannel.nodes)), isTrue);
      n.dispose();
    });

    test('the gap and the cap stay inside their ranges', () async {
      final n = make();
      await settle();
      await n.setGap(1);
      expect(n.state.gapSeconds, 10);
      await n.setGap(9999);
      expect(n.state.gapSeconds, 600);
      await n.setCap(0);
      expect(n.state.dailyCap, 1);
      await n.setCap(9999);
      expect(n.state.dailyCap, 200);
      expect(n.state.copyWith().dailyCap, 200);
      n.dispose();
    });

    test('the daily cap stops sending, counts the rest, and the next day starts again', () async {
      final n = make();
      await settle();
      await n.setEnabled(true);
      await n.setCap(2);
      await n.setGap(10);
      for (var i = 0; i < 2; i++) {
        expect(await n.handle(ev(NotifChannel.flock)), isTrue);
        now = now.add(const Duration(seconds: 20));
      }
      expect(await n.handle(ev(NotifChannel.flock)), isFalse);
      now = now.add(const Duration(hours: 1));
      expect(await n.handle(ev(NotifChannel.flock)), isFalse);
      expect((n.state.sent, n.state.skipped, radio.sent.length), (2, 2, 2));
      expect(n.state.sentOn(now), 2);
      expect(n.state.skippedOn(now), 2);

      now = DateTime(2026, 3, 2, 0, 5);
      expect(n.state.sentOn(now), 0);
      expect(n.state.skippedOn(now), 0);
      expect(await n.handle(ev(NotifChannel.flock)), isTrue);
      expect((n.state.sent, n.state.skipped, n.state.day), (1, 0, '2026-03-02'));
      n.dispose();
    });

    test('a radio that cannot send skips the alert, counts it, and does not use up the gap', () async {
      final n = make();
      await settle();
      await n.setEnabled(true);
      radio.refuse = 'The radio is not connected';
      expect(await n.handle(ev(NotifChannel.flock)), isFalse);
      expect((n.state.sent, n.state.skipped), (0, 1));
      expect(n.state.lastSent, isNull);
      radio.refuse = null;
      now = now.add(const Duration(seconds: 1));
      expect(await n.handle(ev(NotifChannel.flock)), isTrue);
      expect((n.state.sent, n.state.skipped), (1, 1));
      n.dispose();
    });

    test('an alert that arrives while another is being sent is skipped', () async {
      final n = make();
      await settle();
      await n.setEnabled(true);
      radio.hold = Completer<String?>();
      final first = n.handle(ev(NotifChannel.flock));
      await settle();
      expect(await n.handle(ev(NotifChannel.nodes)), isFalse);
      expect(n.state.skipped, 1);
      radio.hold!.complete(null);
      expect(await first, isTrue);
      expect(n.state.sent, 1);
      n.dispose();
    });

    test('the settings and the day count are kept', () async {
      var n = make();
      await settle();
      await n.setEnabled(true);
      await n.setType(MeshAlertType.foxhunt, true);
      await n.setGap(120);
      await n.setCap(7);
      await n.setNodes('!0a1b2c3d');
      await n.handle(ev(NotifChannel.flock));
      n.dispose();

      n = make();
      await settle();
      expect(n.state.enabled, isTrue);
      expect(n.state.types, contains(MeshAlertType.foxhunt));
      expect((n.state.gapSeconds, n.state.dailyCap), (120, 7));
      expect(n.state.nodes, ['!0a1b2c3d']);
      expect((n.state.sent, n.state.day, n.state.lastSent), (1, '2026-03-01', now));
      n.dispose();
    });
  });

  group('notification hook', () {
    setUp(() {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (_) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        null,
      );
    });

    test('a listener hears each alert that notifies, with its channel, and live-activity onAlert still fires', () async {
      final svc = NotificationService()..debugReady();
      final heard = <AlertEvent>[];
      final live = <String>[];
      svc.onAlert = (title, detail, kind, mac, alert) => live.add(title);
      svc.addAlertListener(heard.add);
      svc.foxhuntEnabled = true;
      svc.onNodeDown('North Gate');
      svc.onNodeUp('North Gate');
      svc.onFoxhuntProximity(mac: 'aa:bb:cc:dd:ee:ff', rssi: -40, previousRssi: -60);
      svc.onWatchAlert(kind: 'watch', title: 'Home router', body: 'seen');
      await settle();
      expect(heard.map((e) => meshAlertTypeOf(e)), [
        MeshAlertType.nodes,
        MeshAlertType.nodes,
        MeshAlertType.foxhunt,
        MeshAlertType.detector,
      ]);
      expect(heard.first.title, 'Node down: North Gate');
      expect(heard.first.detail, 'North Gate dropped off the mesh');
      expect(live, heard.map((e) => e.title).toList());
      svc.dispose();
    });

    test('silenced alerts are not heard, sound off keeps the alert channel, and a removed listener hears nothing', () async {
      final svc = NotificationService()..debugReady();
      final heard = <AlertEvent>[];
      svc.addAlertListener(heard.add);
      svc.setSilenced(true);
      svc.onNodeDown('North Gate');
      await settle();
      expect(heard, isEmpty);
      svc.setSilenced(false);
      svc.soundEnabled = false;
      svc.onNodeDown('North Gate');
      await settle();
      expect(heard.single.channel, NotifChannel.nodes);
      svc.removeAlertListener(heard.add);
      svc.onNodeUp('North Gate');
      await settle();
      expect(heard, hasLength(1));
      svc.dispose();
    });
  });
}
