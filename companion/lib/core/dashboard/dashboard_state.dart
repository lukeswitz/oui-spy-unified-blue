// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';
import 'package:oui_spy/core/dashboard/dashboard_discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DashboardLink { off, waiting, notConnected, connecting, live, homeDown, refused }

extension DashboardLinkText on DashboardLink {
  String get label => switch (this) {
        DashboardLink.off => 'Off',
        DashboardLink.waiting => 'Waiting',
        DashboardLink.notConnected => 'Not connected',
        DashboardLink.connecting => 'Connecting',
        DashboardLink.live => 'Live',
        DashboardLink.homeDown => 'Home down',
        DashboardLink.refused => 'Refused',
      };
}

enum DashboardConnector { mqtt, tak, rns }

extension DashboardConnectorText on DashboardConnector {
  String get key => name;

  String get title => switch (this) {
        DashboardConnector.mqtt => 'MQTT',
        DashboardConnector.tak => 'TAK server',
        DashboardConnector.rns => 'Reticulum',
      };

  String get subtitle => switch (this) {
        DashboardConnector.mqtt => 'Detections in from nodes on Wi-Fi',
        DashboardConnector.tak => 'Nodes, drones and pilots to a TAK server',
        DashboardConnector.rns => 'Alerts as LXMF messages',
      };
}

class ConnectorInfo {
  const ConnectorInfo({this.enabled = false, this.state = '', this.detail = '', this.error = '', this.sent});

  final bool enabled;

  /// `connected`, `connecting`, `error`, `off` or empty when the dashboard did not say.
  final String state;
  final String detail;
  final String error;
  final int? sent;

  bool get up => state == 'connected';

  static ConnectorInfo fromJson(DashboardConnector c, Object? json) {
    if (json is! Map) return const ConnectorInfo();
    final enabled = json['enabled'] == true;
    final error = json['error'] is String ? json['error'] as String : '';
    if (c == DashboardConnector.mqtt) {
      final connected = json['connected'] == true;
      return ConnectorInfo(
        enabled: enabled,
        state: !enabled ? 'off' : (connected ? 'connected' : 'error'),
        detail: json['detail'] is String ? json['detail'] as String : '',
      );
    }
    return ConnectorInfo(
      enabled: enabled,
      state: json['state'] is String ? json['state'] as String : '',
      error: error,
      sent: json['sent'] is num ? (json['sent'] as num).toInt() : null,
      detail: c == DashboardConnector.rns && json['address'] is String ? json['address'] as String : '',
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.homeAlive,
    required this.homeId,
    required this.nodesTotal,
    required this.nodesOnline,
    required this.boardConnected,
    required this.boardDetail,
    required this.retentionDays,
    required this.connectors,
  });

  final bool homeAlive;
  final String homeId;
  final int nodesTotal;
  final int nodesOnline;
  final bool boardConnected;
  final String boardDetail;
  final int retentionDays;
  final Map<DashboardConnector, ConnectorInfo> connectors;

  static DashboardSummary fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String k) => j[k] is Map ? (j[k] as Map).cast<String, dynamic>() : const {};
    final home = sub('home'), nodes = sub('nodes'), board = sub('board'), settings = sub('settings');
    return DashboardSummary(
      homeAlive: home['alive'] == true,
      homeId: home['id'] is String ? home['id'] as String : '',
      nodesTotal: (nodes['total'] as num?)?.toInt() ?? 0,
      nodesOnline: (nodes['online'] as num?)?.toInt() ?? 0,
      boardConnected: board['connected'] == true,
      boardDetail: board['detail'] is String ? board['detail'] as String : '',
      retentionDays: (settings['retention_days'] as num?)?.toInt() ?? 0,
      connectors: {for (final c in DashboardConnector.values) c: ConnectorInfo.fromJson(c, settings[c.key])},
    );
  }
}

class DashboardSettings {
  const DashboardSettings({this.enabled = false, this.host = '', this.discover = false});

  final bool enabled;
  final String host;
  final bool discover;

  DashboardSettings copyWith({bool? enabled, String? host, bool? discover}) => DashboardSettings(
      enabled: enabled ?? this.enabled, host: host ?? this.host, discover: discover ?? this.discover);
}

class DashboardState {
  const DashboardState({
    this.settings = const DashboardSettings(),
    this.link = DashboardLink.off,
    this.summary,
    this.endpoint,
    this.error = '',
    this.hasToken = false,
  });

  final DashboardSettings settings;
  final DashboardLink link;
  final DashboardSummary? summary;
  final DashboardEndpoint? endpoint;
  final String error;
  final bool hasToken;

  DashboardState copyWith({
    DashboardSettings? settings,
    DashboardLink? link,
    DashboardSummary? summary,
    bool clearSummary = false,
    DashboardEndpoint? endpoint,
    bool clearEndpoint = false,
    String? error,
    bool? hasToken,
  }) =>
      DashboardState(
        settings: settings ?? this.settings,
        link: link ?? this.link,
        summary: clearSummary ? null : (summary ?? this.summary),
        endpoint: clearEndpoint ? null : (endpoint ?? this.endpoint),
        error: error ?? this.error,
        hasToken: hasToken ?? this.hasToken,
      );
}

abstract class DashboardTokenStore {
  Future<String?> read();

  Future<void> write(String? token);
}

class SecureDashboardTokenStore implements DashboardTokenStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'dashboard_token';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) =>
      token == null || token.isEmpty ? _storage.delete(key: _key) : _storage.write(key: _key, value: token);
}

