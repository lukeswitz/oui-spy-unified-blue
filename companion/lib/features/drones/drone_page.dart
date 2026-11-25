// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_log.dart';
import 'package:oui_spy/core/drone_tags.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/services/faa_service.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/drones/drone_data.dart';
import 'package:oui_spy/features/drones/drone_kit_section.dart';
import 'package:oui_spy/features/wardrive/drone_markers.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_spec_row.dart';
import 'package:oui_spy/widgets/disabled_reason.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

class DronePage extends ConsumerStatefulWidget {
  const DronePage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<DronePage> createState() => _DronePageState();
}

class _DronePageState extends ConsumerState<DronePage> {
  List<DroneReport> _reports = const [];
  bool _loaded = false;
  int? _flightIndex;
  Timer? _timer;
  FaaRegistration? _faa;
  String? _faaNote;
  bool _faaBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final all = await ref.read(droneLogProvider).query();
    if (!mounted) return;
    setState(() {
      _reports = [for (final r in all) if (r.id == widget.id) r];
      _loaded = true;
    });
  }

  Future<void> _lookupFaa() async {
    setState(() {
      _faaBusy = true;
      _faaNote = null;
    });
    try {
      final reg = await ref.read(faaServiceProvider).lookup(widget.id);
      if (!mounted) return;
      setState(() {
        _faa = reg;
        _faaNote = reg == null ? 'no record for this serial' : null;
      });
    } on FaaLookupException catch (e) {
      if (!mounted) return;
      setState(() => _faaNote = 'no answer: ${e.message}');
    } finally {
      if (mounted) setState(() => _faaBusy = false);
    }
  }

  Detection? _liveDetection() {
    final now = DateTime.now();
    Detection? best;
    for (final d in ref.read(appStateProvider).recentDetections) {
      if (d.engine != Engine.skySpy || droneIdOf(d) != widget.id) continue;
      if (droneRidPoint(d) == null) continue;
      if (now.difference(d.appTimestamp) > const Duration(minutes: 2)) continue;
      if (best == null || d.appTimestamp.isAfter(best.appTimestamp)) best = d;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final tags = ref.watch(droneTagsProvider);
    final units = ref.watch(unitSystemProvider);
    final tag = tags[widget.id];
    final now = DateTime.now();
    final summary = _reports.isEmpty
        ? null
        : DroneSummary(id: widget.id, reports: _reports, now: now);
    final flights = summary?.flights ?? const <DroneFlight>[];
    final idx = flights.isEmpty
        ? null
        : (_flightIndex ?? flights.length - 1).clamp(0, flights.length - 1);
    final flight = idx == null ? null : flights[idx];
    final cachedFaa = ref.watch(faaCachedProvider(widget.id)).valueOrNull;
    final reg = _faa ?? cachedFaa;
    final maker = summary == null ? null : droneMakerOf(summary, reg);
    final live = _liveDetection();
    final color = tag?.color ??
        (summary == null ? AppTheme.skySpy : droneColorForMac(summary.last.mac));

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('DRONE'),
        actions: [
          IconButton(
            key: const Key('drone-page-export'),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export logs',
            onPressed: () => shareDroneLog(context, _reports, tags, title: widget.id),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                DPageTitle(widget.id),
                const SizedBox(height: 4),
                Text(
                  [
                    if (summary != null)
                      summary.airborne
                          ? 'In the air now'
                          : droneHeardText(now.difference(summary.last.ts)),
                    if (maker != null) '${maker.name} (${maker.source})',
                  ].join(' · '),
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                ),
                const DSectionHeader(label: 'Its tag'),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final v in DroneTag.values)
                    ChoiceChip(
                      key: Key('drone-tag-${v.name}'),
                      avatar: Icon(v.icon, size: 16, color: v.color),
                      label: Text(v.label),
                      selected: tag == v,
                      onSelected: (on) =>
                          ref.read(droneTagsProvider.notifier).set(widget.id, on ? v : null),
                    ),
                ]),
                const SizedBox(height: 12),
                _MapActions(live: live),
                const SizedBox(height: 12),
                if (flight == null)
                  Text('No report of this drone is in the log yet.',
                      style: TextStyle(color: t.textDim, fontSize: 13))
                else
                  _FlightMap(
                    key: ValueKey('flight-map-${flight.start.millisecondsSinceEpoch}'),
                    flight: flight,
                    color: color,
                    units: units,
                  ),
                if (summary != null && flight != null) ...[
                  const DSectionHeader(label: 'Flight'),
                  ..._rows(summary, flight, units),
                ],
                const DSectionHeader(label: 'FAA record'),
                _FaaBlock(
                  summary: summary,
                  reg: reg,
                  note: _faaNote,
                  busy: _faaBusy,
                  onLookup: _lookupFaa,
                ),
                if (flights.isNotEmpty) ...[
                  const DSectionHeader(label: 'Past flights'),
                  for (var i = flights.length - 1; i >= 0; i--)
                    _FlightRow(
                      flight: flights[i],
                      selected: i == idx,
                      units: units,
                      onTap: () => setState(() => _flightIndex = i),
                    ),
                ],
                DroneKitSection(droneId: widget.id, flights: flights),
              ],
            ),
    );
  }

  List<Widget> _rows(DroneSummary s, DroneFlight f, UnitSystem units) {
    final last = f.reports.last;
    String len(num m) => UnitFormatter.altitude(m.toDouble(), units);
    final range = f.detectionRange;
    final pilot = pilotRange(last);
    return [
      DSpecRow(label: 'Last report', value: DateFormat('MMM d HH:mm:ss').format(last.ts)),
      DSpecRow(label: 'First heard', value: DateFormat('MMM d HH:mm:ss').format(f.start)),
      if (last.height != null) DSpecRow(label: 'Height', value: len(last.height!)),
      if (last.alt != null) DSpecRow(label: 'GPS alt', value: len(last.alt!)),
      if (last.speed != null) DSpecRow(label: 'Speed', value: '${last.speed} m/s'),
      if (pilot != null) DSpecRow(label: 'Pilot distance', value: droneRangeText(pilot, units)),
      if (range != null)
        DSpecRow(
          key: const Key('drone-detection-range'),
          label: 'Detection location',
          value: '${droneRangeText(range, units)} to the drone',
        ),
      if (last.rssi != null) DSpecRow(label: 'Signal', value: '${last.rssi} dBm'),
      if (s.macs.length > 1 || !s.macs.contains(s.id))
        DSpecRow(label: 'Also heard as', value: s.macs.map((m) => m.toUpperCase()).join('\n'), mono: true),
    ];
  }
}

