// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/sqlite_guard.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/db/tables.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/metrics/fleet_metrics.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Aggregate stats over all collected detections (for the Wardrive config tab).
class ArchiveOverview {
  const ArchiveOverview({
    required this.detections,
    required this.devices,
    required this.withGps,
    required this.sessions,
    required this.firstMs,
    required this.lastMs,
    required this.byEngine,
  });
  final int detections;
  final int devices;
  final int withGps;
  final int sessions;
  final int? firstMs;
  final int? lastMs;
  final List<({String engine, int detections, int devices})> byEngine;
}

class ArchiveHit {
  const ArchiveHit({
    required this.mac,
    required this.engine,
    required this.firstMs,
    required this.lastMs,
    required this.bestRssi,
    required this.sightings,
    required this.ssid,
    required this.name,
    required this.description,
  });
  final String mac;
  final String engine;
  final int firstMs;
  final int lastMs;
  final int bestRssi;
  final int sightings;
  final String ssid;
  final String name;
  final String description;
}

class CollectionStats {
  CollectionStats({
    required this.totalUnique,
    required this.wifiUnique,
    required this.bleUnique,
    required this.totalDetections,
    required this.sessionCount,
    required this.ssidCount,
    required this.channelCounts,
    required this.authCounts,
    required this.ouiCounts,
    required this.flockOuiCounts,
  });

  final int totalUnique;
  final int wifiUnique;
  final int bleUnique;
  final int totalDetections;
  final int sessionCount;
  final int ssidCount;
  final Map<int, int> channelCounts;
  final Map<int, int> authCounts;
  final List<MapEntry<String, int>> ouiCounts;
  final List<MapEntry<String, int>> flockOuiCounts;

  bool get isEmpty => totalUnique == 0;
}

