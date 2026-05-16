import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/flock_oui.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Parses a WiGLE-format CSV and imports it as a wardrive session.
class WigleCsvImport {
  const WigleCsvImport._();

  static final _dateFormats = <DateFormat>[
    DateFormat('yyyy-MM-dd HH:mm:ss'),
    DateFormat('yyyy-MM-ddTHH:mm:ss'),
  ];

  static Future<WigleImportResult> importFile(
    AppDatabase db,
    File file,
  ) async {
    final raw = await file.readAsString();
    return importString(db, raw, fileName: p.basename(file.path));
  }

  static Future<WigleImportResult> importString(
    AppDatabase db,
    String raw, {
    String? fileName,
  }) async {
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty) {
      throw const FormatException('Empty CSV');
    }

    // Locate header row (contains "MAC" and "CurrentLatitude").
    int headerIdx = -1;
    for (var i = 0; i < lines.length && i < 5; i++) {
      final l = lines[i].toLowerCase();
      if (l.contains('mac') && l.contains('currentlatitude')) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx < 0) {
      throw const FormatException(
        'Not a WiGLE CSV (missing column header row)',
      );
    }

    final headers = _splitCsv(lines[headerIdx])
        .map((h) => h.trim().toLowerCase())
        .toList();
    int idx(String name) => headers.indexOf(name.toLowerCase());

    final iMac = idx('MAC');
    final iSsid = idx('SSID');
    final iAuth = idx('AuthMode');
    final iFirst = idx('FirstSeen');
    final iChan = idx('Channel');
    final iRssi = idx('RSSI');
    final iLat = idx('CurrentLatitude');
    final iLon = idx('CurrentLongitude');
    final iAlt = idx('AltitudeMeters');
    final iAcc = idx('AccuracyMeters');
    final iType = idx('Type');

    if (iMac < 0 || iLat < 0 || iLon < 0 || iFirst < 0) {
      throw const FormatException('Missing required columns');
    }

    final sessionId = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final batch = <DetectionsCompanion>[];
    final uniqueMacs = <String>{};
    final flockMacs = <String>{};
    int? minTs;
    int? maxTs;
    int skipped = 0;

    for (var i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final f = _splitCsv(line);
      if (f.length <= iLon) {
        skipped++;
        continue;
      }
      final mac = f[iMac].trim();
      if (mac.isEmpty || mac.toLowerCase() == 'mac') {
        skipped++;
        continue;
      }
      final lat = double.tryParse(f[iLat]);
      final lon = double.tryParse(f[iLon]);
      if (lat == null || lon == null || (lat == 0 && lon == 0)) {
        skipped++;
        continue;
      }
      final ssid = iSsid >= 0 && iSsid < f.length ? f[iSsid] : '';
      final auth = iAuth >= 0 && iAuth < f.length ? f[iAuth] : '';
      final firstSeen = iFirst < f.length ? f[iFirst].trim() : '';
      final chan = iChan >= 0 && iChan < f.length
          ? int.tryParse(f[iChan]) ?? 0
          : 0;
      final rssi = iRssi >= 0 && iRssi < f.length
          ? int.tryParse(f[iRssi]) ?? 0
          : 0;
      final alt = iAlt >= 0 && iAlt < f.length ? double.tryParse(f[iAlt]) : null;
      final acc = iAcc >= 0 && iAcc < f.length ? double.tryParse(f[iAcc]) : null;
      final type = iType >= 0 && iType < f.length
          ? f[iType].trim().toUpperCase()
          : 'WIFI';

      final ts = _parseTs(firstSeen) ?? nowMs;
      minTs = minTs == null || ts < minTs ? ts : minTs;
      maxTs = maxTs == null || ts > maxTs ? ts : maxTs;

      final isBle = type == 'BLE' || auth.toUpperCase().contains('LE');
      final isFlock = FlockOui.match(mac);
      final Engine engine;
      if (isFlock) {
        engine = isBle ? Engine.flockBle : Engine.flockWifi;
      } else {
        engine = Engine.wardrive;
      }
      final method = isBle ? 'ble_adv' : 'wifi_ap';
      final authMode = _parseAuthMode(auth);

      batch.add(DetectionsCompanion(
        sessionId: drift.Value(sessionId),
        nodeId: const drift.Value('default'),
        macAddress: drift.Value(mac),
        deviceName: drift.Value(isBle ? ssid : ''),
        engine: drift.Value(engine.name),
        detectionMethod: drift.Value(method),
        rssi: drift.Value(rssi),
        channel: drift.Value(chan),
        deviceTimestampMs: drift.Value(ts),
        appTimestamp: drift.Value(ts),
        latitude: drift.Value(lat),
        longitude: drift.Value(lon),
        altitude: drift.Value(alt),
        accuracy: drift.Value(acc),
        ssid: drift.Value(isBle ? '' : ssid),
        authMode: drift.Value(authMode),
      ));
      uniqueMacs.add(mac);
      if (isFlock) flockMacs.add(mac);
    }

