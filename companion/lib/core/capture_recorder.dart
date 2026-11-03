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
  final _pending = <DetectionsCompanion>[];
  String? _sessionId;
  String _sessionName = '';
  int _startedAt = 0;
  int _rows = 0;
  bool _flushing = false;

  String? get sessionId => _sessionId;
  int get rows => _rows;
  int get pending => _pending.length;

  void _onDetection(Detection d) {
    if (_recordingElsewhere() || _suppressed(d)) return;
    final now = d.appTimestamp.millisecondsSinceEpoch;
    final key = '${d.macAddress}|${d.engine.name}';
    final last = _lastLogged[key];
    if (last != null && now - last < relogEvery.inMilliseconds) return;
    _lastLogged[key] = now;
    _macs.add(d.macAddress);
    _pending.add(detectionCompanion(d, _sessionId ?? _openSession(now)));
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
    if (_flushing || _pending.isEmpty || sid == null) return;
    _flushing = true;
    var batch = List<DetectionsCompanion>.of(_pending);
    _pending.clear();
    try {
      if (_rows > 0 && await _db.getSessionById(sid) == null) {
        final fresh = _openSession(DateTime.now().millisecondsSinceEpoch);
        _rows = 0;
        _macs.clear();
        batch = [for (final c in batch) c.copyWith(sessionId: drift.Value(fresh))];
        for (final c in batch) {
          _macs.add(c.macAddress.value);
        }
        sid = fresh;
      }
      await _db.into(_db.sessions).insertOnConflictUpdate(SessionsCompanion(
        id: drift.Value(sid),
        name: drift.Value(_sessionName),
        nodeId: const drift.Value('default'),
        startedAt: drift.Value(_startedAt),
        endedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
        detectionCount: drift.Value(_rows + batch.length),
        uniqueMacCount: drift.Value(_macs.length),
        isWardrive: const drift.Value(false),
      ));
      await _db.batchInsertDetections(batch);
      _rows += batch.length;
    } catch (e) {
      _pending.insertAll(0, batch);
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
