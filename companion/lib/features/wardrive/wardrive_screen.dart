import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/orchestrator.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/wardrive/wardrive_stats.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';

class WardriveScreen extends ConsumerStatefulWidget {
  const WardriveScreen({super.key});

  @override
  ConsumerState<WardriveScreen> createState() => _WardriveScreenState();
}

class _WardriveScreenState extends ConsumerState<WardriveScreen> {
  final _mapController = MapController();
  bool _followMode = true;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _focusMap(WardriveController wd) {
    final pos = wd.currentPosition ?? ref.read(gpsProvider).lastPosition;
    if (pos == null) return;
    _mapController.move(
      LatLng(pos.latitude, pos.longitude),
      _mapController.camera.zoom,
    );
    if (!_followMode) setState(() => _followMode = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wd = ref.watch(wardriveProvider);
    final gpsPos = ref.read(gpsProvider).lastPosition;
    final center = wd.currentPosition != null
        ? LatLng(wd.currentPosition!.latitude, wd.currentPosition!.longitude)
        : gpsPos != null
            ? LatLng(gpsPos.latitude, gpsPos.longitude)
            : const LatLng(38.627, -90.199);

    // Auto-follow: keep map centered on current position while moving
    if (_followMode && wd.isActive && wd.currentPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(
          LatLng(wd.currentPosition!.latitude, wd.currentPosition!.longitude),
          _mapController.camera.zoom,
        );
      });
    }

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFE8E8EE),
                onMapEvent: (event) {
                  if (event is MapEventMoveStart &&
                      event.source == MapEventSource.dragStart) {
                    if (_followMode) setState(() => _followMode = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: isDark
                      ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                      : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                  userAgentPackageName: 'tech.colonelpanic.ouispy',
                  maxZoom: 19,
                ),
                if (wd.routePoints.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: wd.routePoints,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppTheme.accent.withValues(alpha: 0.6),
                      strokeWidth: 2.5,
                    ),
                  ]),
                MarkerLayer(
                  markers: _distanceFilteredMarkers(wd),
                ),
                if (wd.currentPosition != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(
                        wd.currentPosition!.latitude,
                        wd.currentPosition!.longitude,
                      ),
                      width: 16, height: 16,
                      child: Container(decoration: BoxDecoration(
                        color: AppTheme.accent, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.4),
                          blurRadius: 8,
                        )],
                      )),
                    ),
                  ]),
              ],
            ),

            // Stats bar (top, only when active)
            if (wd.isActive)
              Positioned(
                top: 0, left: 0, right: 0,
                child: WardriveStats(stats: wd.currentStats),
              ),

            // Idle: completed session summary (if map data present)
            if (!wd.isActive && wd.hasSessionData)
              Positioned(
                top: 0, left: 0, right: 0,
                child: _CompletedSessionBar(wd: wd, ref: ref),
              ),

            // Idle: mode selector + start
            if (!wd.isActive)
              Positioned(
                bottom: 24, left: 0, right: 0,
                child: _IdleControls(wd: wd, ref: ref),
              ),

            // Active: focus button (top-right, below stats)
            if (wd.isActive)
              Positioned(
                top: 130, right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBtn(
                      icon: _followMode ? Icons.my_location : Icons.location_searching,
                      onTap: () => _focusMap(wd),
                      active: _followMode,
                    ),
                    if (wd.foxhuntTarget != null) ...[
                      const SizedBox(height: 6),
                      _FoxhuntBadge(mac: wd.foxhuntTarget!),
                    ],
                  ],
                ),
              ),

            // Active: node stats overlay (top-left, below stats)
            if (wd.isActive && ref.watch(appStateProvider).meshEnabled)
              Positioned(
                top: 130, left: 12,
                child: _NodeStatsOverlay(ref: ref),
              ),

            // Active: pause/stop controls + flock panel below
            if (wd.isActive)
              Positioned(
                bottom: 16, left: 0, right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: _runControls(ref, wd)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _DetectionList(detections: wd.dedupedDetections),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Marker> _distanceFilteredMarkers(WardriveController wd) {
    final geoDetections = wd.dedupedDetections
        .where((d) => d.latitude != null && d.longitude != null)
        .toList();
    final distThresh = wd.markerDistanceM;
    final filtered = <Detection>[];
    final placed = <LatLng>[];

    for (final d in geoDetections) {
      final ll = LatLng(d.latitude!, d.longitude!);
      bool tooClose = false;
      for (final p in placed) {
        final dx = (ll.latitude - p.latitude) * 111320;
        final dy = (ll.longitude - p.longitude) * 111320 *
            cos(ll.latitude * pi / 180);
        if (dx * dx + dy * dy < distThresh * distThresh) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) {
        filtered.add(d);
        placed.add(ll);
      }
    }

    final densityMap = <int, int>{};
    for (var i = 0; i < filtered.length; i++) {
      densityMap[i] = (densityMap[i] ?? 0) + 1;
    }
    for (final d in geoDetections) {
      final ll = LatLng(d.latitude!, d.longitude!);
      for (var i = 0; i < filtered.length; i++) {
        final f = filtered[i];
        final fl = LatLng(f.latitude!, f.longitude!);
        final dx = (ll.latitude - fl.latitude) * 111320;
        final dy = (ll.longitude - fl.longitude) * 111320 *
            cos(ll.latitude * pi / 180);
        if (dx * dx + dy * dy < distThresh * distThresh) {
          densityMap[i] = (densityMap[i] ?? 1) + 1;
          break;
        }
      }
    }

    return filtered.asMap().entries.map((entry) {
      final d = entry.value;
      final count = densityMap[entry.key] ?? 1;
      final size = (12 + (count.clamp(1, 20) * 1.5)).toDouble();
      final alpha = (0.3 + (count.clamp(1, 10) * 0.07)).clamp(0.3, 1.0);

      return Marker(
        point: LatLng(d.latitude!, d.longitude!),
        width: size + 8,
        height: size + 8,
        child: _MarkerDot(engine: d.engine, size: size, alpha: alpha, count: count),
      );
    }).toList();
  }

  Widget _runControls(WidgetRef ref, WardriveController wd) {
    return switch (wd.state) {
      WardriveState.idle => const SizedBox.shrink(),
      WardriveState.running => Row(mainAxisSize: MainAxisSize.min, children: [
          _OutlinePill(label: 'PAUSE', color: AppTheme.textSecondary,
              onTap: () => ref.read(wardriveProvider).pauseSession()),
          const SizedBox(width: 12),
          _Pill(label: 'STOP', color: AppTheme.error,
              onTap: () => ref.read(wardriveProvider).stopSession()),
        ]),
      WardriveState.paused => Row(mainAxisSize: MainAxisSize.min, children: [
          _Pill(label: 'RESUME', color: AppTheme.success,
              onTap: () => ref.read(wardriveProvider).resumeSession()),
          const SizedBox(width: 12),
          _OutlinePill(label: 'STOP', color: AppTheme.error,
              onTap: () => ref.read(wardriveProvider).stopSession()),
        ]),
    };
  }
}

