import 'dart:async';

import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';

class SessionDetectionStore {
  SessionDetectionStore(this._db, {this.flushEvery = const Duration(seconds: 2)});

  final AppDatabase _db;
  final Duration flushEvery;
  final _rowIds = <String, int>{};
  final _dirty = <String, ({String sessionId, Detection d})>{};
  final _noFix = <String>{};
  final _chains = <String, Future<void>>{};
  Timer? _timer;

  int get pending => _dirty.length;

  void reset() {
    _timer?.cancel();
    _timer = null;
    _rowIds.clear();
    _dirty.clear();
    _noFix.clear();
    _chains.clear();
  }

  void insert(String key, String sessionId, Detection d) {
    _dirty.remove(key);
    if (d.latitude == null || d.longitude == null) {
      _noFix.add(key);
    } else {
      _noFix.remove(key);
    }
    _enqueue(key, () async {
      _rowIds[key] = await _db.insertDetectionRow(
        detectionCompanion(d, sessionId),
        ext: detectionExt(d),
      );
    });
  }

  void update(String key, String sessionId, Detection d) {
    _dirty[key] = (sessionId: sessionId, d: d);
    _timer ??= Timer.periodic(flushEvery, (_) => _drain());
  }

  void _drain() {
    if (_dirty.isEmpty) return;
    final batch = Map.of(_dirty);
    _dirty.clear();
    batch.forEach((key, v) {
      final firstFix = _noFix.contains(key) && v.d.latitude != null && v.d.longitude != null;
      if (firstFix) _noFix.remove(key);
      _enqueue(key, () async {
        final id = _rowIds[key];
        if (id == null) return;
        await _db.updateDetectionRow(
          id,
          firstFix ? detectionFirstFixCompanion(v.d) : detectionUpdateCompanion(v.d),
          ext: detectionExt(v.d),
        );
      });
    });
  }

  void _enqueue(String key, Future<void> Function() op) {
    final prev = _chains[key] ?? Future<void>.value();
    _chains[key] = prev.then((_) => op()).catchError((Object e) {
      DebugLog.log('SESSION: detection write failed for $key: $e');
    });
  }

  Future<void> flush() async {
    _drain();
    await Future.wait(_chains.values.toList());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
