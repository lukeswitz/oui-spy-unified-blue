import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/theme/app_theme.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final Map<String, Detection> _dedupedDetections = {}; // MAC|engine → latest
  final List<LatLng> _routePoints = [];
  GpsPosition? _currentPosition;
  StreamSubscription<Detection>? _detSub;
  StreamSubscription<GpsPosition>? _gpsSub;
  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    final ble = ref.read(bleManagerProvider);
    _detSub = ble.detections.listen((d) {
      if (!mounted) return;
      final key = '${d.macAddress}|${d.engine.name}';
      setState(() => _dedupedDetections[key] = d);
    });
    final gps = ref.read(gpsProvider);

    final cached = gps.lastPosition;
    if (cached != null) {
      _currentPosition = cached;
      _routePoints.add(LatLng(cached.latitude, cached.longitude));
    }

    _gpsSub = gps.positionStream.listen((pos) {
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentPosition = pos;
        // Only add route point if moved at least 2m from last point
        if (_routePoints.isEmpty || _distanceM(_routePoints.last, ll) > 2) {
          _routePoints.add(ll);
        }
      });
      if (_followUser) {
        _mapController.move(ll, _mapController.camera.zoom);
      }
    });
  }

  double _distanceM(LatLng a, LatLng b) {
    final dx = (a.latitude - b.latitude) * 111320;
    final dy = (a.longitude - b.longitude) * 111320 * 0.85; // rough cos
    return (dx * dx + dy * dy).abs();
  }

  @override
  void dispose() {
    _detSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(38.627, -90.199);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = AppTheme.of(context);
    final tileUrl = isDark
        ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
        : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png';

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              backgroundColor: isDark ? const Color(0xFF0A0A0F) : const Color(0xFFE8E8EE),
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) _followUser = false;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'tech.colonelpanic.ouispy',
                maxZoom: 19,
              ),
              // Route trace
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.white.withValues(alpha: 0.6),
                      strokeWidth: 2,
                    ),
                  ],
                ),
              // Detection markers (deduplicated by MAC+engine)
              MarkerLayer(
                markers: _dedupedDetections.values
                    .where((d) => d.latitude != null && d.longitude != null)
                    .map((d) => Marker(
                          point: LatLng(d.latitude!, d.longitude!),
                          width: 12,
                          height: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: d.engine.color.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: d.engine.color,
                                width: 1,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              // Current position
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 16,
                      height: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // GPS info bar (bottom)
          if (_currentPosition != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _GpsInfoBar(position: _currentPosition!),
            ),
          // Re-center button
          if (!_followUser)
            Positioned(
              bottom: 50,
              right: 16,
              child: FloatingActionButton.small(
                backgroundColor: t.surface,
                foregroundColor: AppTheme.accent,
                onPressed: () {
                  _followUser = true;
                  if (_currentPosition != null) {
                    _mapController.move(
                      LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      _mapController.camera.zoom,
                    );
                  }
                },
                child: const Icon(Icons.my_location, size: 18),
              ),
            ),
          // Detection count overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 48,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Text(
                '${_dedupedDetections.length} detections',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsInfoBar extends ConsumerWidget {
  const _GpsInfoBar({required this.position});
  final GpsPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _InfoChip('LAT', position.latitude.toStringAsFixed(6)),
          _InfoChip('LON', position.longitude.toStringAsFixed(6)),
          _InfoChip('ALT', UnitFormatter.altitude(position.altitude, units)),
          _InfoChip('SPD', UnitFormatter.speed(position.speedKmh, units)),
          _InfoChip('ACC', '${position.accuracy.toStringAsFixed(0)}m'),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: t.textDim,
            fontSize: 8,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
