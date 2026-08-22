import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/tables.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Aggregate stats over all collected detections (for the Wardrive config tab).
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_detections_session ON detections (session_id)');
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

  Stream<List<Session>> watchWardriveSessions() =>
      (select(sessions)
            ..where((s) => s.isWardrive.equals(true))
            ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
          .watch();

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

  /// Returns detection rows as maps for cross-module consumption
  /// (avoids drift Detection / model Detection name collision).
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

  /// Get all distinct MACs seen across all sessions for stalking detection.
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
                'flockBle', 'flockWifi', 'detector', 'skySpy',
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

  Future<int> clearFlockDetectorDetections() => (delete(detections)
        ..where((d) => d.engine.isIn(['flockBle', 'flockWifi', 'detector', 'skySpy'])))
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
    return NativeDatabase.createInBackground(file);
  });
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
