// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_log.dart';
import 'package:oui_spy/core/drone_tags.dart';
import 'package:oui_spy/features/drones/drone_data.dart';
import 'package:oui_spy/features/drones/drone_page.dart';
import 'package:oui_spy/features/fpv/fpv_screen.dart' show fpvStateLabel;
import 'package:oui_spy/features/fpv/fpv_state.dart' show FpvState, fpvChannelName, fpvNoLevel, fpvRssiToLevel;
import 'package:oui_spy/features/wardrive/drone_markers.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_stats_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DroneWindow {
  h1('1 h', Duration(hours: 1)),
  h4('4 h', Duration(hours: 4)),
  h8('8 h', Duration(hours: 8)),
  h24('24 h', Duration(hours: 24)),
  all('All time', null),
  dates('Dates', null);

  const DroneWindow(this.label, this.span);
  final String label;
  final Duration? span;
}

enum DroneSource {
  all('All'),
  rid('Remote ID'),
  fpv('FPV');

  const DroneSource(this.label);
  final String label;

  bool matches(DroneReport r) => switch (this) {
        all => true,
        rid => !r.fpv,
        fpv => r.fpv,
      };
}

class DronesScreen extends ConsumerStatefulWidget {
  const DronesScreen({super.key});

  @override
  ConsumerState<DronesScreen> createState() => _DronesScreenState();
}

class _DronesScreenState extends ConsumerState<DronesScreen> {
  static const _prefKey = 'drones_window';
  static const _sourceKey = 'drones_source';
  DroneWindow _window = DroneWindow.h24;
  DroneSource _source = DroneSource.all;
  DateTimeRange? _range;
  List<DroneReport> _reports = const [];
  bool _loaded = false;
  Timer? _timer;
  bool _windowChosen = false;
  bool _sourceChosen = false;

  @override
  void initState() {
    super.initState();
    _restoreWindow();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _restoreWindow() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_prefKey);
    if (!_windowChosen && saved != null) {
      for (final w in DroneWindow.values) {
        if (w.name == saved && w != DroneWindow.dates) _window = w;
      }
    }
    final savedSource = p.getString(_sourceKey);
    if (!_sourceChosen && savedSource != null) {
      for (final s in DroneSource.values) {
        if (s.name == savedSource) _source = s;
      }
    }
    await _reload();
  }

  Future<void> _pickSource(DroneSource s) async {
    _sourceChosen = true;
    setState(() => _source = s);
    final p = await SharedPreferences.getInstance();
    await p.setString(_sourceKey, s.name);
  }

  ({DateTime? from, DateTime? to}) get _bounds {
    final now = DateTime.now();
    if (_window == DroneWindow.dates && _range != null) {
      final r = _range!;
      return (
        from: DateTime(r.start.year, r.start.month, r.start.day),
        to: DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999),
      );
    }
    final span = _window.span;
    return (from: span == null ? null : now.subtract(span), to: null);
  }

  Future<void> _reload() async {
    final b = _bounds;
    final rows = await ref.read(droneLogProvider).query(from: b.from, to: b.to);
    if (!mounted) return;
    setState(() {
      _reports = rows;
      _loaded = true;
    });
  }

  Future<void> _pick(DroneWindow w) async {
    _windowChosen = true;
    if (w == DroneWindow.dates) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 3650)),
        lastDate: now,
        initialDateRange: _range,
      );
      if (picked == null) return;
      _range = picked;
    } else {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, w.name);
    }
    setState(() => _window = w);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final tags = ref.watch(droneTagsProvider);
    final units = ref.watch(unitSystemProvider);
    final now = DateTime.now();
    final shown = [for (final r in _reports) if (_source.matches(r)) r];
    final drones = summarizeDrones(shown, now);
    final counts = countDrones(drones);
    final top = counts.topHeight;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('DRONES'),
        actions: [
          IconButton(
            key: const Key('drones-export'),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export drone log',
            onPressed: () => shareDroneLog(context, shown, tags),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            DStatsStrip(
              key: const Key('drone-counts'),
              items: [
                ('${counts.live}', 'Live'),
                ('${counts.airborne}', 'Airborne'),
                ('${counts.pilots}', 'Pilots'),
                (top == null ? '-' : UnitFormatter.altitude(top.toDouble(), units), 'Top height'),
                ('${counts.inWindow}', 'In window'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final w in DroneWindow.values)
                  ChoiceChip(
                    key: Key('drone-window-${w.name}'),
                    label: Text(w == DroneWindow.dates && _range != null
                        ? '${_range!.start.month}/${_range!.start.day} to ${_range!.end.month}/${_range!.end.day}'
                        : w.label),
                    selected: _window == w,
                    onSelected: (_) => _pick(w),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in DroneSource.values)
                  ChoiceChip(
                    key: Key('drone-source-${s.name}'),
                    label: Text(s.label),
                    selected: _source == s,
                    onSelected: (_) => _pickSource(s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_source != DroneSource.rid) const _FpvReceiverCard(),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (drones.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    _source == DroneSource.fpv
                        ? 'No FPV transmitter was found in this window.'
                        : 'No drone was heard in this window.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textDim, fontSize: 13)),
              )
            else
              for (final d in drones)
                _DroneCard(
                  summary: d,
                  tag: tags[d.id],
                  units: units,
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => DronePage(id: d.id))),
                ),
          ],
        ),
      ),
    );
  }
}

