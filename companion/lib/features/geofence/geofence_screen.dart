import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:drift/drift.dart' as drift;
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/geofence/geofence_filter.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:uuid/uuid.dart';

/// Geofence creation, editing and management screen.
/// Supports circle (tap center + drag radius) and polygon (tap vertices) zones.
class GeofenceScreen extends ConsumerStatefulWidget {
  const GeofenceScreen({super.key});

  @override
  ConsumerState<GeofenceScreen> createState() => _GeofenceScreenState();
}

enum _DrawMode { none, circle, polygon }

class _GeofenceScreenState extends ConsumerState<GeofenceScreen> {
  final _mapController = MapController();
  _DrawMode _mode = _DrawMode.none;
  String _name = '';

  // Circle state
  LatLng? _circleCenter;
  double _circleRadiusM = 200;

  // Polygon state
  final List<LatLng> _polyPoints = [];

  // Existing geofences
  List<Geofence> _geofences = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadGeofences();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadGeofences() async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.geofences)
          ..orderBy([(g) => drift.OrderingTerm.desc(g.createdAt)]))
        .get();
    if (mounted) setState(() { _geofences = rows; _loaded = true; });
  }

  void _startCircle() {
    setState(() {
      _mode = _DrawMode.circle;
      _circleCenter = null;
      _circleRadiusM = 200;
      _polyPoints.clear();
    });
  }

  void _startPolygon() {
    setState(() {
      _mode = _DrawMode.polygon;
      _circleCenter = null;
      _polyPoints.clear();
    });
  }

  void _cancelDraw() {
    setState(() {
      _mode = _DrawMode.none;
      _circleCenter = null;
      _polyPoints.clear();
    });
  }

  void _onMapTap(TapPosition tapPos, LatLng point) {
    if (_mode == _DrawMode.circle && _circleCenter == null) {
      setState(() => _circleCenter = point);
    } else if (_mode == _DrawMode.polygon) {
      setState(() => _polyPoints.add(point));
    }
  }

  void _undoLastPoint() {
    if (_polyPoints.isNotEmpty) {
      setState(() => _polyPoints.removeLast());
    }
  }

  Future<void> _saveZone() async {
    final name = _name.trim().isEmpty ? 'Zone ${_geofences.length + 1}' : _name.trim();
    final db = ref.read(databaseProvider);
    final id = const Uuid().v4();

    if (_mode == _DrawMode.circle && _circleCenter != null) {
      await db.upsertGeofence(GeofencesCompanion(
        id: drift.Value(id),
        name: drift.Value(name),
        zoneType: const drift.Value('circle'),
        centerLat: drift.Value(_circleCenter!.latitude),
        centerLon: drift.Value(_circleCenter!.longitude),
        radiusM: drift.Value(_circleRadiusM),
        excludeFromWardrive: const drift.Value(true),
        enabled: const drift.Value(true),
        createdAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
      ));
    } else if (_mode == _DrawMode.polygon && _polyPoints.length >= 3) {
      final json = jsonEncode(
        _polyPoints.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      );
      // Compute centroid for display
      final cLat = _polyPoints.map((p) => p.latitude).reduce((a, b) => a + b) / _polyPoints.length;
      final cLon = _polyPoints.map((p) => p.longitude).reduce((a, b) => a + b) / _polyPoints.length;
      await db.upsertGeofence(GeofencesCompanion(
        id: drift.Value(id),
        name: drift.Value(name),
        zoneType: const drift.Value('polygon'),
        centerLat: drift.Value(cLat),
        centerLon: drift.Value(cLon),
        polygonJson: drift.Value(json),
        excludeFromWardrive: const drift.Value(true),
        enabled: const drift.Value(true),
        createdAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
      ));
    } else {
      return;
    }

    _cancelDraw();
    _name = '';
    await _loadGeofences();
    ref.read(geofenceFilterProvider).reload();
    HapticFeedback.mediumImpact();
  }

  Future<void> _toggleGeofence(Geofence g) async {
    final db = ref.read(databaseProvider);
    await db.upsertGeofence(GeofencesCompanion(
      id: drift.Value(g.id),
      name: drift.Value(g.name),
      zoneType: drift.Value(g.zoneType),
      centerLat: drift.Value(g.centerLat),
      centerLon: drift.Value(g.centerLon),
      radiusM: drift.Value(g.radiusM),
      polygonJson: drift.Value(g.polygonJson),
      corridorJson: drift.Value(g.corridorJson),
      excludeFromWardrive: drift.Value(g.excludeFromWardrive),
      enabled: drift.Value(!g.enabled),
      createdAt: drift.Value(g.createdAt),
    ));
    await _loadGeofences();
    ref.read(geofenceFilterProvider).reload();
  }

  Future<void> _deleteGeofence(Geofence g) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.geofences)..where((t) => t.id.equals(g.id))).go();
    await _loadGeofences();
    ref.read(geofenceFilterProvider).reload();
  }

  bool get _canSave {
    if (_mode == _DrawMode.circle) return _circleCenter != null;
    if (_mode == _DrawMode.polygon) return _polyPoints.length >= 3;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final mapStyle = ref.watch(mapStyleProvider);
    final gps = ref.read(gpsProvider).lastPosition;
    final center = gps != null
        ? LatLng(gps.latitude, gps.longitude)
        : const LatLng(38.627, -90.199);

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
                backgroundColor: mapStyle.isDark
                    ? const Color(0xFF0A0A0A)
                    : const Color(0xFFE8E8EE),
                onTap: _mode != _DrawMode.none ? _onMapTap : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: mapStyle.urlTemplate,
                  userAgentPackageName: 'tech.colonelpanic.ouispy',
                  maxZoom: 19,
                ),
                // Existing geofences
                ..._existingZoneLayers(t),
                // Drawing preview
                ..._drawingPreviewLayers(t),
              ],
            ),

            // Top bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.background.withValues(alpha: 0.92),
                  border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, size: 20, color: t.textPrimary),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.fence, size: 16, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Text('GEOFENCE EXCLUSION', style: TextStyle(
                      color: t.textPrimary, fontSize: 13,
                      fontWeight: FontWeight.w700, letterSpacing: 1,
                    )),
                    const Spacer(),
                    if (_geofences.isNotEmpty)
                      Text('${_geofences.where((g) => g.enabled).length} active',
                        style: TextStyle(
                          color: AppTheme.warning, fontSize: 10,
                          fontFamily: 'monospace', fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Drawing mode controls
            if (_mode != _DrawMode.none)
              Positioned(
                top: 52, left: 0, right: 0,
                child: _DrawingToolbar(
                  mode: _mode,
                  canSave: _canSave,
                  polyPointCount: _polyPoints.length,
                  circleRadiusM: _circleRadiusM,
                  hasCircleCenter: _circleCenter != null,
                  nameController: _name,
                  onNameChanged: (v) => setState(() => _name = v),
                  onRadiusChanged: (v) => setState(() => _circleRadiusM = v),
                  onUndo: _undoLastPoint,
                  onCancel: _cancelDraw,
                  onSave: _saveZone,
                ),
              ),

            // Bottom: draw buttons or zone list
            if (_mode == _DrawMode.none)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _BottomPanel(
                  geofences: _geofences,
                  loaded: _loaded,
                  onStartCircle: _startCircle,
                  onStartPolygon: _startPolygon,
                  onToggle: _toggleGeofence,
                  onDelete: _deleteGeofence,
                  onZoom: (g) {
                    if (g.centerLat != null && g.centerLon != null) {
                      _mapController.move(
                        LatLng(g.centerLat!, g.centerLon!),
                        g.zoneType == 'circle' ? 16 : 15,
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _existingZoneLayers(ResolvedTheme t) {
    final circles = <CircleMarker>[];
    final polygons = <Polygon>[];

    for (final g in _geofences) {
      final color = g.enabled
          ? AppTheme.warning.withValues(alpha: 0.3)
          : AppTheme.textDim.withValues(alpha: 0.15);
      final borderColor = g.enabled
          ? AppTheme.warning.withValues(alpha: 0.7)
          : AppTheme.textDim.withValues(alpha: 0.3);

      if (g.zoneType == 'circle' && g.centerLat != null && g.centerLon != null) {
        circles.add(CircleMarker(
          point: LatLng(g.centerLat!, g.centerLon!),
          radius: g.radiusM ?? 200,
          useRadiusInMeter: true,
          color: color,
          borderColor: borderColor,
          borderStrokeWidth: 2,
        ));
      } else if (g.zoneType == 'polygon' && g.polygonJson != null) {
        try {
          final pts = (jsonDecode(g.polygonJson!) as List)
              .cast<Map<String, dynamic>>()
              .map((p) => LatLng(
                    (p['lat'] as num).toDouble(),
                    (p['lon'] as num).toDouble(),
                  ))
              .toList();
          polygons.add(Polygon(
            points: pts,
            color: color,
            borderColor: borderColor,
            borderStrokeWidth: 2,

          ));
        } catch (_) {}
      }
    }

    return [
      if (circles.isNotEmpty) CircleLayer(circles: circles),
      if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
    ];
  }

  List<Widget> _drawingPreviewLayers(ResolvedTheme t) {
    final layers = <Widget>[];

    if (_mode == _DrawMode.circle && _circleCenter != null) {
      layers.add(CircleLayer(circles: [
        CircleMarker(
          point: _circleCenter!,
          radius: _circleRadiusM,
          useRadiusInMeter: true,
          color: AppTheme.accent.withValues(alpha: 0.2),
          borderColor: AppTheme.accent.withValues(alpha: 0.8),
          borderStrokeWidth: 2,
        ),
      ]));
      layers.add(MarkerLayer(markers: [
        Marker(
          point: _circleCenter!,
          width: 12, height: 12,
          child: Container(decoration: BoxDecoration(
            color: AppTheme.accent, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          )),
        ),
      ]));
    }

    if (_mode == _DrawMode.polygon && _polyPoints.isNotEmpty) {
      if (_polyPoints.length >= 3) {
        layers.add(PolygonLayer(polygons: [
          Polygon(
            points: _polyPoints,
            color: AppTheme.accent.withValues(alpha: 0.2),
            borderColor: AppTheme.accent.withValues(alpha: 0.8),
            borderStrokeWidth: 2,

          ),
        ]));
      } else if (_polyPoints.length == 2) {
        layers.add(PolylineLayer(polylines: [
          Polyline(
            points: _polyPoints,
            color: AppTheme.accent.withValues(alpha: 0.6),
            strokeWidth: 2,
          ),
        ]));
      }
      layers.add(MarkerLayer(
        markers: _polyPoints.asMap().entries.map((e) {
          final isFirst = e.key == 0;
          return Marker(
            point: e.value,
            width: isFirst ? 14 : 10,
            height: isFirst ? 14 : 10,
            child: Container(decoration: BoxDecoration(
              color: isFirst ? AppTheme.success : AppTheme.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            )),
          );
        }).toList(),
      ));
    }

    return layers;
  }
}

class _DrawingToolbar extends StatelessWidget {
  const _DrawingToolbar({
    required this.mode,
    required this.canSave,
    required this.polyPointCount,
    required this.circleRadiusM,
    required this.hasCircleCenter,
    required this.nameController,
    required this.onNameChanged,
    required this.onRadiusChanged,
    required this.onUndo,
    required this.onCancel,
    required this.onSave,
  });

  final _DrawMode mode;
  final bool canSave;
  final int polyPointCount;
  final double circleRadiusM;
  final bool hasCircleCenter;
  final String nameController;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onUndo;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isCircle = mode == _DrawMode.circle;
    final hint = isCircle
        ? (hasCircleCenter ? 'Adjust radius, then save' : 'Tap map to set center')
        : 'Tap map to add vertices ($polyPointCount pts)';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode indicator + hint
          Row(
            children: [
              Icon(
                isCircle ? Icons.circle_outlined : Icons.pentagon_outlined,
                size: 14, color: AppTheme.accent,
              ),
              const SizedBox(width: 6),
              Text(
                isCircle ? 'CIRCLE' : 'POLYGON',
                style: const TextStyle(
                  color: AppTheme.accent, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(hint, style: TextStyle(
                  color: t.textDim, fontSize: 10,
                )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Name field
          SizedBox(
            height: 32,
            child: TextField(
              onChanged: onNameChanged,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Zone name (optional)',
                hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.accent),
                ),
              ),
            ),
          ),
          // Circle radius slider
          if (isCircle && hasCircleCenter) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('RADIUS', style: TextStyle(
                  color: t.textDim, fontSize: 8,
                  fontWeight: FontWeight.w600, letterSpacing: 1,
                )),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay),
                    child: Slider(
                      value: circleRadiusM,
                      min: 50, max: 5000,
                      activeColor: AppTheme.accent,
                      inactiveColor: t.border,
                      onChanged: onRadiusChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    circleRadiusM >= 1000
                        ? '${(circleRadiusM / 1000).toStringAsFixed(1)}km'
                        : '${circleRadiusM.round()}m',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.accent, fontSize: 10,
                      fontFamily: 'monospace', fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // Action buttons
          Row(
            children: [
              if (!isCircle && polyPointCount > 0)
                _SmallBtn(label: 'UNDO', color: AppTheme.warning, onTap: onUndo),
              const Spacer(),
              _SmallBtn(label: 'CANCEL', color: AppTheme.error, onTap: onCancel),
              const SizedBox(width: 8),
              _SmallBtn(
                label: 'SAVE',
                color: canSave ? AppTheme.success : AppTheme.textDim,
                onTap: canSave ? onSave : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.label, required this.color, this.onTap});
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onTap != null ? 0.15 : 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: onTap != null ? 0.5 : 0.15)),
        ),
        child: Text(label, style: TextStyle(
          color: color.withValues(alpha: onTap != null ? 1.0 : 0.4),
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5,
        )),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.geofences,
    required this.loaded,
    required this.onStartCircle,
    required this.onStartPolygon,
    required this.onToggle,
    required this.onDelete,
    required this.onZoom,
  });

  final List<Geofence> geofences;
  final bool loaded;
  final VoidCallback onStartCircle;
  final VoidCallback onStartPolygon;
  final void Function(Geofence) onToggle;
  final void Function(Geofence) onDelete;
  final void Function(Geofence) onZoom;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // Draw buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DrawBtn(
                icon: Icons.circle_outlined,
                label: 'CIRCLE',
                onTap: onStartCircle,
              ),
              const SizedBox(width: 12),
              _DrawBtn(
                icon: Icons.pentagon_outlined,
                label: 'POLYGON',
                onTap: onStartPolygon,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loaded && geofences.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No exclusion zones.\nNetworks inside zones are hidden from wardrive output.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textDim, fontSize: 11),
              ),
            )
          else if (geofences.isNotEmpty)
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shrinkWrap: true,
                itemCount: geofences.length,
                itemBuilder: (_, i) => _GeofenceRow(
                  geofence: geofences[i],
                  onToggle: () => onToggle(geofences[i]),
                  onDelete: () => onDelete(geofences[i]),
                  onZoom: () => onZoom(geofences[i]),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DrawBtn extends StatelessWidget {
  const _DrawBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(
              color: AppTheme.accent, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
          ],
        ),
      ),
    );
  }
}

