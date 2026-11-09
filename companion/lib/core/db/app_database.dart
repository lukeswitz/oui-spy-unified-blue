import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/sqlite_guard.dart';
import 'package:oui_spy/core/db/tables.dart';
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
  int get schemaVersion => 9;

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
      await (delete(sessions)..where((s) => s.id.equals(id))).go();
    });
  }

  Future<void> deleteSessions(List<String> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, (i + 500).clamp(0, ids.length));
        await (delete(detections)..where((d) => d.sessionId.isIn(chunk))).go();
        await (delete(sessions)..where((s) => s.id.isIn(chunk))).go();
      }
    });
  }

  // -- Detection operations --

  Future<void> insertDetection(DetectionsCompanion detection) =>
      into(detections).insert(detection);

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
      };

  Future<List<Map<String, dynamic>>> getDetectionMapsForSession(
      String sessionId) async {
    final rows = await (select(detections)
          ..where((d) => d.sessionId.equals(sessionId))
          ..orderBy([(d) => OrderingTerm.asc(d.appTimestamp)]))
        .get();
    return rows.map(_detectionRowMap).toList();
  }

  Future<List<Map<String, dynamic>>> getAllDetectionMaps() async {
    final rows = await (select(detections)
          ..orderBy([(d) => OrderingTerm.desc(d.appTimestamp)]))
        .get();
    return rows.map(_detectionRowMap).toList();
  }

  Future<int> uniqueMacCount(String sessionId) async {
    final query = selectOnly(detections)
      ..where(detections.sessionId.equals(sessionId))
      ..addColumns([detections.macAddress.count(distinct: true)]);
    final result = await query.getSingle();
    return result.read(detections.macAddress.count(distinct: true)) ?? 0;
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
    return seen.values.toList();
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

    return rows.map((r) {
      final d = detections.map(r.data);
      return {
        'id': d.id,
        'sessionId': d.sessionId,
        'nodeId': d.nodeId,
        'macAddress': d.macAddress,
        'deviceName': d.deviceName,
        'engine': d.engine,
        'detectionMethod': d.detectionMethod,
        'rssi': d.rssi,
        'channel': d.channel,
        'deviceTimestampMs': d.deviceTimestampMs,
        'appTimestamp': d.appTimestamp,
        'ssid': d.ssid,
        'authMode': d.authMode,
        'count': d.count,
        'latitude': d.latitude,
        'longitude': d.longitude,
        'altitude': d.altitude,
        'speed': d.speed,
        'heading': d.heading,
        'accuracy': d.accuracy,
        'satelliteCount': d.satelliteCount,
        'uavId': d.uavId,
        'operatorId': d.operatorId,
        'droneLat': d.droneLat,
        'droneLon': d.droneLon,
        'altitudeMsl': d.altitudeMsl,
        'heightAgl': d.heightAgl,
        'droneSpeed': d.droneSpeed,
        'droneHeading': d.droneHeading,
        'pilotLat': d.pilotLat,
        'pilotLon': d.pilotLon,
        'approxGps': d.approxGps,
        'isRaven': d.isRaven,
        'ravenFirmware': d.ravenFirmware,
        'flockSignals': d.flockSignals,
      };
    }).toList();
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
      'longitude REAL)';

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
  }) =>
      customInsert(
        'INSERT INTO class_alerts (mac_address, device_name, alert_class, title, reason, '
        'is_ble, rssi, channel, alerted_at, latitude, longitude) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
        ],
      );

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
        continue;
      }
      seen['$mac|$cls'] = {
        'id': r.read<int>('id'),
        'sessionId': '',
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
    for (final ext in ['', '-wal', '-shm']) {
      final f = File('$dbPath$ext');
      if (await f.exists()) await f.delete();
    }
    await File(srcPath).copy(dbPath);
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
