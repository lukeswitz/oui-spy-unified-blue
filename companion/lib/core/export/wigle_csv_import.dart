import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/flock_oui.dart';
import 'package:oui_spy/core/watchlist_state.dart';
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
    File file, {
    List<WatchlistEntry> watchlist = const [],
  }) async {
    final raw = await file.readAsString();
    return importString(
      db,
      raw,
      fileName: p.basename(file.path),
      watchlist: watchlist,
    );
  }

  static Future<WigleImportResult> importString(
    AppDatabase db,
    String raw, {
    String? fileName,
    List<WatchlistEntry> watchlist = const [],
  }) async {
    final wlIndex = _WatchlistIndex.build(watchlist);
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
    final detectorMacs = <String>{};
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
      final wlHit = wlIndex.match(mac, ssid);
      final Engine engine;
      final String method;
      if (wlHit != null) {
        engine = Engine.detector;
        method = isBle
            ? (wlHit.byName ? 'name_match' : 'ble_watchlist')
            : 'wifi_watchlist';
      } else if (isFlock) {
        engine = isBle ? Engine.flockBle : Engine.flockWifi;
        method = isBle ? 'ble_adv' : 'wifi_ap';
      } else {
        engine = Engine.wardrive;
        method = isBle ? 'ble_adv' : 'wifi_ap';
      }
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
        filterDescription: wlHit != null && wlHit.description.isNotEmpty
            ? drift.Value(wlHit.description)
            : const drift.Value.absent(),
        isFullMac: wlHit != null
            ? drift.Value(wlHit.isFullMac)
            : const drift.Value.absent(),
      ));
      uniqueMacs.add(mac);
      if (isFlock) flockMacs.add(mac);
      if (wlHit != null) detectorMacs.add(mac);
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
      detectorMacs: detectorMacs.length,
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

class WigleRescanResult {
  const WigleRescanResult({
    required this.sessionsScanned,
    required this.rowsScanned,
    required this.rowsUpdated,
    required this.newDetectorMacs,
    required this.newFlockMacs,
  });
  final int sessionsScanned;
  final int rowsScanned;
  final int rowsUpdated;
  final int newDetectorMacs;
  final int newFlockMacs;
}

class WigleCsvRescan {
  const WigleCsvRescan._();

  /// Reclassify every detection in every wardrive session against the current
  /// watchlist + Flock OUI list. Promotes rows to Engine.detector or
  /// Engine.flockBle/flockWifi when matched; demotes back to Engine.wardrive
  /// when not (only for rows previously in detector/flock that no longer match,
  /// preserving live-captured rows by leaving non-import sources untouched only
  /// when row method indicates it).
  static Future<WigleRescanResult> rescanAll(
    AppDatabase db, {
    List<WatchlistEntry> watchlist = const [],
  }) async {
    final wlIndex = _WatchlistIndex.build(watchlist);
    final sessions = await db.getWardriveSessions();
    int rowsScanned = 0;
    int rowsUpdated = 0;
    final newDetector = <String>{};
    final newFlock = <String>{};

    for (final s in sessions) {
      final rows = await db.getDetectionsForSession(s.id);
      for (final r in rows) {
        rowsScanned++;
        final mac = r.macAddress;
        final ssid = r.ssid;
        final name = r.deviceName.isNotEmpty ? r.deviceName : ssid;
        final method = r.detectionMethod;
        final isBleRow = method == 'ble_adv' ||
            method == 'ble_watchlist' ||
            method == 'name_match' ||
            method == 'oui_match' ||
            method == 'ble_proximity' ||
            method == 'mfg_id' ||
            method == 'raven_uuid';

        final wlHit = wlIndex.match(mac, name);
        final isFlock = FlockOui.match(mac);

        String targetEngine;
        String targetMethod;
        String? targetDesc;
        bool? targetIsFullMac;

        if (wlHit != null) {
          targetEngine = Engine.detector.name;
          targetMethod = isBleRow
              ? (wlHit.byName ? 'name_match' : 'ble_watchlist')
              : 'wifi_watchlist';
          targetDesc = wlHit.description.isNotEmpty ? wlHit.description : null;
          targetIsFullMac = wlHit.isFullMac;
        } else if (isFlock) {
          targetEngine =
              isBleRow ? Engine.flockBle.name : Engine.flockWifi.name;
          targetMethod = isBleRow ? 'ble_adv' : 'wifi_ap';
          targetDesc = null;
          targetIsFullMac = null;
        } else {
          targetEngine = Engine.wardrive.name;
          targetMethod = isBleRow ? 'ble_adv' : 'wifi_ap';
          targetDesc = null;
          targetIsFullMac = null;
        }

        final changed = r.engine != targetEngine ||
            r.detectionMethod != targetMethod ||
            r.filterDescription != targetDesc ||
            r.isFullMac != targetIsFullMac;
        if (!changed) continue;

        await (db.update(db.detections)..where((d) => d.id.equals(r.id))).write(
          DetectionsCompanion(
            engine: drift.Value(targetEngine),
            detectionMethod: drift.Value(targetMethod),
            filterDescription: drift.Value(targetDesc),
            isFullMac: drift.Value(targetIsFullMac),
          ),
        );
        rowsUpdated++;
        if (targetEngine == Engine.detector.name) newDetector.add(mac);
        if (targetEngine == Engine.flockBle.name ||
            targetEngine == Engine.flockWifi.name) {
          newFlock.add(mac);
        }
      }
    }

    return WigleRescanResult(
      sessionsScanned: sessions.length,
      rowsScanned: rowsScanned,
      rowsUpdated: rowsUpdated,
      newDetectorMacs: newDetector.length,
      newFlockMacs: newFlock.length,
    );
  }
}

