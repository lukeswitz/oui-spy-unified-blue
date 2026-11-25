// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';
import 'package:oui_spy/core/dashboard/dashboard_discovery.dart';
import 'package:oui_spy/core/dashboard/dashboard_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi implements DashboardApi {
  final calls = <String>[];
  final posts = <Map<String, dynamic>>[];
  Object? failWith;
  bool homeAlive = true;
  String? lastToken;
  Map<String, dynamic> settings = {
    'mqtt': {'enabled': true, 'connected': true, 'detail': '192.0.2.1:1883'},
    'tak': {'enabled': false, 'state': 'off'},
    'rns': {'enabled': true, 'state': 'error', 'error': 'install the rns and lxmf packages', 'address': ''},
    'retention_days': 14,
  };

  @override
  Future<Map<String, dynamic>> get(DashboardEndpoint e, String path, {String? token}) async {
    calls.add('GET ${e.label}$path');
    lastToken = token;
    final f = failWith;
    if (f != null) throw f;
    return {
      'home': {'id': 'A1B2', 'alive': homeAlive},
      'nodes': {'total': 4, 'online': 3},
      'board': {'connected': true, 'detail': 'x'},
      'settings': settings,
    };
  }

  @override
  Future<Map<String, dynamic>> post(DashboardEndpoint e, String path, Map<String, dynamic> body, {String? token}) async {
    calls.add('POST ${e.label}$path');
    posts.add(body);
    final f = failWith;
    if (f != null) throw f;
    return {'ok': true, 'n': 5};
  }
}

class FakeDiscovery implements DashboardDiscovery {
  DashboardEndpoint? result;
  int finds = 0;

  @override
  Future<DashboardEndpoint?> find() async {
    finds++;
    return result;
  }
}

class FakeTokens implements DashboardTokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? token) async => value = token;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeApi api;
  late FakeDiscovery disc;
  late FakeTokens tokens;

  DashboardNotifier make() =>
      DashboardNotifier(api: api, discovery: disc, tokens: tokens, pollEvery: const Duration(hours: 1));

  setUp(() {
    api = FakeApi();
    disc = FakeDiscovery();
    tokens = FakeTokens();
    SharedPreferences.setMockInitialValues({});
  });

  test('it is off until the user turns it on, and then makes no request without an address', () async {
    final n = make();
    await settle();
    expect(n.state.link, DashboardLink.off);
    await n.setEnabled(true);
    await settle();
    expect(n.state.link, DashboardLink.waiting);
    expect(n.state.error, 'Enter the dashboard address');
    expect(api.calls, isEmpty);
    expect(disc.finds, 0);
    n.dispose();
  });

  test('with an address it goes Live and shows the links', () async {
    final n = make();
    await n.setEnabled(true);
    await n.setHost('192.0.2.5');
    await settle();
    expect(n.state.link, DashboardLink.live);
    expect(api.calls.last, 'GET 192.0.2.5:5077/api/link');
    final s = n.state.summary!;
    expect((s.homeId, s.nodesOnline, s.nodesTotal, s.retentionDays), ('A1B2', 3, 4, 14));
    expect(s.connectors[DashboardConnector.mqtt]!.up, isTrue);
    expect(s.connectors[DashboardConnector.tak]!.enabled, isFalse);
    expect(s.connectors[DashboardConnector.rns]!.error, contains('rns'));
    n.dispose();
  });

  test('a silent home shows Home down', () async {
    api.homeAlive = false;
    final n = make();
    await n.setEnabled(true);
    await n.setHost('192.0.2.5');
    await settle();
    expect(n.state.link, DashboardLink.homeDown);
    n.dispose();
  });

  test('a refusal, an unreachable host and a bad address are told apart', () async {
    final n = make();
    await n.setEnabled(true);
    await n.setHost('192.0.2.5');
    await settle();
    api.failWith = const DashboardError(DashboardFault.refused, 'the dashboard wants the access token');
    await n.refresh();
    expect(n.state.link, DashboardLink.refused);
    expect(n.state.summary, isNull);
    api.failWith = const DashboardError(DashboardFault.unreachable, 'could not reach');
    await n.refresh();
    expect(n.state.link, DashboardLink.notConnected);
    await n.setHost('not an address');
    await settle();
    expect(n.state.link, DashboardLink.waiting);
    expect(n.state.error, 'That is not an address');
    n.dispose();
  });

  test('the token is kept in the token store and sent with requests', () async {
    final n = make();
    await n.setEnabled(true);
    await n.setHost('192.0.2.5');
    await n.setToken('  s3cret ');
    await settle();
    expect(tokens.value, 's3cret');
    expect(api.lastToken, 's3cret');
    expect(n.state.hasToken, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => (prefs.get(k) ?? '').toString().contains('s3cret')), isFalse);
    await n.setToken('');
    expect(tokens.value, isNull);
    expect(n.state.hasToken, isFalse);
    n.dispose();
  });

  test('discovery runs only when the user turned it on, and is remembered until a request fails', () async {
    disc.result = const DashboardEndpoint('192.0.2.7', 5077);
    final n = make();
    await n.setEnabled(true);
    await settle();
    expect(disc.finds, 0);
    await n.setDiscover(true);
    await settle();
    expect(disc.finds, 1);
    expect(n.state.link, DashboardLink.live);
    expect(api.calls.last, 'GET 192.0.2.7:5077/api/link');
    await n.refresh();
    expect(disc.finds, 1);
    api.failWith = const DashboardError(DashboardFault.unreachable, 'gone');
    await n.refresh();
    expect(n.state.link, DashboardLink.notConnected);
    api.failWith = null;
    await n.refresh();
    expect(disc.finds, 2);
    n.dispose();
  });

  test('nothing found says so', () async {
    final n = make();
    await n.setEnabled(true);
    await n.setDiscover(true);
    await settle();
    expect(n.state.link, DashboardLink.waiting);
    expect(n.state.error, 'No dashboard found on this network yet');
    n.dispose();
  });

  test('switching a connector, retention and clearing go to the dashboard; a refusal comes back as text', () async {
    final n = make();
    await n.setEnabled(true);
    await n.setHost('192.0.2.5');
    await settle();
    expect(await n.setConnector(DashboardConnector.tak, true), isNull);
    expect(api.posts.last, {'tak': {'enabled': true}});
    expect(await n.setRetention(30), isNull);
    expect(api.posts.last, {'retention_days': 30});
    await n.setRetention(-5);
    expect(api.posts.last, {'retention_days': 0});
    final r = await n.clearHistory();
    expect((r.cleared, r.error), (5, null));
    expect(api.calls.last, startsWith('GET'));
    api.failWith = const DashboardError(DashboardFault.rejected, 'a TAK server address is needed');
    expect(await n.setConnector(DashboardConnector.tak, true), 'a TAK server address is needed');
    final c = await n.clearHistory();
    expect((c.cleared, c.error), (null, 'a TAK server address is needed'));
    n.dispose();
  });

  test('settings survive a restart and turning it off drops the summary', () async {
    var n = make();
    await n.setEnabled(true);
    await n.setHost('192.0.2.5');
    await n.setDiscover(true);
    await settle();
    n.dispose();
    n = make();
    await settle();
    expect(n.state.settings.enabled, isTrue);
    expect(n.state.settings.host, '192.0.2.5');
    expect(n.state.settings.discover, isTrue);
    expect(n.state.link, DashboardLink.live);
    await n.setEnabled(false);
    expect(n.state.link, DashboardLink.off);
    expect(n.state.summary, isNull);
    n.dispose();
  });
}
