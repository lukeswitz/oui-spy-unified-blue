// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';
import 'package:oui_spy/core/dashboard/dashboard_meshtastic.dart';
import 'package:oui_spy/core/dashboard/dashboard_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_state_test.dart' show FakeApi, FakeDiscovery, FakeTokens, settle;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parsing', () {
    test('the status carries the config, counters, channels and inbox', () {
      final s = MeshtasticStatus.fromJson(FakeApi().meshtastic);
      expect(s.config.enabled, isTrue);
      expect((s.config.port, s.config.channel), ('/dev/ttyUSB0', 1));
      expect(s.config.recipients, ['!0b0c0d0e']);
      expect(s.config.send, {'new_devices': true, 'drones': false, 'lost_nodes': false, 'nodes': true});
      expect((s.state, s.connected, s.radio, s.radioName, s.channelName), ('connected', true, '!0a1b2c3d', 'Dashboard Radio', 'Fleet'));
      expect((s.sent, s.failed, s.queued, s.heard), (4, 1, 2, 1));
      expect(s.last, DateTime.fromMillisecondsSinceEpoch(1700000000500));
      expect(s.channels.map((c) => (c.index, c.name, c.private)), [(0, 'LongFast', false), (1, 'Fleet', true)]);
      expect(s.inbox.single.who, 'North Gate');
      expect(s.inbox.single.text, 'all quiet');
    });

    test('an empty or odd reply is off with everything off', () {
      final s = MeshtasticStatus.fromJson({'channels': 'x', 'inbox': [1, {'text': 5}], 'config': 3, 'last': 'never'});
      expect((s.state, s.connected, s.last), ('off', false, null));
      expect(s.channels, isEmpty);
      expect(s.inbox, isEmpty);
      expect(s.config.enabled, isFalse);
      expect(s.config.channel, 1);
      expect(s.config.send.values.every((v) => !v), isTrue);
      expect(s.config.send.keys, meshEventKinds);
    });

    test('a heard message with no name shows who sent it', () {
      final h = MeshHeard.fromJson({'ts': 1.0, 'from': '!0deadbee', 'name': '', 'channel': 0, 'text': 'hi'})!;
      expect(h.who, '!0deadbee');
    });

    test('the config goes back as the dashboard expects it', () {
      final c = const MeshtasticConfig().copyWith(enabled: true, port: 'tcp:192.0.2.7', channel: 2, recipients: ['!0b0c0d0e']);
      expect(c.toJson(), {
        'enabled': true,
        'port': 'tcp:192.0.2.7',
        'channel': 2,
        'recipients': ['!0b0c0d0e'],
        'send': {'new_devices': false, 'drones': false, 'lost_nodes': false, 'nodes': false},
      });
    });

    test('node ids, states and event names', () {
      for (final ok in ['!0a1b2c3d', ' !0A1B2C3D ']) {
        expect(isMeshNodeId(ok), isTrue, reason: ok);
      }
      for (final bad in ['0a1b2c3d', '!0a1b2c3', '!0a1b2c3dd', '!0a1b2c3g', '']) {
        expect(isMeshNodeId(bad), isFalse, reason: bad);
      }
      expect(meshStateLabel('retrying'), 'Not connected: retrying');
      expect(meshStateLabel('error'), 'Failed');
      expect(meshStateLabel('off'), 'Off');
      expect(meshEventTitle('lost_nodes'), 'Lost nodes');
      expect(meshEventHint('new_devices'), 'A batch a minute');
    });

    test('the Meshtastic connector is one of the connectors', () {
      expect(DashboardConnector.meshtastic.key, 'meshtastic');
      expect(DashboardConnector.meshtastic.title, 'Meshtastic');
    });
  });

  group('through the dashboard link', () {
    late FakeApi api;
    late DashboardNotifier n;

    setUp(() async {
      api = FakeApi();
      n = DashboardNotifier(
          api: api, discovery: FakeDiscovery(), tokens: FakeTokens(), pollEvery: const Duration(hours: 1));
      await n.setEnabled(true);
      await n.setHost('192.0.2.5');
      await settle();
    });

    tearDown(() => n.dispose());

    test('status and ports are read from the dashboard', () async {
      final s = await n.loadMeshtastic();
      expect(s.error, isNull);
      expect(s.status!.sent, 4);
      expect(api.calls, contains('GET 192.0.2.5:5077/api/meshtastic'));
      final p = await n.loadPorts();
      expect(p.ports.map((x) => (x.device, x.espressif)), [('/dev/ttyUSB0', false), ('/dev/cu.usbmodem1101', true)]);
    });

    test('an older dashboard that has no /api/meshtastic is told apart', () async {
      api.failWith = const DashboardError(DashboardFault.rejected, 'HTTP 404 on /api/meshtastic');
      final s = await n.loadMeshtastic();
      expect(s.status, isNull);
      expect(s.error, 'The dashboard did not answer /api/meshtastic (an older dashboard?).');
      final p = await n.loadPorts();
      expect(p.ports, isEmpty);
      expect(p.error, 'HTTP 404 on /api/meshtastic');
    });

    test('saving, the switch and the test go to the dashboard; a refusal comes back as text', () async {
      final c = const MeshtasticConfig().copyWith(enabled: true, port: '/dev/ttyUSB0');
      expect(await n.saveMeshtastic(c), isNull);
      expect(api.posts.last, {'meshtastic': c.toJson()});
      expect(await n.setConnector(DashboardConnector.meshtastic, false), isNull);
      expect(api.posts.last, {
        'meshtastic': {'enabled': false}
      });
      expect(await n.testMeshtastic(), isNull);
      expect(api.calls, contains('POST 192.0.2.5:5077/api/meshtastic/test'));
      api.failWith = const DashboardError(DashboardFault.rejected, 'a radio port is needed');
      expect(await n.saveMeshtastic(c), 'a radio port is needed');
    });
  });
}