class WigleImportResult {
  const WigleImportResult({
    required this.sessionId,
    required this.detectionCount,
    required this.uniqueMacs,
    required this.flockMacs,
    required this.detectorMacs,
    required this.skipped,
  });
  final String sessionId;
  final int detectionCount;
  final int uniqueMacs;
  final int flockMacs;
  final int detectorMacs;
  final int skipped;
}

class _WatchlistIndex {
  _WatchlistIndex._(
    this._fullMacs,
    this._ouis,
    this._descByFull,
    this._descByOui,
    this._namePatterns,
  );

  final Set<String> _fullMacs;
  final Set<String> _ouis;
  final Map<String, String> _descByFull;
  final Map<String, String> _descByOui;
  final List<_NamePattern> _namePatterns;

  static _WatchlistIndex build(List<WatchlistEntry> entries) {
    final fulls = <String>{};
    final ouis = <String>{};
    final descFull = <String, String>{};
    final descOui = <String, String>{};
    final names = <_NamePattern>[];
    for (final e in entries) {
      if (e.isName) {
        final pat = e.identifier.trim();
        if (pat.isEmpty) continue;
        names.add(_NamePattern.compile(pat, e.description));
        continue;
      }
      final norm = _normalizeHex(e.identifier);
      if (norm.isEmpty) continue;
      if (e.isFullMac) {
        if (norm.length != 12) continue;
        fulls.add(norm);
        if (e.description.isNotEmpty) descFull[norm] = e.description;
      } else {
        if (norm.length < 6) continue;
        final oui = norm.substring(0, 6);
        ouis.add(oui);
        if (e.description.isNotEmpty) descOui[oui] = e.description;
      }
    }
    return _WatchlistIndex._(fulls, ouis, descFull, descOui, names);
  }

  _WatchlistHit? match(String mac, String name) {
    if (_fullMacs.isEmpty && _ouis.isEmpty && _namePatterns.isEmpty) {
      return null;
    }
    final norm = _normalizeHex(mac);
    if (norm.length >= 12 && _fullMacs.contains(norm)) {
      return _WatchlistHit(
        isFullMac: true,
        byName: false,
        description: _descByFull[norm] ?? '',
      );
    }
    if (norm.length >= 6) {
      final oui = norm.substring(0, 6);
      if (_ouis.contains(oui)) {
        return _WatchlistHit(
          isFullMac: false,
          byName: false,
          description: _descByOui[oui] ?? '',
        );
      }
    }
    if (name.isNotEmpty) {
      for (final p in _namePatterns) {
        if (p.matches(name)) {
          return _WatchlistHit(
            isFullMac: false,
            byName: true,
            description: p.description.isNotEmpty ? p.description : p.raw,
          );
        }
      }
    }
    return null;
  }

  static String _normalizeHex(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isUpper = c >= 0x41 && c <= 0x46;
      final isLower = c >= 0x61 && c <= 0x66;
      if (isDigit) {
        buf.writeCharCode(c);
      } else if (isUpper) {
        buf.writeCharCode(c + 0x20);
      } else if (isLower) {
        buf.writeCharCode(c);
      }
    }
    return buf.toString();
  }
}

class _NamePattern {
  _NamePattern._(this.raw, this.description, this._regex);

  final String raw;
  final String description;
  final RegExp _regex;

  static _NamePattern compile(String pattern, String description) {
    final buf = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        buf.write('.*');
      } else if (c == '?') {
        buf.write('.');
      } else {
        buf.write(RegExp.escape(c));
      }
    }
    buf.write(r'$');
    return _NamePattern._(
      pattern,
      description,
      RegExp(buf.toString(), caseSensitive: false),
    );
  }

  bool matches(String name) => _regex.hasMatch(name);
}

class _WatchlistHit {
  const _WatchlistHit({
    required this.isFullMac,
    required this.byName,
    required this.description,
  });
  final bool isFullMac;
  final bool byName;
  final String description;
}
