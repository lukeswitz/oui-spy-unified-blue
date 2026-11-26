// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/assistant/assistant_grants.dart';
import 'package:oui_spy/core/assistant/assistant_intel.dart';
import 'package:oui_spy/core/assistant/assistant_reports.dart';
import 'package:oui_spy/core/assistant/assistant_settings.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _sleep(Duration d) => Future<void>.delayed(d);

class AssistantAutoIntel {
  AssistantAutoIntel({
    required this.intel,
    required this.enabled,
    required this.ready,
    required this.access,
    DateTime Function()? clock,
    Future<void> Function(Duration)? wait,
  })  : _clock = clock ?? DateTime.now,
        _wait = wait ?? _sleep {
    _mark = _clock().millisecondsSinceEpoch;
    _loaded = _load();
  }

  final AssistantIntel intel;
  final bool Function() enabled;
  final bool Function() ready;
  final AssistantAccess Function() access;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _wait;

  static const gap = Duration(seconds: 20);
  static const perDay = 40;
  static const dayMs = 86400000;
  static const prefKey = 'assistant_auto_intel_runs';

  final _queue = ListQueue<String>();
  final List<int> _runs = [];
  late final Future<void> _loaded;
  late int _mark;
  Future<void>? _draining;

  int get queued => _queue.length;
  int get runsToday {
    final now = _clock().millisecondsSinceEpoch;
    return _runs.where((t) => now - t <= dayMs).length;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _runs
      ..clear()
      ..addAll([for (final s in p.getStringList(prefKey) ?? const <String>[]) if (int.tryParse(s) != null) int.parse(s)]);
  }

  Future<void> _saveRuns() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(prefKey, [for (final t in _runs) '$t']);
  }

  bool get _allowed => enabled() && ready() && access().has(AssistantGrant.devices);

  void onAlerts(List<Map<String, dynamic>> rows) {
    final fresh = [for (final r in rows) if (r['appTimestamp'] is int && (r['appTimestamp'] as int) > _mark) r]
      ..sort((a, b) => (a['appTimestamp'] as int).compareTo(b['appTimestamp'] as int));
    for (final r in fresh) {
      _mark = r['appTimestamp'] as int;
      offer('${r['macAddress'] ?? r['mac'] ?? ''}');
    }
  }

  void offer(String mac) {
    final key = mac.toUpperCase();
    if (key.isEmpty || !_allowed) return;
    if (intel.notes.containsKey(key) || intel.working.contains(key) || _queue.contains(key)) return;
    _queue.add(key);
    unawaited(drain());
  }

  Future<void> drain() => _draining ??= _drain().whenComplete(() {
        _draining = null;
        if (_queue.isNotEmpty) unawaited(drain());
      });

  Future<void> _drain() async {
    await _loaded;
    await intel.loaded;
    while (_queue.isNotEmpty) {
      if (!_allowed) {
        _queue.clear();
        break;
      }
      final now = _clock().millisecondsSinceEpoch;
      _runs.removeWhere((t) => now - t > dayMs);
      if (_runs.length >= perDay) {
        _queue.clear();
        break;
      }
      if (_runs.isNotEmpty) {
        final left = gap.inMilliseconds - (now - _runs.last);
        if (left > 0) {
          await _wait(Duration(milliseconds: left));
          continue;
        }
      }
      final key = _queue.removeFirst();
      if (intel.notes.containsKey(key) || intel.working.contains(key) || !intel.knows(key)) continue;
      _runs.add(now);
      await _saveRuns();
      await intel.lookInto(key);
    }
  }
}

DateTime? nextReportAt(AssistantSettings s, DateTime now) {
  if (s.reportEvery == ReportEvery.off) return null;
  final base = s.reportLastMs > 0 ? DateTime.fromMillisecondsSinceEpoch(s.reportLastMs) : now;
  if (s.reportEvery == ReportEvery.every) return base.add(Duration(hours: s.reportHours));
  final h = s.reportDailyMinutes ~/ 60;
  final m = s.reportDailyMinutes % 60;
  final today = DateTime(base.year, base.month, base.day, h, m);
  return today.isAfter(base) ? today : DateTime(base.year, base.month, base.day + 1, h, m);
}

int reportWindowHours(AssistantSettings s, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final since = (s.reportLastMs > 0 ? s.reportLastMs : nowMs - 24 * 3600000).clamp(nowMs - 168 * 3600000, nowMs);
  return ((nowMs - since) / 3600000).ceil().clamp(1, 168);
}

class AssistantSchedule {
  AssistantSchedule({
    required this.reports,
    required this.access,
    required this.settings,
    required this.markRan,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AssistantReports reports;
  final AssistantAccess Function() access;
  final AssistantSettings Function() settings;
  final Future<void> Function(int atMs) markRan;
  final DateTime Function() _clock;

  static const tick = Duration(seconds: 60);
  Timer? _timer;
  bool _running = false;

  void start() {
    _timer ??= Timer.periodic(tick, (_) => unawaited(check()));
    unawaited(check());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  bool get _hasData {
    final a = access();
    return a.on && [AssistantGrant.devices, AssistantGrant.drones, AssistantGrant.wardrive, AssistantGrant.mesh].any(a.granted.contains);
  }

  Future<bool> check() async {
    if (_running || reports.writing) return false;
    final s = settings();
    final now = _clock();
    final at = nextReportAt(s, now);
    if (at == null || !now.isAfter(at) || !s.ready || !_hasData) return false;
    _running = true;
    try {
      await reports.loaded;
      await reports.writeNow(reportWindowHours(s, now));
      await markRan(now.millisecondsSinceEpoch);
      return true;
    } finally {
      _running = false;
    }
  }
}

class AssistantAuto {
  const AssistantAuto(this.intel, this.schedule);
  final AssistantAutoIntel intel;
  final AssistantSchedule schedule;
}

final assistantAutoProvider = Provider<AssistantAuto>((ref) {
  final intel = AssistantAutoIntel(
    intel: ref.read(assistantIntelProvider),
    enabled: () => ref.read(assistantSettingsProvider).autoIntel,
    ready: () => ref.read(assistantSettingsProvider).ready,
    access: () => ref.read(assistantAccessProvider),
  );
  final schedule = AssistantSchedule(
    reports: ref.read(assistantReportsProvider),
    access: () => ref.read(assistantAccessProvider),
    settings: () => ref.read(assistantSettingsProvider),
    markRan: ref.read(assistantSettingsProvider.notifier).markReportRan,
  );
  ref.listen(alertsFeedProvider, (_, feed) => intel.onAlerts(feed.rows));
  ref.listen(assistantSettingsProvider, (_, _) => unawaited(schedule.check()));
  ref.listen(assistantAccessProvider, (_, _) => unawaited(schedule.check()));
  schedule.start();
  ref.onDispose(schedule.dispose);
  return AssistantAuto(intel, schedule);
});
