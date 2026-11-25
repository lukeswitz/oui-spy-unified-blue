// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String droneLogDay(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

class DroneLog {
  DroneLog({
    Future<Directory> Function()? dir,
    DateTime Function()? now,
    this.minGap = const Duration(seconds: 2),
    this.flushDelay = const Duration(seconds: 5),
    this.keepDays = 90,
  })  : _dir = dir ?? _defaultDir,
        _now = now ?? DateTime.now;

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'dronelog'));
  }

  final Future<Directory> Function() _dir;
  final DateTime Function() _now;
  final Duration minGap;
  final Duration flushDelay;
  final int keepDays;

  final Map<String, DateTime> _last = {};
  final Map<String, StringBuffer> _pending = {};
  Timer? _timer;
  bool _pruned = false;

  void add(DroneReport r) {
    final prev = _last[r.id];
    if (prev != null && r.ts.difference(prev).abs() < minGap) return;
    _last[r.id] = r.ts;
    _pending
        .putIfAbsent(droneLogDay(r.ts), () => StringBuffer())
        .writeln(jsonEncode(r.toJson()));
    _timer ??= Timer(flushDelay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<Directory> _ensureDir() async {
    final d = await _dir();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = Map<String, StringBuffer>.of(_pending);
    _pending.clear();
    try {
      final d = await _ensureDir();
      for (final e in batch.entries) {
        await File(p.join(d.path, '${e.key}.jsonl'))
            .writeAsString(e.value.toString(), mode: FileMode.append);
      }
      if (!_pruned) {
        _pruned = true;
        await prune();
      }
    } on FileSystemException catch (e) {
      DebugLog.log('DroneLog: flush failed: ${e.message}');
      for (final entry in batch.entries) {
        final buf = _pending.putIfAbsent(entry.key, () => StringBuffer());
        final restored = StringBuffer(entry.value.toString())..write(buf);
        _pending[entry.key] = restored;
      }
    }
  }

  Future<void> prune() async {
    final d = await _ensureDir();
    final cutoff = droneLogDay(_now().subtract(Duration(days: keepDays)));
    await for (final f in d.list()) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      if (!name.endsWith('.jsonl')) continue;
      if (name.substring(0, name.length - 6).compareTo(cutoff) < 0) {
        await f.delete();
      }
    }
  }

  Future<List<DroneReport>> query({DateTime? from, DateTime? to}) async {
    await flush();
    final d = await _dir();
    if (!await d.exists()) return const [];
    final lo = from == null ? null : droneLogDay(from);
    final hi = to == null ? null : droneLogDay(to);
    final out = <DroneReport>[];
    var bad = 0;
    final files = <File>[];
    await for (final f in d.list()) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      if (!name.endsWith('.jsonl')) continue;
      final day = name.substring(0, name.length - 6);
      if (lo != null && day.compareTo(lo) < 0) continue;
      if (hi != null && day.compareTo(hi) > 0) continue;
      files.add(f);
    }
    for (final f in files) {
      for (final line in const LineSplitter().convert(await f.readAsString())) {
        if (line.trim().isEmpty) continue;
        try {
          final r = DroneReport.fromJson(jsonDecode(line) as Map<String, dynamic>);
          if (from != null && r.ts.isBefore(from)) continue;
          if (to != null && r.ts.isAfter(to)) continue;
          out.add(r);
        } on FormatException {
          bad++;
        } on TypeError {
          bad++;
        }
      }
    }
    if (bad > 0) DebugLog.log('DroneLog: skipped $bad unreadable lines');
    out.sort((a, b) => a.ts.compareTo(b.ts));
    return out;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final droneLogProvider = Provider<DroneLog>((ref) {
  final log = DroneLog();
  ref.onDispose(log.dispose);
  return log;
});
