// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:math' as math;

import 'package:oui_spy/core/assistant/assistant_grants.dart';

abstract class AssistantEnv {
  bool get boardLinked;
  Future<Map<String, dynamic>> health();
  List<Map<String, dynamic>> devices();
  Future<List<Map<String, dynamic>>> alerts();
  Map<String, dynamic> names();
  List<Map<String, dynamic>> drones();
  Map<String, dynamic> wardrive();
  List<Map<String, dynamic>> mesh();
  Future<List<Map<String, dynamic>>> captures();
  ({double lat, double lon})? positionOf(String place);
  Future<String> setEngine(String engine, bool on);
  Future<String> setCapture(bool start);
  Future<String> setAlias(String mac, String name);
  Future<String> reboot();
  Future<String> factoryReset();
  Future<String> wipeWifiCredentials();
}

enum ToolRisk { read, local, board, danger }

class ToolRequest {
  const ToolRequest({required this.name, required this.title, required this.args, required this.risk, required this.summary});
  final String name;
  final String title;
  final Map<String, dynamic> args;
  final ToolRisk risk;
  final String summary;
}

class ToolResult {
  const ToolResult(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

typedef ToolConfirm = Future<bool> Function(ToolRequest request);

class ToolContext {
  const ToolContext({required this.env, required this.loc, required this.now});
  final AssistantEnv env;
  final bool loc;
  final DateTime now;
}

class AssistantTool {
  const AssistantTool({
    required this.name,
    required this.title,
    required this.description,
    required this.schema,
    required this.needs,
    required this.risk,
    required this.run,
    required this.describe,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, dynamic> schema;
  final Set<AssistantGrant> needs;
  final ToolRisk risk;
  final Future<Object?> Function(Map<String, dynamic> args, ToolContext ctx) run;
  final String Function(Map<String, dynamic> args) describe;

  Map<String, dynamic> toJson() => {'name': name, 'title': title, 'description': description, 'inputSchema': schema};
}

const maxToolText = 6000;
const boardEngines = ['detector', 'flockBle', 'flockWifi', 'skySpy'];
const _positionKeys = {'lat', 'lon', 'pilot_lat', 'pilot_lon', 'drone_lat', 'drone_lon'};

Map<String, dynamic> _schema([Map<String, dynamic> props = const {}, List<String> required = const []]) => {
      'type': 'object',
      'properties': props,
      if (required.isNotEmpty) 'required': required,
    };

Map<String, dynamic> _str(String description, {List<String>? values}) =>
    {'type': 'string', 'description': description, 'enum': ?values};

Map<String, dynamic> _int(String description, int min, int max) =>
    {'type': 'integer', 'description': description, 'minimum': min, 'maximum': max};

String? _argStr(Map<String, dynamic> a, String k) {
  final v = a[k];
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

int? _argInt(Map<String, dynamic> a, String k) {
  final v = a[k];
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

int _limit(Map<String, dynamic> a) => (_argInt(a, 'limit') ?? 20).clamp(1, 100);

String _iso(Object? ms) => ms is int && ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String() : '';

Map<String, dynamic> _clean(Map<String, dynamic> m, bool loc) {
  final out = <String, dynamic>{};
  for (final e in m.entries) {
    if (e.value == null) continue;
    if (!loc && _positionKeys.contains(e.key)) continue;
    if (e.key.endsWith('_ms')) {
      out['${e.key.substring(0, e.key.length - 3)}_at'] = _iso(e.value);
      continue;
    }
    out[e.key] = e.value;
  }
  return out;
}

bool _matches(Map<String, dynamic> m, String? q, List<String> keys) {
  if (q == null) return true;
  final needle = q.toLowerCase();
  return keys.any((k) => '${m[k] ?? ''}'.toLowerCase().contains(needle));
}

bool _recent(Map<String, dynamic> m, String key, Map<String, dynamic> a, DateTime now) {
  final mins = _argInt(a, 'since_minutes');
  if (mins == null) return true;
  final last = m[key];
  return last is int && last >= now.millisecondsSinceEpoch - mins * 60000;
}

double metersBetween(double aLat, double aLon, double bLat, double bLon) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(bLat - aLat);
  final dLon = rad(bLon - aLon);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(aLat)) * math.cos(rad(bLat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

int _ms(Map<String, dynamic> m, String k) => m[k] is int ? m[k] as int : 0;

List<AssistantTool> _buildTools() => [
      AssistantTool(
        name: 'app_health',
        title: 'App and board health',
        description:
            'The phone app and its link now: app version, whether a board is linked, which board, its protocol, which engines run, the mesh and the wardriver. Always readable while the assistant is on.',
        schema: _schema(),
        needs: const {},
        risk: ToolRisk.read,
        run: (a, c) => c.env.health(),
        describe: (_) => 'Read app and board health',
      ),
      AssistantTool(
        name: 'app_devices',
        title: 'Devices seen',
        description:
            'Devices the app has seen: name or your alias, maker, kind and radio, what a detector matched, first and last heard and the best signal. Newest first unless sorted otherwise.',
        schema: _schema({
          'query': _str('Match a MAC, name, alias, maker or kind'),
          'since_minutes': _int('Only devices heard in the last N minutes', 1, 100000),
          'limit': _int('How many (default 20)', 1, 100),
          'sort': _str('recent (default), signal (strongest first) or first (earliest heard first)',
              values: ['recent', 'signal', 'first']),
        }),
        needs: const {AssistantGrant.devices},
        risk: ToolRisk.read,
        run: (a, c) async {
          final q = _argStr(a, 'query');
          final rows = [
            for (final d in c.env.devices())
              if (_matches(d, q, const ['mac', 'name', 'alias', 'maker', 'type']) && _recent(d, 'last_ms', a, c.now)) d,
          ];
          rows.sort(switch (_argStr(a, 'sort') ?? 'recent') {
            'signal' => (x, y) => _ms(y, 'best_rssi').compareTo(_ms(x, 'best_rssi')),
            'first' => (x, y) => _ms(x, 'first_ms').compareTo(_ms(y, 'first_ms')),
            _ => (x, y) => _ms(y, 'last_ms').compareTo(_ms(x, 'last_ms')),
          });
          return {
            'total': rows.length,
            'devices': [for (final d in rows.take(_limit(a))) _clean(d, c.loc)],
          };
        },
        describe: (_) => 'Read devices seen',
      ),
      AssistantTool(
        name: 'app_alerts',
        title: 'Alerts',
        description: 'The alerts raised for new or watched devices, newest first, with what matched.',
        schema: _schema({
          'query': _str('Match a MAC, name or reason'),
          'limit': _int('How many (default 20)', 1, 100),
        }),
        needs: const {AssistantGrant.devices},
        risk: ToolRisk.read,
        run: (a, c) async {
          final q = _argStr(a, 'query');
          final rows = [
            for (final d in await c.env.alerts())
              if (_matches(d, q, const ['mac', 'name', 'why', 'class'])) d,
          ];
          return {'total': rows.length, 'alerts': [for (final d in rows.take(_limit(a))) _clean(d, c.loc)]};
        },
        describe: (_) => 'Read alerts',
      ),
      AssistantTool(
        name: 'app_names',
        title: 'Names and watchlist',
        description: 'Your own names for devices (aliases) and the watchlist entries that raise an alert.',
        schema: _schema(),
        needs: const {AssistantGrant.devices},
        risk: ToolRisk.read,
        run: (a, c) async => c.env.names(),
        describe: (_) => 'Read names and watchlist',
      ),
      AssistantTool(
        name: 'app_drones',
        title: 'Remote ID drones',
        description:
            'Remote ID drones: serial, operator ID, first and last heard, altitude, height, speed, heading and signal. Newest first.',
        schema: _schema({
          'query': _str('Match a serial, MAC or operator ID'),
          'limit': _int('How many (default 20)', 1, 100),
        }),
        needs: const {AssistantGrant.drones},
        risk: ToolRisk.read,
        run: (a, c) async {
          final q = _argStr(a, 'query');
          final rows = [
            for (final d in c.env.drones())
              if (_matches(d, q, const ['serial', 'mac', 'operator_id'])) d,
          ];
          return {'total': rows.length, 'drones': [for (final d in rows.take(_limit(a))) _clean(d, c.loc)]};
        },
        describe: (_) => 'Read drones',
      ),
      AssistantTool(
        name: 'app_wardrive',
        title: 'Wardriver',
        description: 'The wardriver: its state and how many Wi-Fi and Bluetooth devices it has.',
        schema: _schema(),
        needs: const {AssistantGrant.wardrive},
        risk: ToolRisk.read,
        run: (a, c) async => _clean(c.env.wardrive(), c.loc),
        describe: (_) => 'Read wardriver counts',
      ),
      AssistantTool(
        name: 'app_mesh',
        title: 'Mesh nodes',
        description: 'The mesh nodes: id and name, board, temperature, firmware, filters, peers, uptime and when last heard.',
        schema: _schema(),
        needs: const {AssistantGrant.mesh},
        risk: ToolRisk.read,
        run: (a, c) async => {'nodes': [for (final n in c.env.mesh()) _clean(n, c.loc)]},
        describe: (_) => 'Read mesh nodes',
      ),
      AssistantTool(
        name: 'app_captures',
        title: 'Capture files',
        description: 'The saved PCAP capture files: name, size and when written. File contents are never sent.',
        schema: _schema(),
        needs: const {AssistantGrant.files},
        risk: ToolRisk.read,
        run: (a, c) async => {'files': [for (final f in await c.env.captures()) _clean(f, c.loc)]},
        describe: (_) => 'List capture files',
      ),
      AssistantTool(
        name: 'app_near',
        title: 'What was near a place',
        description:
            'Devices and drones with a recorded position within a radius of this phone, a mesh node or a position, nearest first. Needs LOCATION.',
        schema: _schema({
          'place': _str('me (this phone), a mesh node id, or "lat,lon"'),
          'radius_m': _int('Meters (default 250)', 10, 20000),
          'limit': _int('How many (default 20)', 1, 100),
        }, const ['place']),
        needs: const {AssistantGrant.devices, AssistantGrant.drones, AssistantGrant.loc},
        risk: ToolRisk.read,
        run: (a, c) async {
          final place = _argStr(a, 'place') ?? 'me';
          final at = c.env.positionOf(place);
          if (at == null) return {'error': 'no position known for "$place"'};
          final radius = (_argInt(a, 'radius_m') ?? 250).clamp(10, 20000);
          final found = <Map<String, dynamic>>[];
          void add(String what, Map<String, dynamic> m, Object? lat, Object? lon) {
            if (lat is! num || lon is! num) return;
            final d = metersBetween(at.lat, at.lon, lat.toDouble(), lon.toDouble());
            if (d > radius) return;
            found.add({
              'what': what,
              'name': m['alias'] ?? m['name'] ?? m['serial'] ?? m['mac'],
              'mac': m['mac'],
              'distance_m': d.round(),
              'lat': lat,
              'lon': lon,
              'last_ms': m['last_ms'],
            });
          }

          for (final d in c.env.devices()) {
            add('device', d, d['lat'], d['lon']);
          }
          for (final d in c.env.drones()) {
            add('drone', d, d['drone_lat'], d['drone_lon']);
            add('drone pilot', d, d['pilot_lat'], d['pilot_lon']);
          }
          found.sort((x, y) => (x['distance_m'] as int).compareTo(y['distance_m'] as int));
          return {'radius_m': radius, 'found': found.length, 'nearest': [for (final f in found.take(_limit(a))) _clean(f, true)]};
        },
        describe: (_) => 'Read what was near a place',
      ),
      AssistantTool(
        name: 'app_device_action',
        title: 'Name a device',
        description: 'Gives a device your own name in the app (an empty name clears it). Changes nothing on the board.',
        schema: _schema({
          'mac': _str('The device, AA:BB:CC:DD:EE:FF'),
          'name': _str('The name; empty clears it'),
        }, const ['mac', 'name']),
        needs: const {AssistantGrant.control},
        risk: ToolRisk.local,
        run: (a, c) async {
          final mac = _argStr(a, 'mac')?.toUpperCase() ?? '';
          if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(mac)) {
            return {'error': 'mac must be AA:BB:CC:DD:EE:FF'};
          }
          return {'ok': true, 'result': await c.env.setAlias(mac, (a['name'] as String?)?.trim() ?? '')};
        },
        describe: (a) => 'Name ${a['mac']} "${a['name']}"',
      ),
      AssistantTool(
        name: 'board_engine',
        title: 'Turn a scan engine on or off',
        description:
            'Turns one scan engine on the linked board on or off: detector, flockBle, flockWifi or skySpy. Needs your OK for every call.',
        schema: _schema({
          'engine': _str('The engine', values: boardEngines),
          'action': _str('on or off', values: ['on', 'off']),
        }, const ['engine', 'action']),
        needs: const {AssistantGrant.control},
        risk: ToolRisk.board,
        run: (a, c) async {
          final engine = _argStr(a, 'engine') ?? '';
          final action = _argStr(a, 'action') ?? '';
          if (!boardEngines.contains(engine)) return {'error': 'engine must be one of ${boardEngines.join(', ')}'};
          if (action != 'on' && action != 'off') return {'error': 'action is on or off'};
          return {'ok': true, 'result': await c.env.setEngine(engine, action == 'on')};
        },
        describe: (a) => 'Turn the ${a['engine']} engine ${a['action']}',
      ),
      AssistantTool(
        name: 'board_capture',
        title: 'Start or stop a packet capture',
        description: 'Starts or stops a passive PCAP capture on the linked board. Needs your OK for every call.',
        schema: _schema({'action': _str('start or stop', values: ['start', 'stop'])}, const ['action']),
        needs: const {AssistantGrant.control},
        risk: ToolRisk.board,
        run: (a, c) async {
          final action = _argStr(a, 'action');
          if (action != 'start' && action != 'stop') return {'error': 'action is start or stop'};
          return {'ok': true, 'result': await c.env.setCapture(action == 'start')};
        },
        describe: (a) => '${a['action'] == 'start' ? 'Start' : 'Stop'} the packet capture',
      ),
      AssistantTool(
        name: 'board_reboot',
        title: 'Restart the board',
        description: 'Restarts the linked board. Its settings are kept. Needs your OK for every call.',
        schema: _schema(),
        needs: const {AssistantGrant.control},
        risk: ToolRisk.board,
        run: (a, c) async => {'ok': true, 'result': await c.env.reboot()},
        describe: (_) => 'Restart the board',
      ),
      AssistantTool(
        name: 'board_factory_reset',
        title: 'Factory reset the board',
        description: 'Erases the linked board\'s saved settings and restarts it. Irreversible. Needs the IRREVERSIBLE grant and your OK.',
        schema: _schema(),
        needs: const {AssistantGrant.danger},
        risk: ToolRisk.danger,
        run: (a, c) async => {'ok': true, 'result': await c.env.factoryReset()},
        describe: (_) => 'FACTORY RESET the board (erases its settings)',
      ),
      AssistantTool(
        name: 'board_wipe_wifi',
        title: 'Wipe the board\'s saved Wi-Fi login',
        description: 'Erases the Wi-Fi network and password saved on the linked board. Irreversible. Needs the IRREVERSIBLE grant and your OK.',
        schema: _schema(),
        needs: const {AssistantGrant.danger},
        risk: ToolRisk.danger,
        run: (a, c) async => {'ok': true, 'result': await c.env.wipeWifiCredentials()},
        describe: (_) => 'WIPE the Wi-Fi login saved on the board',
      ),
    ];

class AssistantToolbox {
  AssistantToolbox(this.env, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AssistantEnv env;
  final DateTime Function() _clock;

  static final List<AssistantTool> all = List.unmodifiable(_buildTools());

  static AssistantTool? byName(String name) {
    for (final t in all) {
      if (t.name == name) return t;
    }
    return null;
  }

  static bool granted(AssistantTool t, AssistantAccess a) => a.on && t.needs.every(a.has);

  static List<AssistantTool> offered(AssistantAccess a) => [for (final t in all) if (granted(t, a)) t];

  static String missing(AssistantTool t, AssistantAccess a) {
    if (!a.on) return 'the assistant is off (Settings > Data > Assistant).';
    final miss = [for (final g in t.needs) if (!a.has(g)) g.label];
    return '${miss.join(', ')} not granted (Settings > Data > Assistant). Do not try to get around it.';
  }

  Future<ToolResult> call(
    String name,
    Map<String, dynamic> args,
    AssistantAccess access,
    ToolConfirm confirm,
  ) async {
    final tool = byName(name);
    if (tool == null) return ToolResult('No tool named "$name".', isError: true);
    if (!granted(tool, access)) return ToolResult('Not allowed: ${missing(tool, access)}', isError: true);
    final touchesBoard = tool.risk == ToolRisk.board || tool.risk == ToolRisk.danger;
    if (touchesBoard && !env.boardLinked) return const ToolResult('No board is linked.', isError: true);
    if (touchesBoard) {
      final ok = await confirm(ToolRequest(
        name: tool.name,
        title: tool.title,
        args: args,
        risk: tool.risk,
        summary: tool.describe(args),
      ));
      if (!ok) return const ToolResult('Not run: the person declined.', isError: true);
    }
    final loc = access.has(AssistantGrant.loc);
    try {
      final out = await tool.run(args, ToolContext(env: env, loc: loc, now: _clock()));
      var text = out is String ? out : const JsonEncoder().convert(out);
      if (!loc) text = hidePositions(text);
      if (text.length > maxToolText) {
        text = '${text.substring(0, maxToolText)}... (cut at $maxToolText characters: ask for fewer, or narrow it)';
      }
      return ToolResult(text, isError: out is Map && out['error'] != null);
    } on Object catch (e) {
      return ToolResult('The app could not answer that: $e', isError: true);
    }
  }
}