    if (batch.isEmpty) {
      throw const FormatException('No valid rows in CSV');
    }

    final startedAt = minTs ?? nowMs;
    final endedAt = maxTs ?? startedAt;
    final label = fileName != null && fileName.isNotEmpty
        ? 'Imported ${p.basenameWithoutExtension(fileName)}'
        : 'Imported ${DateTime.fromMillisecondsSinceEpoch(startedAt).toIso8601String().substring(0, 16)}';

    // Defensive: ensure 'default' node exists (FK safety even if pragma off).
    await db.upsertNode(NodesCompanion(
      id: const drift.Value('default'),
      name: const drift.Value('default'),
      macAddress: const drift.Value(''),
      createdAt: drift.Value(nowMs),
    ));

    await db.insertSession(SessionsCompanion(
      id: drift.Value(sessionId),
      name: drift.Value(label),
      nodeId: const drift.Value('default'),
      startedAt: drift.Value(startedAt),
      endedAt: drift.Value(endedAt),
      isWardrive: const drift.Value(true),
      detectionCount: drift.Value(batch.length),
      uniqueMacCount: drift.Value(uniqueMacs.length),
      distanceKm: const drift.Value(0.0),
    ));
    await db.batchInsertDetections(batch);

    return WigleImportResult(
      sessionId: sessionId,
      detectionCount: batch.length,
      uniqueMacs: uniqueMacs.length,
      flockMacs: flockMacs.length,
      skipped: skipped,
    );
  }

  static int? _parseTs(String s) {
    if (s.isEmpty) return null;
    final asInt = int.tryParse(s);
    if (asInt != null) {
      // Epoch ms vs seconds heuristic.
      return asInt > 1000000000000 ? asInt : asInt * 1000;
    }
    for (final fmt in _dateFormats) {
      // DateFormat.parseUtc throws FormatException on mismatch — try next format.
      try {
        return fmt.parseUtc(s).millisecondsSinceEpoch;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// Map WiGLE AuthMode string back to firmware authMode byte.
  /// 0=OPEN 1=WEP 2=WPA 3=WPA2 4=WPA_WPA2 5=WPA2_ENT 6=WPA3
  static int _parseAuthMode(String s) {
    final u = s.toUpperCase();
    if (u.contains('WPA3')) return 6;
    if (u.contains('WPA2_EAP') || u.contains('EAP')) return 5;
    if (u.contains('WPA_WPA2') || (u.contains('WPA') && u.contains('WPA2'))) {
      return 4;
    }
    if (u.contains('WPA2')) return 3;
    if (u.contains('WPA')) return 2;
    if (u.contains('WEP')) return 1;
    return 0;
  }

  /// Minimal CSV splitter — handles double-quoted fields with "" escapes.
  static List<String> _splitCsv(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else {
        if (c == ',') {
          out.add(buf.toString());
          buf.clear();
        } else if (c == '"') {
          inQuotes = true;
        } else {
          buf.write(c);
        }
      }
    }
    out.add(buf.toString());
    return out;
  }
}

class WigleImportResult {
  const WigleImportResult({
    required this.sessionId,
    required this.detectionCount,
    required this.uniqueMacs,
    required this.flockMacs,
    required this.skipped,
  });
  final String sessionId;
  final int detectionCount;
  final int uniqueMacs;
  final int flockMacs;
  final int skipped;
}