class _MapActions extends ConsumerWidget {
  const _MapActions({required this.live});
  final Detection? live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final det = live;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('drone-show-on-map'),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Show on map'),
              onPressed: det == null
                  ? null
                  : () {
                      final p = droneRidPoint(det)!;
                      ref.read(wardriveProvider).requestZoom(p.latitude, p.longitude, detection: det);
                      context.go('/wardrive');
                    },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('drone-follow'),
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Follow'),
              onPressed: det == null
                  ? null
                  : () {
                      ref.read(wardriveProvider).requestFollowDrone(det);
                      context.go('/wardrive');
                    },
            ),
          ),
        ]),
        if (det == null)
          const DisabledReason('Needs a live position: this drone has not been heard in the last 2 minutes.'),
      ],
    );
  }
}

class _FlightMap extends StatelessWidget {
  const _FlightMap({super.key, required this.flight, required this.color, required this.units});
  final DroneFlight flight;
  final Color color;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final path = flight.path;
    final pilot = flight.lastPilotPoint;
    final here = flight.detectionPoint;
    final last = flight.lastDronePoint;
    final spot = detectionLocationLayers(here: here, drone: last, color: color, units: units);
    final all = [...path, ?pilot, ?here];
    final t = AppTheme.of(context);
    if (all.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Text('No position was reported on this flight.',
            style: TextStyle(color: t.textDim, fontSize: 13)),
      );
    }
    return Consumer(builder: (context, ref, _) {
      final style = ref.watch(mapStyleProvider);
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          key: const Key('drone-flight-map'),
          height: 260,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: all.first,
              initialZoom: 16,
              initialCameraFit: all.length >= 2
                  ? CameraFit.coordinates(
                      coordinates: all, padding: const EdgeInsets.all(40), maxZoom: 18)
                  : null,
              backgroundColor: style.isDark ? Colors.black : Colors.white,
            ),
            children: [
              mapTileLayer(style),
              if (path.length >= 2)
                PolylineLayer(polylines: [Polyline(points: path, color: color, strokeWidth: 2.4)]),
              if (last != null && pilot != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [last, pilot],
                    color: color.withValues(alpha: 0.65),
                    strokeWidth: 1.6,
                    pattern: StrokePattern.dashed(segments: const [6, 6]),
                  ),
                ]),
              if (spot != null) PolylineLayer(polylines: [spot.line]),
              if (spot != null) MarkerLayer(markers: spot.markers),
              MarkerLayer(markers: [
                if (last != null)
                  Marker(
                    point: last,
                    width: 42,
                    height: 42,
                    child: DronePin(color: color, size: 26),
                  ),
                if (pilot != null)
                  Marker(
                    point: pilot,
                    width: 36,
                    height: 36,
                    child: PilotPin(color: color, size: 22),
                  ),
              ]),
              mapAttribution(style),
            ],
          ),
        ),
      );
    });
  }
}

