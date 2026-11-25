// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/assistant/assistant_grants.dart';
import 'package:oui_spy/core/assistant/assistant_tools.dart';
import 'package:oui_spy/features/assistant/assistant_settings_screen.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeEnv implements AssistantEnv {
  FakeEnv({this.linked = true});
  final bool linked;
  final calls = <String>[];

  @override
  bool get boardLinked => linked;
  @override
  Future<Map<String, dynamic>> health() async => {'app_version': '1.0.0'};
  @override
  List<Map<String, dynamic>> devices() => [
        {
          'mac': 'AA:BB:CC:00:00:01',
          'name': 'Cam',
          'maker': 'Acme',
          'type': 'camera',
          'best_rssi': -50,
          'first_ms': 1000,
          'last_ms': 2000,
          'lat': 10.123456,
          'lon': 20.123456,
        },
        {
          'mac': 'AA:BB:CC:00:00:02',
          'name': 'Watch',
          'maker': 'Other',
          'type': 'wearable',
          'best_rssi': -80,
          'first_ms': 500,
          'last_ms': 3000,
          'lat': 10.5,
          'lon': 20.5,
        },
      ];
  @override
  Future<List<Map<String, dynamic>>> alerts() async => [
        {'mac': 'AA:BB:CC:00:00:01', 'name': 'Cam', 'why': 'oui match', 'lat': 10.123456, 'lon': 20.123456},
      ];
  @override
  Map<String, dynamic> names() => {'aliases': [], 'watchlist': []};
  @override
  List<Map<String, dynamic>> drones() => [];
  @override
  Map<String, dynamic> wardrive() => {'state': 'idle', 'wifi_devices': 3};
  @override
  List<Map<String, dynamic>> mesh() => [];
  @override
  Future<List<Map<String, dynamic>>> captures() async => [];
  @override
  ({double lat, double lon})? positionOf(String place) => place == 'me' ? (lat: 10.123456, lon: 20.123456) : null;
  @override
  Future<String> setEngine(String engine, bool on) async {
    calls.add('engine $engine $on');
    return 'ok';
  }

  @override
  Future<String> setCapture(bool start) async {
    calls.add('capture $start');
    return 'ok';
  }

  @override
  Future<String> setAlias(String mac, String name) async {
    calls.add('alias $mac $name');
    return 'ok';
  }

  @override
  Future<String> reboot() async {
    calls.add('reboot');
    return 'ok';
  }

  @override
  Future<String> factoryReset() async {
    calls.add('factory');
    return 'ok';
  }

  @override
  Future<String> wipeWifiCredentials() async {
    calls.add('wipe');
    return 'ok';
  }
}

AssistantAccess access(Set<AssistantGrant> g, {bool on = true}) => AssistantAccess(on: on, granted: g);

