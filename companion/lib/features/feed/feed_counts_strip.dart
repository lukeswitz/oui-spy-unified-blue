// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart' show databaseProvider;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/feed_counts.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/theme/app_theme.dart';

class FeedCountsStrip extends ConsumerStatefulWidget {
  const FeedCountsStrip({super.key, this.refresh = const Duration(seconds: 5)});

  final Duration refresh;

  @override
  ConsumerState<FeedCountsStrip> createState() => _FeedCountsStripState();
}

class _FeedCountsStripState extends ConsumerState<FeedCountsStrip> {
  FeedCounts _counts = const FeedCounts();
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.refresh, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final app = ref.read(appStateProvider);
      final known = app.knownNodes;
      final live = app.liveKnownNodes;
      final sightings = <LiveSighting>[
        for (final d in app.recentDetections)
          if (d.macAddress.isNotEmpty)
            LiveSighting(
              d.engine == Engine.skySpy && (d.odid?.uavId ?? '').isNotEmpty ? d.odid!.uavId! : MacUtil.normalize(d.macAddress),
              d.appTimestamp.millisecondsSinceEpoch,
              drone: d.engine == Engine.skySpy,
            ),
        if (ref.exists(deviceRegistryProvider))
          for (final d in ref.read(deviceRegistryProvider).devices)
            if (d.obs.mac.isNotEmpty) LiveSighting(MacUtil.normalize(d.obs.mac), d.obs.lastSeenMs),
      ];
      final db = ref.read(databaseProvider);
      final stored = await db.macCounts(startOfLocalDay(now).millisecondsSinceEpoch);
      final hourly = await db.hourlyMacCounts(nowMs);
      if (!mounted) return;
      setState(() => _counts = buildFeedCounts(
            nowMs: nowMs,
            nodesOnline: known.where(live.contains).length,
            nodesTotal: known.length,
            live: sightings,
            unread: ref.read(alertsFeedProvider).unread,
            macsKept: stored.kept,
            storedToday: stored.since,
            hourly: hourly,
          ));
    } catch (e) {
      DebugLog.log('FEED: counts failed: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final unread = ref.watch(alertsFeedProvider).unread;
    final silenced = ref.watch(notificationServiceProvider.select((n) => n.silenced));
    final c = _counts;
    Widget stat(String label, String value, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.textSecondary)),
            Text(value,
                style: TextStyle(
                  color: color ?? t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppTheme.mono,
                )),
          ],
        );
    return Container(
      key: const Key('feed-counts'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.rule), bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              stat('NODES ONLINE', '${c.nodesOnline}/${c.nodesTotal}'),
              stat('HEARD NOW', '${c.heardNow}'),
              stat('LIVE DRONES', '${c.liveDrones}', color: c.liveDrones > 0 ? AppTheme.skySpy : null),
              stat('HEARD TODAY', '${c.today}'),
              stat(silenced ? 'UNREAD ALERTS (SILENCED)' : 'UNREAD ALERTS', '$unread',
                  color: unread > 0 ? AppTheme.error : null),
              stat('MACS KEPT', '${c.macsKept}'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('24 HOURS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.textSecondary)),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: CustomPaint(
                    key: const Key('feed-counts-bars'),
                    painter: HourBarsPainter(c.hourly, AppTheme.accent, t.border),
                    size: Size.infinite,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${c.hourlyTotal}',
                  style: TextStyle(color: t.textPrimary, fontSize: 12, fontFamily: AppTheme.mono)),
            ],
          ),
        ],
      ),
    );
  }
}

class HourBarsPainter extends CustomPainter {
  HourBarsPainter(this.counts, this.color, this.track);

  final List<int> counts;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final n = counts.length;
    if (n == 0) return;
    final peak = counts.reduce((a, b) => a > b ? a : b);
    final slot = size.width / n;
    final bar = Paint()..color = color;
    final base = Paint()..color = track;
    for (var i = 0; i < n; i++) {
      final x = i * slot;
      canvas.drawRect(Rect.fromLTWH(x + 1, size.height - 1, slot - 2, 1), base);
      if (counts[i] <= 0 || peak <= 0) continue;
      final h = (counts[i] / peak * (size.height - 2)).clamp(1.0, size.height - 2);
      canvas.drawRect(Rect.fromLTWH(x + 1, size.height - 1 - h, slot - 2, h), bar);
    }
  }

  @override
  bool shouldRepaint(HourBarsPainter old) => old.counts != counts || old.color != color || old.track != track;
}