@DriftDatabase(tables: [
  Nodes,
  Sessions,
  Detections,
  EngineConfigs,
  Baselines,
  BaselineDevices,
  Fingerprints,
  FingerprintMacs,
  Geofences,
  GeofenceAlerts,
  StalkingSuspects,
  WigleUploads,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_detections_session ON detections (session_id)');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_detections_mac ON detections (mac_address)');
        await customStatement(_classAlertsDdl);
        await _ensureDetectionExtTable();
        await _ensureSessionTrackTable();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(detections, detections.authMode);
        }
        if (from < 3) {
          await m.addColumn(geofences, geofences.excludeFromWardrive);
        }
        if (from < 4) {
          await m.addColumn(detections, detections.approxGps);
        }
        if (from < 5) {
          final existing = await customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='wigle_uploads'",
          ).get();
          if (existing.isEmpty) {
            await m.createTable(wigleUploads);
          }
        }
        if (from < 6) {
          await m.addColumn(detections, detections.flockSignals);
        }
        if (from < 7) {
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_detections_session ON detections (session_id)');
        }
        if (from < 8) {
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_detections_mac ON detections (mac_address)');
        }
        if (from < 9) {
          await customStatement(_classAlertsDdl);
        }
        if (from < 10) {
          await _ensureDetectionExtTable();
          await _ensureClassAlertSessionColumn();
        }
        if (from < 11) {
          await _ensureSessionTrackTable();
        }
      },
    );
  }

  // -- Node operations --

  Future<List<Node>> getAllNodes() => select(nodes).get();

  Future<void> upsertNode(NodesCompanion node) =>
      into(nodes).insertOnConflictUpdate(node);

  Future<void> updateNodeName(String id, String name) =>
      (update(nodes)..where((n) => n.id.equals(id)))
          .write(NodesCompanion(name: Value(name)));

  Future<void> updateNodeLastSeen(String id, int timestampMs) =>
      (update(nodes)..where((n) => n.id.equals(id)))
          .write(NodesCompanion(lastSeen: Value(timestampMs)));

  Future<void> deleteNode(String id) =>
      (delete(nodes)..where((n) => n.id.equals(id))).go();

  Stream<List<Node>> watchAllNodes() => select(nodes).watch();

  // -- Session operations --

  Future<void> insertSession(SessionsCompanion session) =>
      into(sessions).insert(session);

  Future<void> updateSession(SessionsCompanion session) =>
      (update(sessions)..where((s) => s.id.equals(session.id.value)))
          .write(session);

  Future<List<Session>> getSessionsForNode(String nodeId) =>
      (select(sessions)..where((s) => s.nodeId.equals(nodeId))).get();

  Future<List<Session>> getWardriveSessions() =>
      (select(sessions)
            ..where((s) => s.isWardrive.equals(true))
            ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
          .get();

  Future<Session?> getSessionById(String id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Stream<List<Session>> watchAllSessions() =>
      (select(sessions)..orderBy([(s) => OrderingTerm.desc(s.startedAt)])).watch();

  Future<List<Session>> getAllSessions() =>
      (select(sessions)..orderBy([(s) => OrderingTerm.desc(s.startedAt)])).get();

  Future<void> deleteSession(String id) async {
    await transaction(() async {
      await (delete(detections)..where((d) => d.sessionId.equals(id))).go();
      await customStatement('DELETE FROM session_track WHERE session_id = ?', [id]);
      await (delete(sessions)..where((s) => s.id.equals(id))).go();
    });
  }

  Future<void> deleteSessions(List<String> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
        await (delete(detections)..where((d) => d.sessionId.isIn(chunk))).go();
        await customStatement(
            'DELETE FROM session_track WHERE session_id IN (${List.filled(chunk.length, '?').join(',')})',
            chunk);
        await (delete(sessions)..where((s) => s.id.isIn(chunk))).go();
      }
    });
  }

  static const _sessionTrackDdl = 'CREATE TABLE IF NOT EXISTS session_track ('
      'session_id TEXT NOT NULL, '
      'ts INTEGER NOT NULL, '
      'lat REAL NOT NULL, '
      'lon REAL NOT NULL)';

  Future<void> _ensureSessionTrackTable() async {
    await customStatement(_sessionTrackDdl);
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_session_track ON session_track (session_id, ts)');
  }

  Future<void> insertTrackPoints(String sessionId, List<({int ts, double lat, double lon})> pts) async {
    if (sessionId.isEmpty || pts.isEmpty) return;
    await transaction(() async {
      for (final p in pts) {
        await customInsert(
          'INSERT INTO session_track (session_id, ts, lat, lon) VALUES (?, ?, ?, ?)',
          variables: [
            Variable.withString(sessionId),
            Variable.withInt(p.ts),
            Variable.withReal(p.lat),
            Variable.withReal(p.lon),
          ],
        );
      }
    });
  }

  Future<List<({int ts, double lat, double lon})>> getSessionTrack(String sessionId) async {
    final rows = await customSelect(
      'SELECT ts, lat, lon FROM session_track WHERE session_id = ? ORDER BY ts ASC',
      variables: [Variable.withString(sessionId)],
    ).get();
    return [
      for (final r in rows)
        (ts: r.read<int>('ts'), lat: r.read<double>('lat'), lon: r.read<double>('lon')),
    ];
  }

  // -- Detection operations --

  Future<void> insertDetection(DetectionsCompanion detection,
          {Map<String, Object?> ext = const {}}) =>
      insertDetectionRow(detection, ext: ext);

  Future<int> insertDetectionRow(DetectionsCompanion detection,
      {Map<String, Object?> ext = const {}}) async {
    final id = await into(detections).insert(detection);
    if (ext.isNotEmpty) await _putDetectionExt(id, ext);
    return id;
  }

  Future<void> updateDetectionRow(int id, DetectionsCompanion detection,
      {Map<String, Object?> ext = const {}}) async {
    await (update(detections)..where((d) => d.id.equals(id))).write(detection);
    if (ext.isNotEmpty) await _putDetectionExt(id, ext);
  }

  Future<void> batchInsertDetections(List<DetectionsCompanion> batch) async {
    await this.batch((b) {
      b.insertAll(detections, batch);
    });
  }

  Future<List<Detection>> getDetectionsForSession(String sessionId) =>
      (select(detections)
            ..where((d) => d.sessionId.equals(sessionId))
            ..orderBy([(d) => OrderingTerm.desc(d.appTimestamp)]))
          .get();

  Map<String, dynamic> _detectionRowMap(Detection r) => {
        'id': r.id,
        'sessionId': r.sessionId,
        'nodeId': r.nodeId,
        'macAddress': r.macAddress,
        'deviceName': r.deviceName,
        'engine': r.engine,
        'detectionMethod': r.detectionMethod,
        'rssi': r.rssi,
        'channel': r.channel,
        'deviceTimestampMs': r.deviceTimestampMs,
        'appTimestamp': r.appTimestamp,
        'ssid': r.ssid,
        'authMode': r.authMode,
        'count': r.count,
        'latitude': r.latitude,
        'longitude': r.longitude,
        'altitude': r.altitude,
        'speed': r.speed,
        'heading': r.heading,
        'accuracy': r.accuracy,
        'satelliteCount': r.satelliteCount,
        'uavId': r.uavId,
        'operatorId': r.operatorId,
        'droneLat': r.droneLat,
        'droneLon': r.droneLon,
        'altitudeMsl': r.altitudeMsl,
        'heightAgl': r.heightAgl,
        'droneSpeed': r.droneSpeed,
        'droneHeading': r.droneHeading,
        'pilotLat': r.pilotLat,
        'pilotLon': r.pilotLon,
        'approxGps': r.approxGps,
        'isRaven': r.isRaven,
        'ravenFirmware': r.ravenFirmware,
        'flockSignals': r.flockSignals,
        'robotType': r.robotType,
        'exploited': r.exploited,
        'robotSerial': r.robotSerial,
        'filterDescription': r.filterDescription,
        'isFullMac': r.isFullMac,
      };

  Future<List<Map<String, dynamic>>> getDetectionMapsForSession(
      String sessionId) async {
    final rows = await (select(detections)
          ..where((d) => d.sessionId.equals(sessionId))
          ..orderBy([(d) => OrderingTerm.asc(d.appTimestamp), (d) => OrderingTerm.asc(d.id)]))
        .get();
    return _mapsWithExt(rows, sessionId: sessionId);
  }

  Future<List<Map<String, dynamic>>> getDetectionMapsForMac(String mac) async {
    final rows = await (select(detections)
          ..where((d) => d.macAddress.equals(mac.toUpperCase()) | d.macAddress.equals(mac.toLowerCase()))
          ..orderBy([(d) => OrderingTerm.asc(d.appTimestamp), (d) => OrderingTerm.asc(d.id)]))
        .get();
    return _mapsWithExt(rows);
  }

  Future<List<Map<String, dynamic>>> getAllDetectionMaps() async {
    final rows = await (select(detections)
          ..orderBy([(d) => OrderingTerm.desc(d.appTimestamp)]))
        .get();
    return _mapsWithExt(rows);
  }

  Future<List<Map<String, dynamic>>> getNonDroneDetectionMapsBetween(
      DateTime from, DateTime to) async {
    final rows = await (select(detections)
          ..where((d) =>
              d.appTimestamp.isBetweenValues(
                  from.millisecondsSinceEpoch, to.millisecondsSinceEpoch) &
              d.engine.equals('skySpy').not())
          ..orderBy([(d) => OrderingTerm.asc(d.appTimestamp)]))
        .get();
    return _mapsWithExt(rows);
  }

  static const _detectionExtDdl = 'CREATE TABLE IF NOT EXISTS detection_ext ('
      'detection_id INTEGER PRIMARY KEY, '
      'data TEXT NOT NULL)';

  Future<void> _ensureDetectionExtTable() async {
    await customStatement(_detectionExtDdl);
    await customStatement('CREATE TRIGGER IF NOT EXISTS trg_detection_ext_delete '
        'AFTER DELETE ON detections BEGIN '
        'DELETE FROM detection_ext WHERE detection_id = OLD.id; END');
  }

  Future<void> _putDetectionExt(int id, Map<String, Object?> ext) => customInsert(
        'INSERT OR REPLACE INTO detection_ext (detection_id, data) VALUES (?, ?)',
        variables: [Variable.withInt(id), Variable.withString(jsonEncode(ext))],
      );

  Future<List<Map<String, dynamic>>> _mapsWithExt(List<Detection> rows,
      {String? sessionId}) async {
    final maps = rows.map(_detectionRowMap).toList();
    if (maps.isEmpty) return maps;
    final ext = sessionId == null
        ? await customSelect('SELECT detection_id, data FROM detection_ext').get()
        : await customSelect(
            'SELECT e.detection_id, e.data FROM detection_ext e '
            'JOIN detections d ON d.id = e.detection_id WHERE d.session_id = ?',
            variables: [Variable.withString(sessionId)],
          ).get();
    final byId = <int, Map<String, dynamic>>{};
    for (final e in ext) {
      final id = e.read<int>('detection_id');
      try {
        byId[id] = Map<String, dynamic>.from(jsonDecode(e.read<String>('data')) as Map);
      } on FormatException catch (err) {
        DebugLog.log('DB: detection_ext row $id unreadable, details skipped: $err');
      }
    }
    for (final m in maps) {
      final x = byId[m['id'] as int];
      if (x != null) m['ext'] = x;
    }
    return maps;
  }

  Future<int> uniqueMacCount(String sessionId) async {
    final query = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final result = await query.getSingle();
    return result.read(detections.macAddress.count(distinct: true)) ?? 0;
  }

  /// Distinct MACs stored, and how many were heard since [sinceMs].
  Future<({int kept, int since})> macCounts(int sinceMs) async {
    final r = await customSelect(
      'SELECT COUNT(DISTINCT lower(mac_address)) AS kept, '
      'COUNT(DISTINCT CASE WHEN app_timestamp >= ?1 THEN lower(mac_address) END) AS since '
      'FROM detections',
      variables: [Variable.withInt(sinceMs)],
      readsFrom: {detections},
    ).getSingle();
    return (kept: r.read<int>('kept'), since: r.read<int>('since'));
  }

  /// Distinct MACs heard in each of the 24 hours before [nowMs]; index 23 is the latest hour.
  Future<List<int>> hourlyMacCounts(int nowMs) async {
    final rows = await customSelect(
      'SELECT (?1 - app_timestamp) / 3600000 AS h, COUNT(DISTINCT lower(mac_address)) AS n '
      'FROM detections WHERE app_timestamp > ?1 - 86400000 AND app_timestamp <= ?1 GROUP BY h',
      variables: [Variable.withInt(nowMs)],
      readsFrom: {detections},
    ).get();
    final out = List<int>.filled(24, 0);
    for (final r in rows) {
      final h = r.read<int>('h');
      if (h >= 0 && h < 24) out[23 - h] = r.read<int>('n');
    }
    return out;
  }

  /// Count unique flock MACs in a session.
  Future<int> flockMacCount(String sessionId) async {
    final query = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..where(detections.engine.isIn(['flockBle', 'flockWifi']))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final result = await query.getSingle();
    return result.read(detections.macAddress.count(distinct: true)) ?? 0;
  }

  /// Count unique flock MACs across every stored session.
  Future<int> flockMacCountAll() async {
    final query = selectOnly(detections)
      ..where(detections.engine.isIn(['flockBle', 'flockWifi']))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final result = await query.getSingle();
    return result.read(detections.macAddress.count(distinct: true)) ?? 0;
  }

  /// Count unique detector (watchlist hit) MACs in a session.
  Future<int> detectorMacCount(String sessionId) async {
    final query = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..where(detections.engine.equals('detector'))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final result = await query.getSingle();
    return result.read(detections.macAddress.count(distinct: true)) ?? 0;
  }

  /// Count unique drone (Sky Spy / Remote ID) MACs in a session.
  Future<int> droneMacCount(String sessionId) async {
    final query = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..where(detections.engine.equals('skySpy'))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final result = await query.getSingle();
    return result.read(detections.macAddress.count(distinct: true)) ?? 0;
  }

  /// Count unique WiFi and BLE MACs in a session.
  Future<({int wifi, int ble})> wifiBleUniqueCounts(String sessionId) async {
    final wifiQuery = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..where(detections.detectionMethod.equals('wifi_ap'))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final wifiResult = await wifiQuery.getSingle();
    final wifi =
        wifiResult.read(detections.macAddress.count(distinct: true)) ?? 0;

    final bleQuery = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..where(detections.detectionMethod.equals('ble_adv'))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final bleResult = await bleQuery.getSingle();
    final ble =
        bleResult.read(detections.macAddress.count(distinct: true)) ?? 0;

    return (wifi: wifi, ble: ble);
  }

  Future<List<({String mac, String ssid, int auth, int channel, bool seenBefore})>> sessionAps(
      String sessionId, int startedAt) async {
    final rows = await customSelect(
      'SELECT d.mac_address AS mac, MAX(d.ssid) AS ssid, MAX(d.auth_mode) AS auth, MAX(d.channel) AS ch, '
      'EXISTS(SELECT 1 FROM detections e WHERE e.mac_address = d.mac_address '
      'AND e.session_id != ? AND e.app_timestamp < ?) AS seen '
      "FROM detections d WHERE d.session_id = ? AND d.detection_method = 'wifi_ap' GROUP BY d.mac_address",
      variables: [Variable.withString(sessionId), Variable.withInt(startedAt), Variable.withString(sessionId)],
    ).get();
    return [
      for (final r in rows)
        (
          mac: r.read<String>('mac'),
          ssid: r.readNullable<String>('ssid') ?? '',
          auth: r.read<int>('auth'),
          channel: r.read<int>('ch'),
          seenBefore: r.read<int>('seen') != 0,
        ),
    ];
  }

  static const int metricRowCap = 200000;

  Future<List<MetricRow>> metricRows(int fromMs, int toMs, {String? node}) async {
    await _ensureDetectionExtTable();
    final rows = await customSelect(
      'SELECT d.mac_address AS mac, d.engine AS engine, d.detection_method AS method, d.rssi AS rssi, '
      'd.channel AS channel, d.app_timestamp AS at, d.auth_mode AS auth, '
      '(d.latitude IS NOT NULL AND d.longitude IS NOT NULL) AS placed, '
      "COALESCE(json_extract(e.data, '\$.sourceNodeId'), '') AS node "
      'FROM detections d LEFT JOIN detection_ext e ON e.detection_id = d.id '
      'WHERE d.app_timestamp >= ? AND d.app_timestamp <= ? '
      "${node == null ? '' : "AND COALESCE(json_extract(e.data, '\$.sourceNodeId'), '') = ? "}"
      'ORDER BY d.app_timestamp DESC LIMIT $metricRowCap',
      variables: [Variable.withInt(fromMs), Variable.withInt(toMs), if (node != null) Variable.withString(node)],
    ).get();
    return [
      for (final r in rows)
        MetricRow(
          mac: r.read<String>('mac'),
          engine: r.read<String>('engine'),
          method: r.read<String>('method'),
          rssi: r.read<int>('rssi'),
          channel: r.read<int>('channel'),
          atMs: r.read<int>('at'),
          node: r.read<String>('node'),
          auth: r.read<int>('auth'),
          placed: r.read<int>('placed') != 0,
        ),
    ];
  }

  Future<Set<String>> metricNewMacs(int fromMs, int toMs, {String? node}) async {
    await _ensureDetectionExtTable();
    const nodeOf = "COALESCE(json_extract(%s.data, '\$.sourceNodeId'), '') = ?";
    final cur = node == null ? '' : 'AND ${nodeOf.replaceFirst('%s', 'e')} ';
    final prev = node == null ? '' : 'AND ${nodeOf.replaceFirst('%s', 'pe')} ';
    final rows = await customSelect(
      'SELECT DISTINCT d.mac_address AS mac FROM detections d LEFT JOIN detection_ext e ON e.detection_id = d.id '
      'WHERE d.app_timestamp >= ? AND d.app_timestamp <= ? $cur'
      'AND NOT EXISTS (SELECT 1 FROM detections p LEFT JOIN detection_ext pe ON pe.detection_id = p.id '
      'WHERE p.mac_address = d.mac_address AND p.app_timestamp < ? $prev)',
      variables: [
        Variable.withInt(fromMs),
        Variable.withInt(toMs),
        if (node != null) Variable.withString(node),
        Variable.withInt(fromMs),
        if (node != null) Variable.withString(node),
      ],
    ).get();
    return {for (final r in rows) r.read<String>('mac')};
  }

  Future<List<DroneReport>> metricDrones(int fromMs, int toMs, {String? node}) async {
    await _ensureDetectionExtTable();
    final rows = await customSelect(
      'SELECT d.mac_address AS mac, d.uav_id AS uav, d.rssi AS rssi, d.app_timestamp AS at, '
      'd.height_agl AS agl, d.altitude_msl AS alt, d.drone_speed AS spd, '
      "COALESCE(json_extract(e.data, '\$.sourceNodeId'), '') AS node "
      'FROM detections d LEFT JOIN detection_ext e ON e.detection_id = d.id '
      "WHERE d.engine = 'skySpy' AND d.app_timestamp >= ? AND d.app_timestamp <= ? "
      "${node == null ? '' : "AND COALESCE(json_extract(e.data, '\$.sourceNodeId'), '') = ? "}"
      'ORDER BY d.app_timestamp DESC LIMIT $metricRowCap',
      variables: [Variable.withInt(fromMs), Variable.withInt(toMs), if (node != null) Variable.withString(node)],
    ).get();
    return [
      for (final r in rows)
        DroneReport(
          ts: DateTime.fromMillisecondsSinceEpoch(r.read<int>('at')),
          id: (r.readNullable<String>('uav') ?? '').isNotEmpty ? r.read<String>('uav') : r.read<String>('mac'),
          mac: r.read<String>('mac'),
          height: r.readNullable<int>('agl'),
          alt: r.readNullable<int>('alt'),
          speed: r.readNullable<int>('spd'),
          rssi: r.read<int>('rssi'),
          node: r.read<String>('node'),
        ),
    ];
  }

  Future<int> metricCount(int fromMs, int toMs, {String? node}) async {
    await _ensureDetectionExtTable();
    final r = await customSelect(
      'SELECT COUNT(*) AS n FROM detections d LEFT JOIN detection_ext e ON e.detection_id = d.id '
      'WHERE d.app_timestamp >= ? AND d.app_timestamp < ? '
      "${node == null ? '' : "AND COALESCE(json_extract(e.data, '\$.sourceNodeId'), '') = ?"}",
      variables: [Variable.withInt(fromMs), Variable.withInt(toMs), if (node != null) Variable.withString(node)],
    ).getSingle();
    return r.read<int>('n');
  }

  Future<List<String>> metricNodes() async {
    await _ensureDetectionExtTable();
    final rows = await customSelect(
      "SELECT DISTINCT json_extract(data, '\$.sourceNodeId') AS node FROM detection_ext "
      "WHERE json_extract(data, '\$.sourceNodeId') IS NOT NULL",
    ).get();
    return [for (final r in rows) if ((r.readNullable<String>('node') ?? '').isNotEmpty) r.read<String>('node')]..sort();
  }

  Future<({int aps, int placed, int lastMs})> wardriveSsidSummary(String ssid) async {
    final r = await customSelect(
      'SELECT COUNT(DISTINCT mac_address) AS aps, '
      'COUNT(DISTINCT CASE WHEN latitude IS NOT NULL THEN mac_address END) AS placed, '
      'COALESCE(MAX(app_timestamp), 0) AS last '
      "FROM detections WHERE detection_method = 'wifi_ap' AND ssid = ?",
      variables: [Variable.withString(ssid)],
    ).getSingle();
    return (aps: r.read<int>('aps'), placed: r.read<int>('placed'), lastMs: r.read<int>('last'));
  }

  Future<List<(double, double)>> sessionRoute(String sessionId) async {
    final rows = await customSelect(
      'SELECT app_timestamp / 10000 AS b, AVG(latitude) AS la, AVG(longitude) AS lo FROM detections '
      'WHERE session_id = ? AND latitude IS NOT NULL AND longitude IS NOT NULL '
      'AND (approx_gps IS NULL OR approx_gps = 0) AND NOT (latitude = 0 AND longitude = 0) '
      'GROUP BY b ORDER BY b',
      variables: [Variable.withString(sessionId)],
    ).get();
    return [for (final r in rows) (r.read<double>('la'), r.read<double>('lo'))];
  }

  Future<Map<String, int>> classAlertCountsBetween(int fromMs, int toMs) async {
    final rows = await customSelect(
      'SELECT alert_class AS k, COUNT(DISTINCT mac_address) AS n FROM class_alerts '
      'WHERE alerted_at >= ? AND alerted_at <= ? GROUP BY alert_class',
      variables: [Variable.withInt(fromMs), Variable.withInt(toMs)],
    ).get();
    return {for (final r in rows) r.read<String>('k'): r.read<int>('n')};
  }

  Future<ArchiveOverview> archiveOverview() async {
    final t = await customSelect(
      "SELECT COUNT(*) AS n, "
      "COUNT(DISTINCT engine || '|' || mac_address) AS devices, "
      "SUM(CASE WHEN latitude IS NOT NULL AND COALESCE(approx_gps, 0) = 0 THEN 1 ELSE 0 END) AS gps, "
      "MIN(app_timestamp) AS first_ms, MAX(app_timestamp) AS last_ms, "
      "COUNT(DISTINCT session_id) AS sessions FROM detections",
    ).getSingle();
    final rows = await customSelect(
      "SELECT engine, COUNT(*) AS n, COUNT(DISTINCT mac_address) AS devices "
      "FROM detections GROUP BY engine ORDER BY n DESC",
    ).get();
    return ArchiveOverview(
      detections: t.read<int>('n'),
      devices: t.read<int>('devices'),
      withGps: t.readNullable<int>('gps') ?? 0,
      sessions: t.read<int>('sessions'),
      firstMs: t.readNullable<int>('first_ms'),
      lastMs: t.readNullable<int>('last_ms'),
      byEngine: [
        for (final r in rows)
          (engine: r.read<String>('engine'), detections: r.read<int>('n'), devices: r.read<int>('devices')),
      ],
    );
  }

  Future<List<ArchiveHit>> searchArchive(String query, {int limit = 200}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final hex = q.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
    final macClause = hex.length >= 4
        ? "REPLACE(REPLACE(UPPER(mac_address), ':', ''), '-', '') LIKE ? OR "
        : '';
    final like = '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await customSelect(
      "SELECT mac_address, engine, MIN(app_timestamp) AS first_ms, MAX(app_timestamp) AS last_ms, "
      "MAX(rssi) AS best_rssi, COUNT(*) AS n, MAX(ssid) AS ssid, MAX(device_name) AS name, "
      "MAX(COALESCE(filter_description, '')) AS descr "
      "FROM detections WHERE $macClause ssid LIKE ? ESCAPE '\\' OR device_name LIKE ? ESCAPE '\\' "
      "OR filter_description LIKE ? ESCAPE '\\' "
      "GROUP BY mac_address, engine ORDER BY last_ms DESC LIMIT ?",
      variables: [
        if (hex.length >= 4) Variable.withString('%$hex%'),
        Variable.withString(like),
        Variable.withString(like),
        Variable.withString(like),
        Variable.withInt(limit),
      ],
    ).get();
    return [
      for (final r in rows)
        ArchiveHit(
          mac: r.read<String>('mac_address'),
          engine: r.read<String>('engine'),
          firstMs: r.read<int>('first_ms'),
          lastMs: r.read<int>('last_ms'),
          bestRssi: r.read<int>('best_rssi'),
          sightings: r.read<int>('n'),
          ssid: r.readNullable<String>('ssid') ?? '',
          name: r.readNullable<String>('name') ?? '',
          description: r.readNullable<String>('descr') ?? '',
        ),
    ];
  }

  /// Aggregate collection stats across every completed session.
  Future<CollectionStats> wardriveCollectionStats() async {
    final totals = await customSelect(
      "SELECT "
      "(SELECT COUNT(DISTINCT mac_address) FROM detections) AS total_unique, "
      "(SELECT COUNT(DISTINCT mac_address) FROM detections WHERE detection_method='wifi_ap') AS wifi_unique, "
      "(SELECT COUNT(DISTINCT mac_address) FROM detections WHERE detection_method='ble_adv') AS ble_unique, "
      "(SELECT COUNT(*) FROM detections) AS total_dets, "
      "(SELECT COUNT(*) FROM sessions WHERE ended_at IS NOT NULL) AS session_count, "
      "(SELECT COUNT(DISTINCT ssid) FROM detections WHERE detection_method='wifi_ap' AND ssid != '') AS ssid_count",
    ).getSingle();

    final chanRows = await customSelect(
      "SELECT channel AS ch, COUNT(DISTINCT mac_address) AS c FROM detections "
      "WHERE detection_method='wifi_ap' AND channel BETWEEN 1 AND 177 "
      "GROUP BY channel ORDER BY channel",
    ).get();

    final authRows = await customSelect(
      "SELECT auth_mode AS a, COUNT(DISTINCT mac_address) AS c FROM detections "
      "WHERE detection_method='wifi_ap' GROUP BY auth_mode",
    ).get();

    final ouiRows = await customSelect(
      "SELECT UPPER(SUBSTR(mac_address,1,8)) AS oui, COUNT(DISTINCT mac_address) AS c "
      "FROM detections WHERE mac_address != '' GROUP BY oui ORDER BY c DESC LIMIT 300",
    ).get();

    final flockOuiRows = await customSelect(
      "SELECT UPPER(SUBSTR(mac_address,1,8)) AS oui, COUNT(DISTINCT mac_address) AS c "
      "FROM detections WHERE engine IN ('flockBle','flockWifi') AND mac_address != '' "
      "GROUP BY oui ORDER BY c DESC LIMIT 80",
    ).get();

    return CollectionStats(
      totalUnique: totals.read<int>('total_unique'),
      wifiUnique: totals.read<int>('wifi_unique'),
      bleUnique: totals.read<int>('ble_unique'),
      totalDetections: totals.read<int>('total_dets'),
      sessionCount: totals.read<int>('session_count'),
      ssidCount: totals.read<int>('ssid_count'),
      channelCounts: {
        for (final r in chanRows) r.read<int>('ch'): r.read<int>('c'),
      },
      authCounts: {
        for (final r in authRows) r.read<int>('a'): r.read<int>('c'),
      },
      ouiCounts: [
        for (final r in ouiRows) MapEntry(r.read<String>('oui'), r.read<int>('c')),
      ],
      flockOuiCounts: [
        for (final r in flockOuiRows)
          MapEntry(r.read<String>('oui'), r.read<int>('c')),
      ],
    );
  }

  Future<
      (
        List<(int, double, double)>,
        List<({String mac, String name, String ssid, String engine, String method, int channel, double lat, double lon, int lastMs})>
      )> stopsReportInput(int sinceMs) async {
    const where = 'app_timestamp >= ? AND latitude IS NOT NULL AND longitude IS NOT NULL '
        'AND (approx_gps IS NULL OR approx_gps = 0)';
    final track = await customSelect(
      'SELECT app_timestamp / 60000 AS m, AVG(latitude) AS la, AVG(longitude) AS lo '
      'FROM detections WHERE $where GROUP BY m ORDER BY m',
      variables: [Variable.withInt(sinceMs)],
    ).get();
    final cells = await customSelect(
      "SELECT mac_address, MAX(device_name) AS name, MAX(ssid) AS ssid, MAX(engine) AS engine, "
      "MAX(detection_method) AS method, MAX(channel) AS ch, AVG(latitude) AS la, AVG(longitude) AS lo, "
      "MAX(app_timestamp) AS last_ms FROM detections WHERE $where AND mac_address != '' "
      'GROUP BY mac_address, CAST(latitude / 0.0015 AS INTEGER), CAST(longitude / 0.0015 AS INTEGER)',
      variables: [Variable.withInt(sinceMs)],
    ).get();
    return (
      [for (final r in track) (r.read<int>('m') * 60000, r.read<double>('la'), r.read<double>('lo'))],
      [
        for (final r in cells)
          (
            mac: r.read<String>('mac_address'),
            name: r.readNullable<String>('name') ?? '',
            ssid: r.readNullable<String>('ssid') ?? '',
            engine: r.readNullable<String>('engine') ?? '',
            method: r.readNullable<String>('method') ?? '',
            channel: r.readNullable<int>('ch') ?? 0,
            lat: r.read<double>('la'),
            lon: r.read<double>('lo'),
            lastMs: r.read<int>('last_ms'),
          ),
      ],
    );
  }

  Future<List<({String mac, int auth, double? lat, double? lon})>> trustedSeed(String ssid) async {
    final rows = await customSelect(
      "SELECT mac_address, MAX(auth_mode) AS auth, AVG(latitude) AS la, AVG(longitude) AS lo FROM detections "
      "WHERE ssid = ? AND detection_method = 'wifi_ap' AND mac_address != '' "
      'GROUP BY mac_address, CAST(COALESCE(latitude, 0) / 0.003 AS INTEGER), CAST(COALESCE(longitude, 0) / 0.003 AS INTEGER) '
      'LIMIT 500',
      variables: [Variable.withString(ssid)],
    ).get();
    return [
      for (final r in rows)
        (
          mac: r.read<String>('mac_address'),
          auth: r.readNullable<int>('auth') ?? -1,
          lat: r.readNullable<double>('la'),
          lon: r.readNullable<double>('lo'),
        ),
    ];
  }

  /// Get all distinct MACs seen across all sessions for stalking detection.
  Future<List<int>> sightingTimesForMac(String mac) async {
    final ts = detections.appTimestamp;
    final rows = await (selectOnly(detections)
          ..addColumns([ts])
          ..where(detections.macAddress.equals(mac.toUpperCase()) |
              detections.macAddress.equals(mac.toLowerCase())))
        .get();
    return [for (final r in rows) r.read(ts)!];
  }

  Future<List<String>> macSeenInMultipleSessions(int minSessions) async {
    final mac = detections.macAddress;
    final sessionCount = detections.sessionId.count(distinct: true);
    final query = selectOnly(detections)
      ..addColumns([mac, sessionCount])
      ..groupBy([mac])
      ..where(sessionCount.isBiggerOrEqualValue(minSessions));
    final rows = await query.get();
    return rows.map((r) => r.read(mac)!).toList();
  }

  Future<List<Map<String, dynamic>>> getFlockDetectorDetections() async {
    final rows = await (select(detections)
          ..where((d) => d.engine.isIn([
                'flockBle', 'flockWifi', 'detector', 'skySpy', 'sdr',
              ]))
          ..orderBy([(d) => OrderingTerm.desc(d.appTimestamp)]))
        .get();
    final seen = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final uav = r.uavId ?? '';
      final isDrone = r.engine == 'skySpy';
      final key = (isDrone && uav.isNotEmpty)
          ? 'uav:$uav'
          : '${r.macAddress}|${r.engine}';
      final existing = seen[key];
      final method = r.detectionMethod;
      if (existing == null) {
        seen[key] = {
          ..._detectionRowMap(r),
          'memberMacs': <String>{r.macAddress},
          'transports': <String>{if (method.isNotEmpty) method},
        };
      } else {
        (existing['memberMacs'] as Set<String>).add(r.macAddress);
        if (method.isNotEmpty) (existing['transports'] as Set<String>).add(method);
        if (isDrone && existing['latitude'] == null && r.latitude != null) {
          existing['latitude'] = r.latitude;
          existing['longitude'] = r.longitude;
        }
      }
    }
    for (final e in seen.values) {
      e['memberMacs'] = (e['memberMacs'] as Set<String>).toList();
      e['transports'] = (e['transports'] as Set<String>).toList()..sort();
    }
    final out = seen.values.toList();
    await _attachExt(out);
    return out;
  }

  /// Full-history detection search (MAC / name / SSID / method / node).
  Future<List<Map<String, dynamic>>> searchDetectionMaps(
    String query, {
    int limit = 2000,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final like = '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await customSelect(
      'SELECT * FROM detections WHERE '
      'mac_address LIKE ?1 ESCAPE \'\\\' OR '
      'device_name LIKE ?1 ESCAPE \'\\\' OR '
      'ssid LIKE ?1 ESCAPE \'\\\' OR '
      'detection_method LIKE ?1 ESCAPE \'\\\' OR '
      'node_id LIKE ?1 ESCAPE \'\\\' '
      'ORDER BY app_timestamp DESC LIMIT ?2',
      variables: [Variable.withString(like), Variable.withInt(limit)],
      readsFrom: {detections},
    ).get();

    final maps = rows.map((r) => _detectionRowMap(detections.map(r.data))).toList();
    await _attachExt(maps);
    return maps;
  }

  Future<Map<String, dynamic>?> latestDetectionMapForMac(String mac, {String sessionId = ''}) async {
    if (mac.isEmpty) return null;
    final rows = await customSelect(
      'SELECT * FROM detections WHERE lower(mac_address) = lower(?1) '
      'ORDER BY (session_id = ?2) DESC, app_timestamp DESC, id DESC LIMIT 1',
      variables: [Variable.withString(mac), Variable.withString(sessionId)],
      readsFrom: {detections},
    ).get();
    if (rows.isEmpty) return null;
    final maps = [_detectionRowMap(detections.map(rows.single.data))];
    await _attachExt(maps);
    return maps.single;
  }

  Future<void> _attachExt(List<Map<String, dynamic>> maps) async {
    final ids = [for (final m in maps) m['id'] as int];
    final byId = <int, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final ext = await customSelect(
        'SELECT detection_id, data FROM detection_ext WHERE detection_id IN '
        '(${List.filled(chunk.length, '?').join(',')})',
        variables: [for (final id in chunk) Variable.withInt(id)],
      ).get();
      for (final e in ext) {
        final id = e.read<int>('detection_id');
        try {
          byId[id] = Map<String, dynamic>.from(jsonDecode(e.read<String>('data')) as Map);
        } on FormatException catch (err) {
          DebugLog.log('DB: detection_ext row $id unreadable, details skipped: $err');
        }
      }
    }
    for (final m in maps) {
      final x = byId[m['id'] as int];
      if (x != null) m['ext'] = x;
    }
  }

  /// Delete a single detection by its primary key.
  Future<void> deleteDetectionById(int id) =>
      (delete(detections)..where((d) => d.id.equals(id))).go();

  static const _classAlertsDdl = 'CREATE TABLE IF NOT EXISTS class_alerts ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'mac_address TEXT NOT NULL, '
      "device_name TEXT NOT NULL DEFAULT '', "
      'alert_class TEXT NOT NULL, '
      'title TEXT NOT NULL, '
      "reason TEXT NOT NULL DEFAULT '', "
      'is_ble INTEGER NOT NULL, '
      'rssi INTEGER NOT NULL, '
      'channel INTEGER NOT NULL, '
      'alerted_at INTEGER NOT NULL, '
      'latitude REAL, '
      'longitude REAL, '
      "session_id TEXT NOT NULL DEFAULT '')";

  Future<void> _ensureClassAlertSessionColumn() async {
    final cols = await customSelect('PRAGMA table_info(class_alerts)').get();
    if (cols.isEmpty) {
      await customStatement(_classAlertsDdl);
      return;
    }
    if (!cols.any((c) => c.read<String>('name') == 'session_id')) {
      await customStatement(
          "ALTER TABLE class_alerts ADD COLUMN session_id TEXT NOT NULL DEFAULT ''");
    }
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_class_alerts_session ON class_alerts (session_id)');
    await _linkOldAlertsToSessions();
  }

  Future<void> _linkOldAlertsToSessions() => customStatement(
        'UPDATE class_alerts SET session_id = COALESCE(('
        'SELECT s.id FROM sessions s '
        'WHERE class_alerts.alerted_at >= s.started_at '
        'AND s.ended_at IS NOT NULL AND class_alerts.alerted_at <= s.ended_at '
        'ORDER BY s.is_wardrive DESC, s.started_at DESC LIMIT 1), \'\') '
        "WHERE session_id = ''",
      );

  Future<void> insertClassAlert({
    required String macAddress,
    required String deviceName,
    required String alertClass,
    required String title,
    required String reason,
    required bool isBle,
    required int rssi,
    required int channel,
    required int alertedAt,
    double? latitude,
    double? longitude,
    String sessionId = '',
  }) =>
      customInsert(
        'INSERT INTO class_alerts (mac_address, device_name, alert_class, title, reason, '
        'is_ble, rssi, channel, alerted_at, latitude, longitude, session_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(macAddress),
          Variable.withString(deviceName),
          Variable.withString(alertClass),
          Variable.withString(title),
          Variable.withString(reason),
          Variable.withBool(isBle),
          Variable.withInt(rssi),
          Variable.withInt(channel),
          Variable.withInt(alertedAt),
          Variable<double>(latitude),
          Variable<double>(longitude),
          Variable.withString(sessionId),
        ],
      );

  Future<List<Map<String, dynamic>>> getClassAlertsForSession(String sessionId) async {
    if (sessionId.isEmpty) return const [];
    final rows = await customSelect(
      'SELECT * FROM class_alerts WHERE session_id = ? ORDER BY alerted_at ASC',
      variables: [Variable.withString(sessionId)],
    ).get();
    return [
      for (final r in rows)
        {
          'id': r.read<int>('id'),
          'sessionId': sessionId,
          'nodeId': '',
          'macAddress': r.read<String>('mac_address'),
          'deviceName': r.read<String>('title'),
          'engine': 'signature',
          'detectionMethod': r.read<String>('reason'),
          'alertClass': r.read<String>('alert_class'),
          'isBle': r.read<bool>('is_ble'),
          'rssi': r.read<int>('rssi'),
          'channel': r.read<int>('channel'),
          'deviceTimestampMs': 0,
          'appTimestamp': r.read<int>('alerted_at'),
          'ssid': r.read<String>('device_name'),
          'authMode': 0,
          'count': 1,
          'latitude': r.readNullable<double>('latitude'),
          'longitude': r.readNullable<double>('longitude'),
        },
    ];
  }

  Future<void> deleteClassAlerts(String mac, String alertClass) => customUpdate(
        'DELETE FROM class_alerts WHERE mac_address = ? AND alert_class = ?',
        variables: [Variable.withString(mac), Variable.withString(alertClass)],
        updateKind: UpdateKind.delete,
      );

  Future<int> clearClassAlerts() =>
      customUpdate('DELETE FROM class_alerts', updateKind: UpdateKind.delete);

  Future<List<Map<String, dynamic>>> getClassAlertMaps() async {
    final rows = await customSelect(
      'SELECT * FROM class_alerts ORDER BY alerted_at DESC',
    ).get();
    final seen = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final mac = r.read<String>('mac_address');
      final cls = r.read<String>('alert_class');
      final existing = seen['$mac|$cls'];
      if (existing != null) {
        existing['count'] = (existing['count'] as int) + 1;
        existing['firstAlertedAt'] = r.read<int>('alerted_at');
        continue;
      }
      seen['$mac|$cls'] = {
        'id': r.read<int>('id'),
        'sessionId': r.read<String>('session_id'),
        'nodeId': '',
        'macAddress': mac,
        'deviceName': r.read<String>('title'),
        'engine': 'signature',
        'detectionMethod': r.read<String>('reason'),
        'alertClass': cls,
        'isBle': r.read<bool>('is_ble'),
        'rssi': r.read<int>('rssi'),
        'channel': r.read<int>('channel'),
        'deviceTimestampMs': 0,
        'appTimestamp': r.read<int>('alerted_at'),
        'firstAlertedAt': r.read<int>('alerted_at'),
        'ssid': r.read<String>('device_name'),
        'authMode': 0,
        'count': 1,
        'latitude': r.readNullable<double>('latitude'),
        'longitude': r.readNullable<double>('longitude'),
      };
    }
    return seen.values.toList();
  }

  Future<List<Map<String, dynamic>>> getAlertHistoryMaps() async {
    final engineRows = await getFlockDetectorDetections();
    final byMac = <String, Map<String, dynamic>>{};
    for (final r in engineRows) {
      for (final m in r['memberMacs'] as List<String>) {
        byMac.putIfAbsent(m.toUpperCase(), () => r);
      }
    }
    final out = [...engineRows];
    for (final c in await getClassAlertMaps()) {
      final host = byMac[(c['macAddress'] as String).toUpperCase()];
      if (host == null) {
        out.add(c);
        continue;
      }
      ((host['mergedClasses'] ??= <(String, String)>[]) as List<(String, String)>)
          .add((c['macAddress'] as String, c['alertClass'] as String));
      host['classTitle'] ??= c['deviceName'];
    }
    return out;
  }

  Future<int> clearFlockDetectorDetections() => (delete(detections)
        ..where((d) => d.engine.isIn(['flockBle', 'flockWifi', 'detector', 'skySpy', 'sdr'])))
      .go();

  Future<void> deleteDetectionsByMacs(String sessionId, List<String> macs) {
    if (macs.isEmpty) return Future.value();
    return (delete(detections)
          ..where((d) => d.sessionId.equals(sessionId) & d.macAddress.isIn(macs)))
        .go();
  }

  // -- WiGLE upload operations --

  Future<void> insertWigleUpload(WigleUploadsCompanion upload) =>
      into(wigleUploads).insert(upload);

  Future<List<WigleUpload>> getWigleUploads() =>
      (select(wigleUploads)
            ..orderBy([(u) => OrderingTerm.desc(u.uploadedAt)]))
          .get();

  Future<WigleUpload?> getWigleUploadForSession(String sessionId) =>
      (select(wigleUploads)..where((u) => u.sessionId.equals(sessionId)))
          .getSingleOrNull();

  // -- Baseline operations --

  Future<void> insertBaseline(BaselinesCompanion baseline) =>
      into(baselines).insert(baseline);

  Future<List<Baseline>> getAllBaselines() => select(baselines).get();

  Future<List<BaselineDevice>> getBaselineDevices(String baselineId) =>
      (select(baselineDevices)
            ..where((d) => d.baselineId.equals(baselineId)))
          .get();

  // -- Geofence operations --

  Future<List<Geofence>> getActiveGeofences() =>
      (select(geofences)..where((g) => g.enabled.equals(true))).get();

  Future<void> upsertGeofence(GeofencesCompanion geofence) =>
      into(geofences).insertOnConflictUpdate(geofence);

  /// Get all enabled geofences marked for wardrive exclusion.
  Future<List<Geofence>> getWardriveExclusionGeofences() =>
      (select(geofences)
            ..where((g) => g.enabled.equals(true))
            ..where((g) => g.excludeFromWardrive.equals(true)))
          .get();

  Future<List<Geofence>> getAlertGeofences() =>
      (select(geofences)
            ..where((g) => g.enabled.equals(true))
            ..where((g) => g.excludeFromWardrive.equals(false)))
          .get();

  Future<File> createBackup() async {
    final dir = await getTemporaryDirectory();
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final dest = File(p.join(dir.path, 'oui_spy_backup_$stamp.db'));
    if (await dest.exists()) await dest.delete();
    await customStatement('VACUUM INTO ?', [dest.path]);
    return dest;
  }

  static Future<bool> validateBackup(String srcPath) async {
    final test = AppDatabase.forTesting(NativeDatabase(File(srcPath)));
    try {
      final integrity =
          await test.customSelect('PRAGMA integrity_check').get();
      final ok = integrity.isNotEmpty &&
          (integrity.first.data.values.first as String?)?.toLowerCase() ==
              'ok';
      if (!ok) return false;
      final tables = await test
          .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='detections'")
          .get();
      return tables.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      await test.close();
    }
  }

  Future<void> restoreFromFile(String srcPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'oui_spy.db');
    await close();
    await deleteFiles(dbPath);
    await File(srcPath).copy(dbPath);
  }

  Future<void> deleteAllData() async {
    final dir = await getApplicationDocumentsDirectory();
    await close();
    await deleteFiles(p.join(dir.path, 'oui_spy.db'));
  }

  static Future<void> deleteFiles(String dbPath) async {
    for (final ext in ['', '-wal', '-shm']) {
      final f = File('$dbPath$ext');
      if (await f.exists()) await f.delete();
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'oui_spy.db'));
    return NativeDatabase.createInBackground(file, sqlite3: guardedSqlite3);
  });
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