void main() {
  group('hidePositions', () {
    test('removes keyed, paired and long decimals', () {
      final s = hidePositions('{"lat":10.123456,"pilot_lon":-20.5} at 10.1234, 20.1234 and 33.123456789 v1.2.3');
      expect(s, isNot(contains('10.123456')));
      expect(s, contains('"lat":"[location off]"'));
      expect(s, isNot(contains('20.1234')));
      expect(s, isNot(contains('33.123456789')));
      expect(s, contains('v1.2.3'));
    });
  });

  group('toolbox gating', () {
    test('everything is refused while the assistant is off', () async {
      final box = AssistantToolbox(FakeEnv());
      final r = await box.call('app_health', {}, access({AssistantGrant.devices}, on: false), (_) async => true);
      expect(r.isError, isTrue);
      expect(r.text, contains('off'));
    });

    test('a read tool needs its grant and names the missing one', () async {
      final box = AssistantToolbox(FakeEnv());
      final r = await box.call('app_devices', {}, access({}), (_) async => true);
      expect(r.isError, isTrue);
      expect(r.text, contains('DEVICES'));
    });

    test('app_health needs no grant', () async {
      final box = AssistantToolbox(FakeEnv());
      final r = await box.call('app_health', {}, access({}), (_) async => true);
      expect(r.isError, isFalse);
      expect(jsonDecode(r.text)['app_version'], '1.0.0');
    });

    test('positions are dropped without LOCATION and kept with it', () async {
      final box = AssistantToolbox(FakeEnv());
      final off = await box.call('app_devices', {}, access({AssistantGrant.devices}), (_) async => true);
      expect(off.text, isNot(contains('10.123456')));
      expect(off.text, isNot(contains('"lat"')));
      final on = await box.call('app_devices', {}, access({AssistantGrant.devices, AssistantGrant.loc}), (_) async => true);
      expect(on.text, contains('10.123456'));
    });

    test('alerts carry no position without LOCATION', () async {
      final box = AssistantToolbox(FakeEnv());
      final r = await box.call('app_alerts', {}, access({AssistantGrant.devices}), (_) async => true);
      expect(r.text, contains('oui match'));
      expect(r.text, isNot(contains('10.123456')));
    });

    test('devices sort, filter and limit', () async {
      final box = AssistantToolbox(FakeEnv());
      final a = access({AssistantGrant.devices});
      final byRecent = jsonDecode((await box.call('app_devices', {}, a, (_) async => true)).text);
      expect(byRecent['devices'][0]['name'], 'Watch');
      final bySignal = jsonDecode((await box.call('app_devices', {'sort': 'signal', 'limit': 1}, a, (_) async => true)).text);
      expect(bySignal['devices'], hasLength(1));
      expect(bySignal['devices'][0]['name'], 'Cam');
      final q = jsonDecode((await box.call('app_devices', {'query': 'acme'}, a, (_) async => true)).text);
      expect(q['total'], 1);
      final recent = jsonDecode((await box.call('app_devices', {'since_minutes': 1}, a, (_) async => true)).text);
      expect(recent['total'], 0);
    });

    test('app_near needs LOCATION and finds the nearest', () async {
      final box = AssistantToolbox(FakeEnv());
      final denied = await box.call('app_near', {'place': 'me'}, access({AssistantGrant.devices, AssistantGrant.drones}), (_) async => true);
      expect(denied.isError, isTrue);
      expect(denied.text, contains('LOCATION'));
      final ok = await box.call(
          'app_near', {'place': 'me', 'radius_m': 100}, access({AssistantGrant.devices, AssistantGrant.drones, AssistantGrant.loc}), (_) async => true);
      final out = jsonDecode(ok.text);
      expect(out['found'], 1);
      expect(out['nearest'][0]['name'], 'Cam');
    });

    test('output is cut at the limit', () async {
      final big = _BigEnv();
      final r = await AssistantToolbox(big).call('app_devices', {'limit': 100}, access({AssistantGrant.devices}), (_) async => true);
      expect(r.text.length, lessThan(maxToolText + 200));
      expect(r.text, contains('cut at'));
    });
  });

  group('actions', () {
    test('a board change waits for the person and does not run when declined', () async {
      final env = FakeEnv();
      final asked = <ToolRequest>[];
      final r = await AssistantToolbox(env).call('board_engine', {'engine': 'detector', 'action': 'on'}, access({AssistantGrant.control}), (q) async {
        asked.add(q);
        return false;
      });
      expect(asked, hasLength(1));
      expect(asked.single.summary, contains('detector'));
      expect(r.isError, isTrue);
      expect(env.calls, isEmpty);
    });

    test('an approved board change runs once', () async {
      final env = FakeEnv();
      final r = await AssistantToolbox(env).call('board_engine', {'engine': 'skySpy', 'action': 'off'}, access({AssistantGrant.control}), (_) async => true);
      expect(r.isError, isFalse);
      expect(env.calls, ['engine skySpy false']);
    });

    test('an engine outside the list is refused after approval', () async {
      final env = FakeEnv();
      final r = await AssistantToolbox(env).call('board_engine', {'engine': 'uniPwn', 'action': 'on'}, access({AssistantGrant.control}), (_) async => true);
      expect(r.isError, isTrue);
      expect(env.calls, isEmpty);
    });

    test('board tools without a link ask nothing', () async {
      var asked = 0;
      final r = await AssistantToolbox(FakeEnv(linked: false)).call('board_reboot', {}, access({AssistantGrant.control}), (_) async {
        asked++;
        return true;
      });
      expect(r.isError, isTrue);
      expect(asked, 0);
    });

    test('board tools without CONTROL are refused and never asked', () async {
      final env = FakeEnv();
      var asked = 0;
      final r = await AssistantToolbox(env).call('board_reboot', {}, access({AssistantGrant.devices}), (_) async {
        asked++;
        return true;
      });
      expect(r.isError, isTrue);
      expect(asked, 0);
      expect(env.calls, isEmpty);
    });

    test('irreversible tools are refused without the grant, even with CONTROL', () async {
      final env = FakeEnv();
      var asked = 0;
      for (final name in ['board_factory_reset', 'board_wipe_wifi']) {
        final r = await AssistantToolbox(env).call(name, {}, access({AssistantGrant.control}), (_) async {
          asked++;
          return true;
        });
        expect(r.isError, isTrue, reason: name);
        expect(r.text, contains('IRREVERSIBLE'));
      }
      expect(asked, 0);
      expect(env.calls, isEmpty);
    });

    test('irreversible tools run only with the grant and an OK', () async {
      final env = FakeEnv();
      final g = access({AssistantGrant.danger});
      expect((await AssistantToolbox(env).call('board_factory_reset', {}, g, (_) async => false)).isError, isTrue);
      expect(env.calls, isEmpty);
      expect((await AssistantToolbox(env).call('board_factory_reset', {}, g, (_) async => true)).isError, isFalse);
      expect(env.calls, ['factory']);
    });

    test('naming a device needs CONTROL and a valid MAC', () async {
      final env = FakeEnv();
      final box = AssistantToolbox(env);
      expect((await box.call('app_device_action', {'mac': 'AA:BB:CC:00:00:01', 'name': 'x'}, access({}), (_) async => true)).isError, isTrue);
      expect((await box.call('app_device_action', {'mac': 'nope', 'name': 'x'}, access({AssistantGrant.control}), (_) async => true)).isError, isTrue);
      final ok = await box.call('app_device_action', {'mac': 'aa:bb:cc:00:00:01', 'name': 'x'}, access({AssistantGrant.control}), (_) async => true);
      expect(ok.isError, isFalse);
      expect(env.calls, ['alias AA:BB:CC:00:00:01 x']);
    });

    test('an unknown tool is refused', () async {
      final r = await AssistantToolbox(FakeEnv()).call('recon_command', {'command': 'wipe'}, access(AssistantGrant.values.toSet()), (_) async => true);
      expect(r.isError, isTrue);
    });
  });

  test('offered lists only granted tools', () {
    expect(AssistantToolbox.offered(access({}, on: false)), isEmpty);
    final names = AssistantToolbox.offered(access({AssistantGrant.devices})).map((t) => t.name).toSet();
    expect(names, containsAll(['app_health', 'app_devices', 'app_alerts', 'app_names']));
    expect(names, isNot(contains('board_reboot')));
    expect(names, isNot(contains('app_near')));
    expect(names, isNot(contains('board_factory_reset')));
  });

  test('every tool is exposed in the MCP tool shape', () {
    for (final t in AssistantToolbox.all) {
      final j = t.toJson();
      expect(j.keys, containsAll(['name', 'title', 'description', 'inputSchema']));
      expect((j['inputSchema'] as Map)['type'], 'object');
    }
  });

  group('access state', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is off with nothing granted by default', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final a = c.read(assistantAccessProvider);
      expect(a.on, isFalse);
      expect(a.granted, isEmpty);
    });

    test('keeps what was set across a restart', () async {
      final c = ProviderContainer();
      await c.read(assistantAccessProvider.notifier).setOn(true);
      await c.read(assistantAccessProvider.notifier).setGrant(AssistantGrant.drones, true);
      c.dispose();
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(assistantAccessProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final a = c2.read(assistantAccessProvider);
      expect(a.on, isTrue);
      expect(a.granted, {AssistantGrant.drones});
    });

    test('grants do not count while the assistant is off', () {
      final a = access({AssistantGrant.devices}, on: false);
      expect(a.has(AssistantGrant.devices), isFalse);
    });
  });

  testWidgets('settings: switching on asks first, grants wait for it, sensitive grants warn', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: AssistantSettingsBody())),
    ));
    await tester.pumpAndSettle();
    expect(c.read(assistantAccessProvider).on, isFalse);

    await tester.tap(find.text('DEVICES'));
    await tester.pumpAndSettle();
    expect(c.read(assistantAccessProvider).granted, isEmpty);

    await tester.tap(find.widgetWithText(ConfigToggleRow, 'Assistant'));
    await tester.pumpAndSettle();
    expect(find.text('Switch the assistant on?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(c.read(assistantAccessProvider).on, isFalse);

    await tester.tap(find.widgetWithText(ConfigToggleRow, 'Assistant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SWITCH ON'));
    await tester.pumpAndSettle();
    expect(c.read(assistantAccessProvider).on, isTrue);

    await tester.tap(find.text('DEVICES'));
    await tester.pumpAndSettle();
    expect(c.read(assistantAccessProvider).granted, {AssistantGrant.devices});

    await tester.tap(find.text('LOCATION'));
    await tester.pumpAndSettle();
    expect(find.text('Grant LOCATION?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(c.read(assistantAccessProvider).granted, {AssistantGrant.devices});
  });
}

class _BigEnv extends FakeEnv {
  @override
  List<Map<String, dynamic>> devices() => [
        for (var i = 0; i < 100; i++)
          {'mac': 'AA:BB:CC:00:${i.toRadixString(16).padLeft(2, '0')}:01', 'name': 'Device number $i with a long name', 'maker': 'Maker $i', 'type': 'thing', 'last_ms': i},
      ];
}
