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
  final List<Detection> _detections = [];
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
      setState(() => _detections.add(d));
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
        _routePoints.add(ll);
      });
      if (_followUser) {
        _mapController.move(ll, _mapController.camera.zoom);
      }
    });
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              backgroundColor: const Color(0xFF0A0A0A),
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) _followUser = false;
              },
            ),
            children: [
              // Dark tile layer (CartoDB dark matter)
              TileLayer(
                urlTemplate:
                    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
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
              // Detection markers
              MarkerLayer(
                markers: _detections
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
                backgroundColor: AppTheme.surface,
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
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Text(
                '${_detections.length} detections',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
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

class _GpsInfoBar extends StatelessWidget {
  const _GpsInfoBar({required this.position});
  final GpsPosition position;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.92),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _InfoChip('LAT', position.latitude.toStringAsFixed(6)),
          _InfoChip('LON', position.longitude.toStringAsFixed(6)),
          _InfoChip('ALT', '${position.altitude.toStringAsFixed(0)}m'),
          _InfoChip('SPD', '${position.speedKmh.toStringAsFixed(0)}km/h'),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 8,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
