import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:uuid/uuid.dart';

class CaptureRecorder {
  CaptureRecorder(
    this._db,
    Stream<Detection> detections, {
    required bool Function() recordingElsewhere,
    required bool Function(Detection) suppressed,
  })  : _recordingElsewhere = recordingElsewhere,
        _suppressed = suppressed {
    _sub = detections.listen(_onDetection);
    _timer = Timer.periodic(flushEvery, (_) => flush());
  }

  static const relogEvery = Duration(seconds: 60);
  static const flushEvery = Duration(seconds: 2);

  final AppDatabase _db;
  final bool Function() _recordingElsewhere;
  final bool Function(Detection) _suppressed;
  late final StreamSubscription<Detection> _sub;
  late final Timer _timer;
  final _lastLogged = <String, int>{};
  final _macs = <String>{};
  final _pending = <({String key, DetectionsCompanion row, Map<String, Object?> ext})>[];
  final _latest = <String, Detection>{};
  final _rowIds = <String, int>{};
  final _dirty = <String>{};
  final _droneGate = DroneTrackGate();
  bool _needsRow = false;
  String? _sessionId;
  String _sessionName = '';
  int _startedAt = 0;
  int _rows = 0;
  bool _flushing = false;

  String? get sessionId => _sessionId;
  int get rows => _rows;
  int get pending => _pending.length;

  String sessionIdForAlert() {
    final id = _sessionId ?? _openSession(DateTime.now().millisecondsSinceEpoch);
    _needsRow = true;
    return id;
  }

  void _onDetection(Detection d) {
    if (_recordingElsewhere() || _suppressed(d)) return;
    final now = d.appTimestamp.millisecondsSinceEpoch;
    final key = '${d.macAddress}|${d.engine.name}';
    final last = _lastLogged[key];
    final held = _latest[key];
    if (last != null && now - last < relogEvery.inMilliseconds && !_droneGate.moved(key, d)) {
      if (held != null) {
        _latest[key] = mergeWardriveSighting(held, d);
        if (_rowIds.containsKey(key)) _dirty.add(key);
      }
      return;
    }
    _lastLogged[key] = now;
    _macs.add(d.macAddress);
    final merged = held == null ? d : mergeWardriveSighting(held, d);
    _latest[key] = merged;
    _droneGate.note(key, merged);
    _dirty.remove(key);
    _pending.add((
      key: key,
      row: detectionCompanion(merged, _sessionId ?? _openSession(now)),
      ext: detectionExt(merged),
    ));
  }

  String _openSession(int now) {
    final id = const Uuid().v4();
    _sessionId = id;
    _startedAt = now;
    _sessionName = 'Capture ${DateTime.fromMillisecondsSinceEpoch(now).toIso8601String().substring(0, 16)}';
    return id;
  }

  Future<void> flush() async {
    var sid = _sessionId;
    if (_flushing || sid == null) return;
    if (_pending.isEmpty && _dirty.isEmpty && !_needsRow) return;
    _flushing = true;
    var batch = List<({String key, DetectionsCompanion row, Map<String, Object?> ext})>.of(_pending);
    final dirtyKeys = Set<String>.of(_dirty);
    _pending.clear();
    _dirty.clear();
    try {
      if (_rows > 0 && await _db.getSessionById(sid) == null) {
        final fresh = _openSession(DateTime.now().millisecondsSinceEpoch);
        _rows = 0;
        _macs.clear();
        _rowIds.clear();
        dirtyKeys.clear();
        batch = [
          for (final c in batch)
            (key: c.key, row: c.row.copyWith(sessionId: drift.Value(fresh)), ext: c.ext),
        ];
        for (final c in batch) {
          _macs.add(c.row.macAddress.value);
        }
        sid = fresh;
      }
      final ids = <String, int>{};
      await _db.transaction(() async {
        await _db.into(_db.sessions).insertOnConflictUpdate(SessionsCompanion(
          id: drift.Value(sid!),
          name: drift.Value(_sessionName),
          nodeId: const drift.Value('default'),
          startedAt: drift.Value(_startedAt),
          endedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
          detectionCount: drift.Value(_rows + batch.length),
          uniqueMacCount: drift.Value(_macs.length),
          isWardrive: const drift.Value(false),
        ));
        for (final c in batch) {
          ids[c.key] = await _db.insertDetectionRow(c.row, ext: c.ext);
        }
        for (final key in dirtyKeys) {
          final id = ids[key] ?? _rowIds[key];
          final d = _latest[key];
          if (id != null && d != null) {
            await _db.updateDetectionRow(id, detectionUpdateCompanion(d), ext: detectionExt(d));
          }
        }
      });
      _rowIds.addAll(ids);
      _rows += batch.length;
      _needsRow = false;
    } catch (e) {
      _pending.insertAll(0, batch);
      _dirty.addAll(dirtyKeys);
      DebugLog.log('CAPTURE: flush of ${batch.length} rows failed, kept for retry: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> dispose() async {
    _timer.cancel();
    await _sub.cancel();
    await flush();
  }
}

final captureRecorderProvider = Provider<CaptureRecorder>((ref) {
  final ignore = ref.read(ignoreListProvider);
  final geofence = ref.read(geofenceFilterProvider);
  final recorder = CaptureRecorder(
    ref.read(databaseProvider),
    ref.read(bleManagerProvider).detections,
    recordingElsewhere: () => ref.read(wardriveProvider).state != WardriveState.idle,
    suppressed: (d) =>
        ignore.shouldSuppress(
          mac: d.macAddress,
          ssid: d.ssid.isNotEmpty ? d.ssid : d.deviceName,
          isBle: d.isBleDetection,
        ) ||
        geofence.isExcludedNullable(d.latitude, d.longitude),
  );
  ref.onDispose(recorder.dispose);
  return recorder;
});

final alertSessionIdProvider = Provider<String Function()>((ref) => () {
      final wd = ref.read(wardriveProvider);
      if (wd.isActive && wd.sessionId.isNotEmpty) return wd.sessionId;
      return ref.read(captureRecorderProvider).sessionIdForAlert();
    });
