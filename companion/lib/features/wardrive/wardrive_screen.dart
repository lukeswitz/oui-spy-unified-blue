import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/wardrive/wardrive_stats.dart';
import 'package:oui_spy/theme/app_theme.dart';

class WardriveScreen extends ConsumerStatefulWidget {
  const WardriveScreen({super.key});

  @override
  ConsumerState<WardriveScreen> createState() => _WardriveScreenState();
}

class _WardriveScreenState extends ConsumerState<WardriveScreen> {
  final _mapController = MapController();

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
  }

  @override
  Widget build(BuildContext context) {
    final wd = ref.watch(wardriveProvider);
    final center = wd.currentPosition != null
        ? LatLng(wd.currentPosition!.latitude, wd.currentPosition!.longitude)
        : const LatLng(38.627, -90.199);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                backgroundColor: const Color(0xFF0A0A0A),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
                  userAgentPackageName: 'tech.colonelpanic.ouispy',
                  maxZoom: 19,
                ),
                if (wd.routePoints.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: wd.routePoints,
                      color: Colors.white.withValues(alpha: 0.7),
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

            // Idle: mode selector + start
            if (!wd.isActive)
              Positioned(
                bottom: 24, left: 0, right: 0,
                child: _IdleControls(wd: wd, ref: ref),
              ),

            // Active: focus button (top-right, below stats)
            if (wd.isActive)
              Positioned(
                top: 90, right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconBtn(
                      icon: Icons.my_location,
                      onTap: () => _focusMap(wd),
                    ),
                    if (wd.foxhuntTarget != null) ...[
                      const SizedBox(height: 6),
                      _FoxhuntBadge(mac: wd.foxhuntTarget!),
                    ],
                  ],
                ),
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

  bool _isFlock(Engine e) => e == Engine.flockBle || e == Engine.flockWifi;

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
          _Pill(label: 'PAUSE', color: AppTheme.warning,
              onTap: () => ref.read(wardriveProvider).pauseSession()),
          const SizedBox(width: 12),
          _Pill(label: 'STOP', color: AppTheme.error,
              onTap: () => ref.read(wardriveProvider).stopSession()),
        ]),
      WardriveState.paused => Row(mainAxisSize: MainAxisSize.min, children: [
          _Pill(label: 'RESUME', color: AppTheme.success,
              onTap: () => ref.read(wardriveProvider).resumeSession()),
          const SizedBox(width: 12),
          _Pill(label: 'STOP', color: AppTheme.error,
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
    final t = wd.target;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border, width: 0.5),
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
                            Icon(m.icon, size: 16, color: sel ? m.color : AppTheme.textDim),
                            const SizedBox(height: 2),
                            Text(
                              m.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: sel ? m.color : AppTheme.textDim,
                                fontSize: 8, fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
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
                          onTap: () => ref.read(wardriveProvider).setRadio(r),
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
                                    color: sel ? t.color : AppTheme.textDim),
                                const SizedBox(width: 4),
                                Text(r.label, style: TextStyle(
                                  color: sel ? t.color : AppTheme.textDim,
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
            color: AppTheme.background.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border, width: 0.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.straighten, size: 12, color: AppTheme.textDim),
              const SizedBox(width: 6),
              const Text('DIST', style: TextStyle(
                color: AppTheme.textDim, fontSize: 8,
                fontWeight: FontWeight.w600, letterSpacing: 1,
              )),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay),
                  child: Slider(
                    value: wd.markerDistanceM,
                    min: 1, max: 100,
                    activeColor: AppTheme.accent,
                    inactiveColor: AppTheme.border,
                    onChanged: (v) {
                      ref.read(wardriveProvider).markerDistanceM = v;
                      ref.read(wardriveProvider).notifyListeners();
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
        _Pill(
          label: 'START',
          color: t.color,
          onTap: () => ref.read(wardriveProvider).startSession(),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: const TextStyle(
          color: AppTheme.background, fontSize: 13,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label, required this.icon,
    required this.active, required this.color, required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.2)
              : AppTheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : AppTheme.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? color : AppTheme.textDim),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            color: active ? color : AppTheme.textDim,
            fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1,
          )),
        ]),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(icon, size: 16, color: AppTheme.textSecondary),
      ),
    );
  }
}

class _DetectionList extends StatelessWidget {
  const _DetectionList({required this.detections});
  final List<Detection> detections;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<Detection>>{};
    for (final d in detections) {
      final key = d.engine.label;
      (grouped[key] ??= []).add(d);
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
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
            style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 9,
              fontFamily: 'monospace', fontWeight: FontWeight.w500,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
            )),
          ] else
            const Spacer(),
          if (d.count > 1)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('\u00d7${d.count}',
                style: const TextStyle(
                  color: AppTheme.textDim, fontSize: 8,
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
                color: AppTheme.background,
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

class _FoxhuntBadge extends StatelessWidget {
  const _FoxhuntBadge({required this.mac});
  final String mac;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.9),
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