class _FpvReceiverCard extends ConsumerWidget {
  const _FpvReceiverCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleManagerProvider);
    if (!(ble.board.toLowerCase().contains('c5') && ble.fpvAvailable)) return const SizedBox.shrink();
    final t = AppTheme.of(context);
    return StreamBuilder<FpvState>(
      stream: ble.fpvState,
      initialData: ble.latestFpvState,
      builder: (context, snap) {
        final s = snap.data ?? FpvState.empty;
        final color = !s.active
            ? t.textDim
            : s.hasError
                ? AppTheme.error
                : s.locked
                    ? AppTheme.success
                    : AppTheme.accent;
        final stats = <(String, String)>[
          if (s.active) ('Channel', '${fpvChannelName(s.channel)} · ${s.mhz} MHz'),
          if (s.active && s.level != fpvNoLevel) ('LVL', '${s.level}'),
          if (s.active) ('Flagged', '${s.flaggedCount}'),
        ];
        return Container(
          key: const Key('fpv-receiver-card'),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: color.withValues(alpha: s.active ? 0.8 : 0.3)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => context.push('/fpv'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.videocam, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('FPV RECEIVER',
                          style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppTheme.mono)),
                    ),
                    Text(fpvStateLabel(s),
                        key: const Key('fpv-receiver-state'),
                        style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppTheme.mono,
                            letterSpacing: 1)),
                    Icon(Icons.chevron_right, color: t.textDim, size: 18),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    s.active ? 'Analog 5.8 GHz video receiver' : 'Off · tap to open the receiver',
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      for (final x in stats)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${x.$1} ', style: TextStyle(color: t.textDim, fontSize: 11)),
                          Text(x.$2,
                              style: TextStyle(
                                  color: t.textPrimary, fontSize: 12, fontFamily: AppTheme.mono)),
                        ]),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DroneCard extends ConsumerWidget {
  const _DroneCard({
    required this.summary,
    required this.tag,
    required this.units,
    required this.onTap,
  });

  final DroneSummary summary;
  final DroneTag? tag;
  final UnitSystem units;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final d = summary;
    final last = d.last;
    final fpv = d.fpv;
    final alias = ref.watch(deviceNotesProvider)[DeviceNotesNotifier.keyOf(last.mac)]?.name.trim() ?? '';
    final reg = fpv ? null : ref.watch(faaCachedProvider(d.id)).valueOrNull;
    final maker = fpv ? null : droneMakerOf(d, reg);
    final color = tag?.color ?? droneColorForMac(last.mac);
    final range = fpv ? null : pilotRange(last);
    final stats = <(String, String)>[
      if (fpv) ...[
        ('Channel', fpvChannelText(d.id)),
        if (last.rssi != null) ('LVL', '${fpvRssiToLevel(last.rssi!)}'),
      ] else ...[
        if (last.height != null) ('Height', UnitFormatter.altitude(last.height!.toDouble(), units)),
        if (last.speed != null) ('Speed', '${last.speed} m/s'),
        if (range != null) ('Pilot', droneRangeText(range, units)),
        if (last.rssi != null) ('Signal', '${last.rssi} dBm'),
      ],
    ];
    return Container(
      key: Key('drone-card-${d.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: d.live ? 0.8 : 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(fpv ? Icons.videocam : Icons.flight, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(alias.isEmpty ? d.id : alias,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppTheme.mono)),
                ),
                if (tag != null) DroneTagBadge(tag!),
              ]),
              const SizedBox(height: 4),
              Text(
                [
                  if (alias.isNotEmpty) d.id,
                  if (fpv) 'Analog 5.8 GHz video',
                  if (maker != null) '${maker.name} (${maker.source})',
                  d.airborne ? 'In the air now' : droneHeardText(DateTime.now().difference(last.ts)),
                ].join(' · '),
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (final s in stats)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${s.$1} ', style: TextStyle(color: t.textDim, fontSize: 11)),
                      Text(s.$2,
                          style: TextStyle(
                              color: t.textPrimary, fontSize: 12, fontFamily: AppTheme.mono)),
                    ]),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