class _GeofenceRow extends StatelessWidget {
  const _GeofenceRow({
    required this.geofence,
    required this.onToggle,
    required this.onDelete,
    required this.onZoom,
  });

  final Geofence geofence;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final g = geofence;
    final enabled = g.enabled;
    final icon = g.zoneType == 'circle' ? Icons.circle_outlined : Icons.pentagon_outlined;
    final subtitle = g.zoneType == 'circle'
        ? '${(g.radiusM ?? 0).round()}m radius'
        : 'polygon';

    return GestureDetector(
      onTap: onZoom,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: enabled
              ? AppTheme.warning.withValues(alpha: 0.06)
              : t.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled
                ? AppTheme.warning.withValues(alpha: 0.25)
                : t.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14,
                color: enabled ? AppTheme.warning : t.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name, style: TextStyle(
                    color: enabled ? t.textPrimary : t.textDim,
                    fontSize: 11, fontWeight: FontWeight.w600,
                  )),
                  Text(subtitle, style: TextStyle(
                    color: t.textDim, fontSize: 9,
                  )),
                ],
              ),
            ),
            // Toggle
            GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: enabled
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  enabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: enabled ? AppTheme.success : AppTheme.error,
                    fontSize: 9, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Delete
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.delete_outline, size: 16,
                  color: AppTheme.error.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