class _IdleControls extends StatelessWidget {
  const _IdleControls({required this.wd, required this.ref});
  final WardriveController wd;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final th = AppTheme.of(context);
    final t = wd.target;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: th.background.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: th.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: WardriveTarget.values.map((m) {
                  final sel = m == t;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => ref.read(wardriveProvider).setTarget(m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: sel ? m.color.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: sel ? Border.all(color: m.color.withValues(alpha: 0.4)) : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(m.icon, size: 16, color: sel ? m.color : th.textDim),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  m.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: sel ? m.color : th.textDim,
                                    fontSize: 8, fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (t.hasRadioChoice) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: WardriveRadio.values.map((r) {
                      final sel = r == wd.radio;
                      final radioIcon = switch (r) {
                        WardriveRadio.wifi => Icons.wifi,
                        WardriveRadio.ble => Icons.bluetooth,
                        WardriveRadio.both => Icons.sensors,
                      };
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            ref.read(wardriveProvider).setRadio(r);
                            ref.read(appStateProvider).setEngineRadio(
                              Engine.wardrive,
                              switch (r) {
                                WardriveRadio.wifi => 0x01,
                                WardriveRadio.ble => 0x02,
                                WardriveRadio.both => 0x03,
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: sel ? t.color.withValues(alpha: 0.1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(radioIcon, size: 12,
                                    color: sel ? t.color : th.textDim),
                                const SizedBox(width: 4),
                                Text(r.label, style: TextStyle(
                                  color: sel ? t.color : th.textDim,
                                  fontSize: 9, fontWeight: FontWeight.w600,
                                )),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: th.background.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: th.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.straighten, size: 12, color: th.textDim),
              const SizedBox(width: 6),
              Text('DIST', style: TextStyle(
                color: th.textDim, fontSize: 8,
                fontWeight: FontWeight.w600, letterSpacing: 1,
              )),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay),
                  child: Slider(
                    value: wd.markerDistanceM,
                    min: 1, max: 100,
                    activeColor: AppTheme.accent,
                    inactiveColor: th.border,
                    onChanged: (v) {
                      ref.read(wardriveProvider).markerDistanceM = v;
                    },
                  ),
                ),
              ),
              Text('${wd.markerDistanceM.round()}m', style: const TextStyle(
                color: AppTheme.accent, fontSize: 10,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: ref.context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _SessionHistorySheet(),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: th.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: th.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 14, color: th.textSecondary),
                    const SizedBox(width: 6),
                    Text('SESSIONS', style: TextStyle(
                      color: th.textSecondary, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1,
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _Pill(
              label: 'START',
              color: t.color,
              onTap: () => ref.read(wardriveProvider).startSession(),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          color: t.background, fontSize: 13,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ),
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(
          color: color, fontSize: 13,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.15)
              : t.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppTheme.accent.withValues(alpha: 0.6) : t.border,
          ),
        ),
        child: Icon(icon, size: 16,
            color: active ? AppTheme.accent : t.textSecondary),
      ),
    );
  }
}

class _DetectionList extends StatelessWidget {
  const _DetectionList({required this.detections});
  final List<Detection> detections;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    if (detections.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<Detection>>{};
    for (final d in detections) {
      final key = d.engine.label;
      (grouped[key] ??= []).add(d);
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
              child: Row(
                children: [
                  Icon(entry.value.first.engine.icon,
                      size: 10, color: entry.value.first.engine.color),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.key.toUpperCase()}  ${entry.value.length}',
                    style: TextStyle(
                      color: entry.value.first.engine.color,
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.take(10).map((d) => _DetListRow(d: d)),
          ],
        ],
      ),
    );
  }
}

class _DetListRow extends StatelessWidget {
  const _DetListRow({required this.d});
  final Detection d;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
    final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
    final label = d.ssid.isNotEmpty
        ? d.ssid
        : d.deviceName.isNotEmpty
            ? d.deviceName
            : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Container(width: 2, height: 14,
            decoration: BoxDecoration(
              color: d.engine.color, borderRadius: BorderRadius.circular(1)),
          ),
          const SizedBox(width: 5),
          Text(d.macAddress.toUpperCase(),
            style: TextStyle(
              color: t.textPrimary, fontSize: 9,
              fontFamily: 'monospace', fontWeight: FontWeight.w500,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textSecondary, fontSize: 9),
            )),
          ] else
            const Spacer(),
          if (d.count > 1)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('\u00d7${d.count}',
                style: TextStyle(
                  color: t.textDim, fontSize: 8,
                  fontFamily: 'monospace', fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text('${d.rssi}', style: TextStyle(
            color: rssiColor, fontSize: 9,
            fontFamily: 'monospace', fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}

class _MarkerDot extends StatelessWidget {
  const _MarkerDot({required this.engine, required this.size, required this.alpha, required this.count});
  final Engine engine;
  final double size;
  final double alpha;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isFlock = engine == Engine.flockBle || engine == Engine.flockWifi;
    final isDrone = engine == Engine.skySpy;
    final showIcon = isFlock || isDrone;
    final iconData = isFlock ? Icons.videocam : isDrone ? Icons.flight : null;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size + 6,
          height: size + 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: engine.color.withValues(alpha: alpha * 0.3),
          ),
        ),
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: engine.color.withValues(alpha: alpha),
            border: Border.all(color: engine.color, width: 1.5),
          ),
          child: showIcon && size > 14
              ? Icon(iconData, size: size * 0.55, color: Colors.white.withValues(alpha: 0.9))
              : null,
        ),
        if (count > 1 && size > 16)
          Positioned(
            right: 0, top: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: t.background,
                shape: BoxShape.circle,
                border: Border.all(color: engine.color, width: 0.5),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: engine.color, fontSize: 7,
                  fontWeight: FontWeight.w700, fontFamily: 'monospace',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompletedSessionBar extends ConsumerWidget {
  const _CompletedSessionBar({required this.wd, required this.ref});
  final WardriveController wd;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final t = AppTheme.of(context);
    final units = wRef.watch(unitSystemProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${wd.uniqueMacs.length} unique  \u00b7  ${wd.rawDetectionCount} total  \u00b7  ${UnitFormatter.distance(wd.distanceKm, units)}',
              style: TextStyle(
                color: t.textSecondary, fontSize: 10,
                fontFamily: 'monospace', fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _shareCsv(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload, size: 12, color: AppTheme.accent),
                  SizedBox(width: 4),
                  Text('CSV', style: TextStyle(
                    color: AppTheme.accent, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5,
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => wd.clearMapData(),
            child: Icon(Icons.close, size: 14, color: t.textDim),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCsv(BuildContext context) async {
    final sid = wd.lastCompletedSessionId ?? wd.sessionId;
    if (sid.isEmpty) return;
    final file = await wd.getCsvFile(sid);
    if (file == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No CSV file found for this session')),
        );
      }
      return;
    }
    await Share.shareXFiles([XFile(file.path)], subject: 'OUI-SPY WiGLE CSV');
  }
}

class _SessionHistorySheet extends ConsumerWidget {
  const _SessionHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final db = ref.watch(databaseProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32, height: 3,
                decoration: BoxDecoration(
                  color: t.textDim, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              Text('WARDRIVE SESSIONS', style: TextStyle(
                color: t.textPrimary, fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: 1.5,
              )),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<Session>>(
                  stream: db.watchWardriveSessions(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(
                        color: AppTheme.accent, strokeWidth: 2));
                    }
                    final sessions = snapshot.data!
                        .where((s) => s.endedAt != null)
                        .toList();
                    if (sessions.isEmpty) {
                      return Center(child: Text(
                        'No completed sessions',
                        style: TextStyle(color: t.textDim, fontSize: 12),
                      ));
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: sessions.length,
                      itemBuilder: (_, i) => _SessionRow(
                        session: sessions[i],
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(wardriveProvider).loadSession(sessions[i].id);
                        },
                        onShare: () => _shareSession(context, ref, sessions[i].id),
                        onDelete: () => _deleteSession(context, ref, sessions[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSession(BuildContext context, WidgetRef ref, Session session) async {
    final t = AppTheme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Delete Session', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Delete this session and all its ${session.detectionCount} detections? This cannot be undone.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await db.deleteSession(session.id);
      // Clear loaded session if it was the deleted one
      final wd = ref.read(wardriveProvider);
      if (wd.loadedSessionId == session.id) {
        wd.clearLoadedSession();
      }
    }
  }

  Future<void> _shareSession(BuildContext context, WidgetRef ref, String sid) async {
    final wd = ref.read(wardriveProvider);
    final file = await wd.getCsvFile(sid);
    if (file != null) {
      await Share.shareXFiles([XFile(file.path)], subject: 'OUI-SPY WiGLE CSV');
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV not found \u2014 session may predate auto-save')),
        );
      }
    }
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({super.key, required this.session, required this.onTap, required this.onShare, required this.onDelete});
  final Session session;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    final start = DateTime.fromMillisecondsSinceEpoch(session.startedAt);
    final dateStr = DateFormat('MMM d, yyyy  HH:mm').format(start);
    final duration = session.endedAt != null
        ? Duration(milliseconds: session.endedAt! - session.startedAt)
        : Duration.zero;
    final durStr = '${duration.inMinutes}m ${duration.inSeconds % 60}s';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.route, size: 16, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr, style: TextStyle(
                    color: t.textPrimary, fontSize: 11,
                    fontFamily: 'monospace', fontWeight: FontWeight.w500,
                  )),
                  const SizedBox(height: 2),
                  Text(
                    '$durStr  \u00b7  ${session.detectionCount} det  \u00b7  ${session.uniqueMacCount} mac  \u00b7  ${UnitFormatter.distance(session.distanceKm, units)}',
                    style: TextStyle(
                      color: t.textDim, fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onShare,
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.ios_share, size: 14, color: t.textDim),
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, size: 14, color: AppTheme.error.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoxhuntBadge extends StatelessWidget {
  const _FoxhuntBadge({required this.mac});
  final String mac;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.foxhunter.withValues(alpha: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.gps_fixed, color: AppTheme.foxhunter, size: 20),
        const SizedBox(height: 4),
        Text(
          mac.substring(0, 8),
          style: const TextStyle(
            color: AppTheme.foxhunter, fontSize: 9, fontFamily: 'monospace',
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Node Stats Overlay — shows peer nodes + their detection counts
// ---------------------------------------------------------------------------

class _NodeStatsOverlay extends ConsumerWidget {
  const _NodeStatsOverlay({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final orchestrator = ref.watch(orchestratorProvider);
    final appState = ref.watch(appStateProvider);
    final peers = orchestrator.activePeers;

    if (peers.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxWidth: 160),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hub, size: 10, color: AppTheme.accent),
              const SizedBox(width: 4),
              Text(
                '${peers.length + 1} NODES',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Self
          _NodeRow(
            name: appState.nodeId.isNotEmpty ? appState.nodeId : 'LOCAL',
            count: appState.countForEngine(Engine.wardrive),
            isSelf: true,
            t: t,
          ),
          // Peers
          ...peers.map((p) => _NodeRow(
            name: p.name ?? p.nodeId,
            count: p.detectionCount,
            isSelf: false,
            t: t,
          )),
        ],
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.name,
    required this.count,
    required this.isSelf,
    required this.t,
  });
  final String name;
  final int count;
  final bool isSelf;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              color: isSelf ? AppTheme.accent : AppTheme.flockBle,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                color: isSelf ? AppTheme.accent : t.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
