// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/assistant/assistant_tools.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/mesh_node_info.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/node_positions.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/watchlist_state.dart';

class LiveAssistantEnv implements AssistantEnv {
  LiveAssistantEnv(this._ref);
  final Ref _ref;

  AppState get _app => _ref.read(appStateProvider);
  BleManager get _ble => _ref.read(bleManagerProvider);

  @override
  bool get boardLinked => _app.isConnected;

  @override
  Future<Map<String, dynamic>> health() async {
    final info = await PackageInfo.fromPlatform();
    final wd = _ref.read(wardriveProvider);
    return {
      'app_version': info.version,
      'board_linked': _app.isConnected,
      'link_state': _ble.currentConnectionState.name,
      if (_app.isConnected) 'board': _ble.board,
      if (_app.isConnected) 'node_id': _app.nodeId,
      if (_ble.protoVersion != null) 'protocol': _ble.protoVersion,
      'engines_running': [for (final e in Engine.values) if (_app.isEngineActive(e)) e.name],
      'mesh_enabled': _app.meshEnabled,
      'mesh_peers': _app.meshPeerCount,
      'wardrive_state': wd.state.name,
      'devices_seen': _ref.read(deviceRegistryProvider).count,
    };
  }

  @override
  List<Map<String, dynamic>> devices() {
    final notes = _ref.read(deviceNotesProvider);
    return [
      for (final d in _ref.read(deviceRegistryProvider).devices)
        () {
          final o = d.obs;
          final trail = o.gpsTrail;
          return <String, dynamic>{
            'mac': o.mac.toUpperCase(),
            'name': o.name,
            if ((notes[DeviceNotesNotifier.keyOf(o.mac)]?.name ?? '').isNotEmpty)
              'alias': notes[DeviceNotesNotifier.keyOf(o.mac)]!.name,
            'maker': d.vendor ?? d.baseVendor ?? '',
            'type': d.guess.headline,
            'radio': o.kind.name,
            'random_address': o.randomized,
            'rssi': o.rssi,
            'best_rssi': o.rssiMax,
            'first_ms': o.firstSeenMs,
            'last_ms': o.lastSeenMs,
            'channel': o.channel == 0 ? null : o.channel,
            'matched': [
              ...d.signatureNames,
              if (o.detectorDesc != null && o.detectorDesc!.isNotEmpty) o.detectorDesc!,
            ],
            'lat': trail.isEmpty ? null : trail.last.lat,
            'lon': trail.isEmpty ? null : trail.last.lon,
          };
        }(),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> alerts() async {
    final rows = await _ref.read(databaseProvider).getClassAlertMaps();
    return [
      for (final r in rows)
        {
          'mac': r['macAddress'],
          'name': r['deviceName'],
          'class': r['alertClass'],
          'why': r['detectionMethod'],
          'radio': r['isBle'] == true ? 'ble' : 'wifi',
          'rssi': r['rssi'],
          'count': r['count'],
          'last_ms': r['appTimestamp'],
          'first_ms': r['firstAlertedAt'],
          'lat': r['latitude'],
          'lon': r['longitude'],
        },
    ];
  }

  @override
  Map<String, dynamic> names() => {
        'aliases': [
          for (final e in _ref.read(deviceNotesProvider).entries)
            if (e.value.name.trim().isNotEmpty) {'mac': e.key, 'name': e.value.name, if (e.value.group.isNotEmpty) 'group': e.value.group},
        ],
        'watchlist': [
          for (final w in _ref.read(watchlistProvider).entries)
            {'match': w.matchType.label, 'identifier': w.identifier, 'description': w.description, 'enabled': w.enabled},
        ],
      };

  @override
  List<Map<String, dynamic>> drones() => [
        for (final d in _ref.read(wardriveProvider).droneDetections)
          {
            'serial': d.odid?.uavId ?? '',
            'mac': d.macAddress.toUpperCase(),
            'operator_id': d.odid?.operatorId,
            'rssi': d.rssi,
            'last_ms': d.appTimestamp.millisecondsSinceEpoch,
            'altitude_m': d.odid?.altitudeMsl,
            'height_m': d.odid?.heightAgl,
            'speed': d.odid?.droneSpeed,
            'heading': d.odid?.droneHeading,
            'drone_lat': d.odid?.droneLat,
            'drone_lon': d.odid?.droneLon,
            'pilot_lat': d.odid?.pilotLat,
            'pilot_lon': d.odid?.pilotLon,
          },
      ];

  @override
  Map<String, dynamic> wardrive() {
    final wd = _ref.read(wardriveProvider);
    return {
      'state': wd.state.name,
      'wifi_devices': wd.rawWifiCount,
      'ble_devices': wd.rawBleCount,
      'drones': wd.droneCount,
      'distance_km': double.parse(wd.distanceKm.toStringAsFixed(2)),
    };
  }

  @override
  List<Map<String, dynamic>> mesh() {
    final app = _app;
    return [
      for (final id in app.knownNodes)
        () {
          final d = app.nodeDetail(id);
          return <String, dynamic>{
            'id': id,
            'name': app.labelForNode(id),
            'board': app.nodeBoard(id),
            'temp_c': app.nodeTempC(id),
            'online': app.liveKnownNodes.contains(id),
            if (d != null) 'firmware': formatFwVersion(d.fwVersion),
            if (d != null) 'filters': d.filterMacs + d.filterUuids,
            if (d != null) 'peers': d.peerCount,
            if (d != null) 'uptime_s': d.uptimeS,
          };
        }(),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> captures() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/pcaps');
    if (!await dir.exists()) return const [];
    final out = <Map<String, dynamic>>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.pcap')) continue;
      final st = await f.stat();
      out.add({'name': f.uri.pathSegments.last, 'bytes': st.size, 'written_ms': st.modified.millisecondsSinceEpoch});
    }
    out.sort((a, b) => (b['written_ms'] as int).compareTo(a['written_ms'] as int));
    return out;
  }

  @override
  ({double lat, double lon})? positionOf(String place) {
    final p = place.trim();
    if (p == 'me') {
      final g = _ref.read(gpsProvider).recentPosition();
      return g == null ? null : (lat: g.latitude, lon: g.longitude);
    }
    final pair = RegExp(r'^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$').firstMatch(p);
    if (pair != null) {
      final lat = double.parse(pair[1]!);
      final lon = double.parse(pair[2]!);
      return lat.abs() <= 90 && lon.abs() <= 180 ? (lat: lat, lon: lon) : null;
    }
    final node = _ref.read(nodePositionsProvider)[AppState.canonicalNodeId(p)];
    return node == null ? null : (lat: node.latitude, lon: node.longitude);
  }

  @override
  Future<String> setEngine(String engine, bool on) async {
    final e = Engine.values.firstWhere((x) => x.name == engine);
    final wd = _ref.read(wardriveProvider);
    if (!on && wd.ownsEngine(e)) {
      await wd.stopOwnedEngine(e);
      return '${e.label} stopped';
    }
    if (on) {
      await _ble.enableEngine(e, radio: _app.engineRadio[e]);
    } else {
      await _ble.disableEngine(e);
    }
    return '${e.label} ${on ? 'on' : 'off'} sent to the board';
  }

  @override
  Future<String> setCapture(bool start) async {
    if (start) {
      await _ble.startPcap();
    } else {
      await _ble.stopPcap();
    }
    return 'Capture ${start ? 'start' : 'stop'} sent to the board';
  }

  @override
  Future<String> setAlias(String mac, String name) async {
    final notes = _ref.read(deviceNotesProvider.notifier);
    final prev = _ref.read(deviceNotesProvider)[DeviceNotesNotifier.keyOf(mac)] ?? const DeviceNote();
    await notes.set(mac, DeviceNote(name: name, group: prev.group, notes: prev.notes));
    return name.isEmpty ? 'Name cleared' : 'Named "$name"';
  }

  @override
  Future<String> reboot() async {
    await _ble.rebootDevice();
    return 'Restart sent to the board';
  }

  @override
  Future<String> factoryReset() async {
    await _ble.factoryReset();
    return 'Factory reset sent to the board';
  }

  @override
  Future<String> wipeWifiCredentials() async {
    await _ble.wipeWifiCreds();
    return 'Wi-Fi login wipe sent to the board';
  }
}

final assistantEnvProvider = Provider<AssistantEnv>((ref) => LiveAssistantEnv(ref));
final assistantToolboxProvider = Provider<AssistantToolbox>((ref) => AssistantToolbox(ref.read(assistantEnvProvider)));