class _FlightRow extends StatelessWidget {
  const _FlightRow({
    required this.flight,
    required this.selected,
    required this.units,
    required this.onTap,
  });
  final DroneFlight flight;
  final bool selected;
  final UnitSystem units;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    String len(num m) => UnitFormatter.altitude(m.toDouble(), units);
    final h = flight.maxHeight;
    final speed = flight.maxSpeed;
    final flown = flight.flownMeters;
    final pilot = flight.farthestFromPilot;
    final range = flight.detectionRange;
    final parts = [
      droneDuration(flight.duration),
      if (h != null) 'max ${len(h)} high',
      if (speed != null) 'max $speed m/s',
      if (flown > 0) '${len(flown)} flown',
      if (pilot != null) 'pilot to ${len(pilot)}',
      if (range != null) 'detected from ${len(range)}',
    ];
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18, color: selected ? AppTheme.accent : t.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('MMM d HH:mm').format(flight.start),
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600)),
              Text(parts.join(' · '), style: TextStyle(color: t.textSecondary, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FaaBlock extends StatelessWidget {
  const _FaaBlock({
    required this.summary,
    required this.reg,
    required this.note,
    required this.busy,
    required this.onLookup,
  });
  final DroneSummary? summary;
  final FaaRegistration? reg;
  final String? note;
  final bool busy;
  final VoidCallback onLookup;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final state = s == null ? FaaState.noSerial : faaStateOf(s);
    final r = reg;
    final rows = <(String, String)>[
      if (r != null && r.status.isNotEmpty) ('Status', r.status),
      if (r != null && r.displayName.isNotEmpty) ('Aircraft', r.displayName),
      if (r != null && r.makeName.isNotEmpty) ('Make', r.makeName),
      if (r != null && r.series.isNotEmpty) ('Series', r.series),
      if (r != null && r.productType.isNotEmpty) ('Type', r.productType),
      if (r != null && r.operationRules.isNotEmpty) ('Rules', r.operationRules),
      if (r != null && r.trackingNumber.isNotEmpty) ('Tracking #', r.trackingNumber),
    ];
    final reason = switch (state) {
      FaaState.noSerial => 'No serial broadcast yet: the FAA registry is searched by serial.',
      FaaState.notIndexed => 'Not a serial the FAA indexes.',
      FaaState.ready => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) DSpecRow(label: row.$1, value: row.$2),
        if (r == null && reason == null && note == null)
          const DisabledReason('Not looked up yet.'),
        if (note != null) DisabledReason(note!),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('drone-faa-lookup'),
          icon: const Icon(Icons.travel_explore, size: 18),
          label: Text(busy ? 'Looking up…' : 'FAA lookup'),
          onPressed: busy || state != FaaState.ready ? null : onLookup,
        ),
        if (reason != null) DisabledReason(reason),
      ],
    );
  }
}