/// The link to the home dashboard. Off by default. While the settings screen is open it asks the dashboard
/// how it is doing every [pollEvery]; the dashboard owns the MQTT, TAK and Reticulum links and this only
/// shows and switches them.
class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier({
    required DashboardApi api,
    required DashboardDiscovery discovery,
    required DashboardTokenStore tokens,
    this.pollEvery = const Duration(seconds: 10),
  })  : _api = api,
        _discovery = discovery,
        _tokens = tokens,
        super(const DashboardState()) {
    _load();
  }

  static const _kOn = 'dashboard_on', _kHost = 'dashboard_host', _kFind = 'dashboard_find';

  final DashboardApi _api;
  final DashboardDiscovery _discovery;
  final DashboardTokenStore _tokens;
  final Duration pollEvery;
  Timer? _timer;
  String? _token;
  DashboardEndpoint? _found;
  bool _busy = false;
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final token = await _tokens.read();
    if (_changed || !mounted) return;
    _token = token;
    state = state.copyWith(
      settings: DashboardSettings(
        enabled: p.getBool(_kOn) ?? false,
        host: p.getString(_kHost) ?? '',
        discover: p.getBool(_kFind) ?? false,
      ),
      hasToken: token != null && token.isNotEmpty,
    );
    _sync();
  }

  Future<void> _save(DashboardSettings s) async {
    _changed = true;
    state = state.copyWith(settings: s);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, s.enabled);
    await p.setString(_kHost, s.host);
    await p.setBool(_kFind, s.discover);
    _found = null;
    _sync();
  }

  Future<void> setEnabled(bool on) => _save(state.settings.copyWith(enabled: on));

  Future<void> setHost(String host) => _save(state.settings.copyWith(host: host.trim()));

  Future<void> setDiscover(bool on) => _save(state.settings.copyWith(discover: on));

  Future<void> setToken(String token) async {
    _changed = true;
    _token = token.trim().isEmpty ? null : token.trim();
    await _tokens.write(_token);
    if (!mounted) return;
    state = state.copyWith(hasToken: _token != null);
    unawaited(refresh());
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    if (!state.settings.enabled) {
      state = state.copyWith(link: DashboardLink.off, clearSummary: true, clearEndpoint: true, error: '');
      return;
    }
    _timer = Timer.periodic(pollEvery, (_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_busy || !mounted) return;
    final s = state.settings;
    if (!s.enabled) return;
    _busy = true;
    try {
      var ep = DashboardEndpoint.parse(s.host);
      if (s.host.trim().isNotEmpty && ep == null) {
        state = state.copyWith(link: DashboardLink.waiting, clearEndpoint: true, error: 'That is not an address');
        return;
      }
      ep ??= s.discover ? (_found ??= await _discovery.find()) : null;
      if (!mounted) return;
      if (ep == null) {
        state = state.copyWith(
            link: DashboardLink.waiting,
            clearSummary: true,
            clearEndpoint: true,
            error: s.discover ? 'No dashboard found on this network yet' : 'Enter the dashboard address');
        return;
      }
      if (state.summary == null) state = state.copyWith(link: DashboardLink.connecting, endpoint: ep, error: '');
      try {
        final json = await _api.get(ep, '/api/link', token: _token);
        if (!mounted) return;
        final sum = DashboardSummary.fromJson(json);
        state = state.copyWith(
            link: sum.homeAlive ? DashboardLink.live : DashboardLink.homeDown,
            summary: sum,
            endpoint: ep,
            error: '');
      } on DashboardError catch (e) {
        if (!mounted) return;
        if (s.host.trim().isEmpty) _found = null;
        state = state.copyWith(
            link: e.fault == DashboardFault.refused ? DashboardLink.refused : DashboardLink.notConnected,
            clearSummary: true,
            endpoint: ep,
            error: e.message);
      }
    } finally {
      _busy = false;
    }
  }

  Future<String?> _post(String path, Map<String, dynamic> body) async {
    final ep = state.endpoint;
    if (ep == null) return 'Not connected to the dashboard';
    try {
      await _api.post(ep, path, body, token: _token);
    } on DashboardError catch (e) {
      return e.message;
    }
    unawaited(refresh());
    return null;
  }

  /// Switches one of the dashboard's links. Returns why it was refused, or null.
  Future<String?> setConnector(DashboardConnector c, bool on) => _post('/api/settings', {
        c.key: {'enabled': on}
      });

  Future<String?> setRetention(int days) => _post('/api/settings', {'retention_days': days < 0 ? 0 : days});

  /// Deletes every detection the dashboard holds. Returns the number deleted, or the reason it was refused.
  Future<({int? cleared, String? error})> clearHistory() async {
    final ep = state.endpoint;
    if (ep == null) return (cleared: null, error: 'Not connected to the dashboard');
    try {
      final r = await _api.post(ep, '/api/detections/clear', const {}, token: _token);
      unawaited(refresh());
      return (cleared: (r['n'] as num?)?.toInt() ?? 0, error: null);
    } on DashboardError catch (e) {
      return (cleared: null, error: e.message);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final dashboardProvider = StateNotifierProvider.autoDispose<DashboardNotifier, DashboardState>((ref) =>
    DashboardNotifier(
      api: HttpDashboardApi(),
      discovery: MdnsDashboardDiscovery(),
      tokens: SecureDashboardTokenStore(),
    ));
