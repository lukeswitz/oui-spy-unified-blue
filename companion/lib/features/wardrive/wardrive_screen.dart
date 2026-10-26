import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/watchlist_state.dart';

import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_provider.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/wardrive/drone_markers.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';
import 'package:oui_spy/features/geofence/geofence_screen.dart';
import 'package:oui_spy/features/wardrive/flock_panel.dart';
import 'package:oui_spy/features/wardrive/wardrive_stats.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/deflock/deflock_api.dart';
import 'package:oui_spy/core/deflock/deflock_provider.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart';
import 'package:share_plus/share_plus.dart';

part 'wardrive_controls.dart';
part 'wardrive_sessions.dart';
part 'wardrive_overlays.dart';
part 'wardrive_popups.dart';

class WardriveScreen extends ConsumerStatefulWidget {
  const WardriveScreen({super.key});

  @override
  ConsumerState<WardriveScreen> createState() => _WardriveScreenState();
}

class _WardriveScreenState extends ConsumerState<WardriveScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  bool _followMode = true;
  int _lastSessionLoadEpoch = 0;
  bool _initialFitDone = false;
  bool _idleCenteredDone = false;
  bool _feedCollapsed = false;
  final _statsKey = GlobalKey();
  double _statsHeight = 0;
  final _completedBarKey = GlobalKey();
  double _completedBarHeight = 0;
  final _chipsKey = GlobalKey();
  double _chipsHeight = 0;
  double _currentZoom = 15;
  double _currentRotation = 0;
  double _povHeading = double.nan;
  _DetectionLayers? _cachedLayers;
  Detection? _focusedDetection;
  List<Detection> _classGroup = const [];
  String _classGroupLabel = '';
  String _cachedLayersKey = '';
  List<Geofence> _exclusionZones = [];
  bool _reconnectPromptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadExclusionZones();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _primeLocationPermission();
      if (ok && mounted) ref.read(gpsProvider).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DebugLog.log('WardriveScreen: resumed, priming permissions');
      _primeLocationPermission().then((success) {
        if (!mounted) return;
        DebugLog.log('WardriveScreen: prime permission success=$success');
        if (success && ref.read(wardriveProvider).isActive) {
          DebugLog.log('WardriveScreen: session active, restarting GPS');
          ref.read(gpsProvider).start();
        }
      });
    }
  }

  Future<bool> _primeLocationPermission() => primeLocationPermission(context);

  Future<void> _showReconnectPrompt(WardriveController wd) async {
    final t = AppTheme.of(context);
    final cont = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Connection Restored',
          style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'The node reconnected during a wardrive. Continue the session?',
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('STOP & SAVE', style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('CONTINUE', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    _reconnectPromptOpen = false;
    if (!mounted) return;
    if (cont == true) {
      await wd.continueAfterReconnect();
    } else {
      await wd.stopAfterReconnect();
    }
  }

  void _onMapReady() {
    if (_initialFitDone) return;
    final wd = ref.read(wardriveProvider);
    if (!wd.hasSessionData) return;
    _initialFitDone = true;
    setState(() => _followMode = false);
    _fitToSessionBounds(wd, includeCurrentPosition: true);
  }

  Future<void> _loadExclusionZones() async {
    final db = ref.read(databaseProvider);
    final zones = await db.getWardriveExclusionGeofences();
    if (mounted) setState(() => _exclusionZones = zones);
  }

  void _fitToSessionBounds(WardriveController wd, {bool includeCurrentPosition = false}) {
    final points = <LatLng>[
      ...wd.routePoints.where((p) => p.latitude.isFinite && p.longitude.isFinite),
      ...wd.dedupedDetections
          .where((d) => _hasMapCoord(d.latitude, d.longitude))
          .where((d) => wd.isWithinSession(d.latitude!, d.longitude!))
          .map((d) => LatLng(d.latitude!, d.longitude!)),
    ];

    if (includeCurrentPosition) {
      final pos = wd.currentPosition ?? ref.read(gpsProvider).lastPosition;
      if (pos != null && pos.latitude.isFinite && pos.longitude.isFinite) {
        points.add(LatLng(pos.latitude, pos.longitude));
      }
    }

    _fitToPoints(points);
  }

  void _fitToPoints(List<LatLng> points) {
    if (points.length < 2) {
      if (points.length == 1) {
        _mapController.move(points.first, 16);
      }
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLon = points.first.longitude;
    var maxLon = points.first.longitude;

    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }

    if (!minLat.isFinite || !maxLat.isFinite ||
        !minLon.isFinite || !maxLon.isFinite) {
      return;
    }

    // Min span guard for start≈stop GPS jitter (prevents snap to max zoom).
    const minHalfSpanM = 75.0;
    final refLat = (minLat + maxLat) / 2.0;
    final cosLat = math.max(0.1, math.cos(refLat * math.pi / 180.0));
    final minHalfLat = minHalfSpanM / 111320.0;
    final minHalfLon = minHalfSpanM / (111320.0 * cosLat);
    if ((maxLat - minLat) < minHalfLat * 2) {
      minLat = refLat - minHalfLat;
      maxLat = refLat + minHalfLat;
    }
    if ((maxLon - minLon) < minHalfLon * 2) {
      final refLon = (minLon + maxLon) / 2.0;
      minLon = refLon - minHalfLon;
      maxLon = refLon + minHalfLon;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLon),
          LatLng(maxLat, maxLon),
        ),
        padding: const EdgeInsets.all(48),
        maxZoom: 17.0,
      ),
    );


    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final z = _mapController.camera.zoom;
      if ((z - _currentZoom).abs() > 0.05) {
        setState(() => _currentZoom = z);
      }
    });
  }

  void _zoomToDetection(Detection d) {
    if (!_hasMapCoord(d.latitude, d.longitude)) return;
    setState(() {
      _focusedDetection = d;
      _followMode = false;
    });
    _mapController.move(LatLng(d.latitude!, d.longitude!), 18);
  }

  void _clearFocusedDetection() {
    if (_focusedDetection == null) return;
    setState(() => _focusedDetection = null);
  }

  static String _classLabelOf(Detection d) {
    final cls = detectionAlertClass[d];
    if (cls == null) return d.engine.label;
    for (final c in SignatureClass.values) {
      if (c.name == cls) return c.label;
    }
    return cls;
  }

  Future<void> _showAllOfClass() async {
    final f = _focusedDetection;
    if (f == null) return;
    final cls = detectionAlertClass[f];
    final List<Detection> group;
    if (cls != null) {
      final rows = await ref.read(databaseProvider).getClassAlertMaps();
      group = [
        for (final r in rows)
          if (r['alertClass'] == cls) detectionFromDbRow(r),
      ];
    } else {
      final seen = <String>{};
      group = [
        for (final d in [
          ...ref.read(wardriveProvider).dedupedDetections,
          ...ref.read(appStateProvider).recentDetections,
        ])
          if (d.engine == f.engine && seen.add(d.macAddress)) d,
      ];
    }
    final geo = group.where((d) => _hasMapCoord(d.latitude, d.longitude)).toList();
    if (!mounted) return;
    setState(() {
      _focusedDetection = null;
      _classGroup = geo;
      _classGroupLabel = _classLabelOf(f);
      _followMode = false;
    });
    _fitToPoints([for (final d in geo) LatLng(d.latitude!, d.longitude!)]);
  }

  void _clearClassGroup() {
    if (_classGroup.isEmpty && _classGroupLabel.isEmpty) return;
    setState(() {
      _classGroup = const [];
      _classGroupLabel = '';
    });
  }

  static bool _hasMapCoord(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    if (!lat.isFinite || !lon.isFinite) return false;
    if (lat == 0.0 && lon == 0.0) return false;
    if (lat.abs() > 89.5) return false; // pole-locked glitch
    return true;
  }


  static const double _povMoveOnThreshold = 0.3; // m/s — engage rotate
  static const double _povMoveOffThreshold = 0.1; // m/s — disengage (hysteresis)

  void _focusMap(WardriveController wd) {
    final pos = wd.currentPosition ?? ref.read(gpsProvider).lastPosition;
    if (pos == null) return;
    if (!_followMode) setState(() => _followMode = true);
    final here = LatLng(pos.latitude, pos.longitude);
    if (wd.isActive && pos.speed > _povMoveOnThreshold && pos.heading.isFinite) {
      _povHeading = pos.heading;
      _applyFollowCamera(here, pos.heading);
    } else if (!_povHeading.isNaN) {
      _applyFollowCamera(here, _povHeading);
    } else {
      _mapController.move(here, _mapController.camera.zoom);
    }
  }

  void _applyFollowCamera(LatLng here, double headingDeg) {
    final cam = _mapController.camera;
    final size = cam.nonRotatedSize;
    DebugLog.log('FollowCam: heading=${headingDeg.toStringAsFixed(1)} '
        'size=${size.x.toInt()}x${size.y.toInt()} zoom=${cam.zoom.toStringAsFixed(2)} '
        'curRot=${cam.rotation.toStringAsFixed(1)}');
    if (size.x <= 0 || size.y <= 0) {
      _mapController.moveAndRotate(here, cam.zoom, -headingDeg);
      return;
    }
    final mpp = _metersPerPixel(here.latitude, cam.zoom);
    final aheadMeters = mpp * size.y * 0.25;
    final ahead = const Distance().offset(here, aheadMeters, headingDeg);
    _mapController.moveAndRotate(ahead, cam.zoom, -headingDeg);
  }

  List<Widget> _exclusionZoneLayers() {
    if (_exclusionZones.isEmpty) return [];
    final circles = <CircleMarker>[];
    final polygons = <Polygon>[];
    final zoneColor = AppTheme.warning.withValues(alpha: 0.19);
    final zoneBorder = AppTheme.warning.withValues(alpha: 0.6);

    for (final g in _exclusionZones) {
      if (g.zoneType == 'circle' && g.centerLat != null && g.centerLon != null) {
        circles.add(CircleMarker(
          point: LatLng(g.centerLat!, g.centerLon!),
          radius: g.radiusM ?? 200,
          useRadiusInMeter: true,
          color: zoneColor,
          borderColor: zoneBorder,
          borderStrokeWidth: 1.5,
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
            color: zoneColor,
            borderColor: zoneBorder,
            borderStrokeWidth: 1.5,
          ));
        } catch (_) {}
      }
    }

    return [
      if (circles.isNotEmpty) CircleLayer(circles: circles),
      if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
    ];
  }

  GeoBounds? _visibleGeoBounds() {
    try {
      final v = _mapController.camera.visibleBounds;
      return GeoBounds(
        south: v.south,
        west: v.west,
        north: v.north,
        east: v.east,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mapped ALPRs (OSM / DeFlock), culled to the visible viewport.
  List<Widget> _alprLayers(DeflockProvider df) {
    if (!df.showAlpr) return const [];
    final view = _visibleGeoBounds();
    if (view == null) return const [];
    final nodes = df.nodesIn(view);
    if (nodes.isEmpty) return const [];
    return [
      MarkerLayer(
        markers: [
          for (final n in nodes)
            Marker(
              point: n.position,
              width: 22,
              height: 22,
              child: Tooltip(
                message: n.label,
                child: Icon(
                  Icons.videocam_outlined,
                  size: 18,
                  color: n.isFlock ? AppTheme.flockWifi : AppTheme.textDim,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  void _refreshAlprForView() {
    final df = ref.read(deflockProvider);
    if (!df.showAlpr) return;
    final view = _visibleGeoBounds();
    if (view == null) return;
    final messenger = ScaffoldMessenger.of(context);
    df.ensureBounds(view).then((_) {
      final err = df.error;
      if (err == null || !mounted) return;
      df.clearError();
      messenger.showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: AppTheme.warning,
        duration: const Duration(seconds: 3),
      ));
    });
  }

  /// WDGWars gang territory hulls, culled to the visible viewport.
  List<Widget> _territoryLayers(WdgwarsProvider wdg) {
    if (!wdg.showTerritories) return const [];
    if (wdg.territories.isEmpty) {
      if (!wdg.territoriesLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(wdgwarsProvider).loadTerritories();
        });
      }
      return const [];
    }

    LatLngBounds? view;
    try {
      view = _mapController.camera.visibleBounds;
    } catch (_) {
      view = null;
    }

    final polygons = <Polygon>[];
    for (final t in wdg.territories) {
      final b = t.bounds;
      if (view != null &&
          (b.minLat > view.north ||
              b.maxLat < view.south ||
              b.minLon > view.east ||
              b.maxLon < view.west)) {
        continue;
      }
      polygons.add(Polygon(
        points: t.hull,
        color: t.color.withValues(alpha: 0.13),
        borderColor: t.color.withValues(alpha: 0.75),
        borderStrokeWidth: 1.4,
        label: t.name.isEmpty ? null : t.name,
        labelStyle: TextStyle(
          color: t.color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ));
    }
    if (polygons.isEmpty) return const [];
    return [PolygonLayer(polygons: polygons)];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final mapStyle = ref.watch(mapStyleProvider);
    final wd = ref.watch(wardriveProvider);
    if (wd.pendingReconnectPrompt && !_reconnectPromptOpen) {
      _reconnectPromptOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && wd.pendingReconnectPrompt) {
          _showReconnectPrompt(wd);
        } else {
          _reconnectPromptOpen = false;
        }
      });
    }
    final appEngines = ref.watch(appStateProvider);
    final gpsPos = ref.watch(gpsProvider).lastPosition;
    final selfPos = wd.currentPosition ?? gpsPos;
    final center = wd.currentPosition != null
        ? LatLng(wd.currentPosition!.latitude, wd.currentPosition!.longitude)
        : gpsPos != null
            ? LatLng(gpsPos.latitude, gpsPos.longitude)
            : const LatLng(38.627, -90.199);

    // Fit to session bounds when a saved session is loaded
    final loadedId = wd.loadedSessionId;
    if (loadedId != null &&
        wd.sessionLoadEpoch != _lastSessionLoadEpoch &&
        wd.hasSessionData) {
      _lastSessionLoadEpoch = wd.sessionLoadEpoch;
      _focusedDetection = null;
      _classGroup = const [];
      _classGroupLabel = '';
      _followMode = false;
      _initialFitDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitToSessionBounds(wd);
      });
    }

    if (!wd.isActive &&
        loadedId == null &&
        !_idleCenteredDone &&
        selfPos != null) {
      _idleCenteredDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(LatLng(selfPos.latitude, selfPos.longitude), 15);
      });
    }
    if (wd.isActive) _idleCenteredDone = false;

    // Consume pending zoom target from cross-tab navigation
    if (wd.pendingZoomTarget != null) {
      final zoom = wd.consumeZoomTarget()!;
      final focus = wd.consumeZoomDetection();
      _followMode = false;
      _focusedDetection = focus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(zoom, 18);
      });
    }

    final gpsPos2 = wd.currentPosition ?? gpsPos;
    final povActive = gpsPos2 != null && wd.isActive && _followMode;
    if (povActive) {
      final here = LatLng(gpsPos2.latitude, gpsPos2.longitude);
      final speed = gpsPos2.speed;
      final headingValid = gpsPos2.heading.isFinite;
      final wasFollowing = !_povHeading.isNaN;
      // Hysteresis: engage at >0.3 m/s, disengage at <0.1 m/s.
      final engaged = headingValid &&
          (speed > _povMoveOnThreshold ||
              (wasFollowing && speed > _povMoveOffThreshold));
      if (engaged) {
        final delta = _shortAngleDelta(
          _povHeading.isNaN ? 0 : _povHeading,
          gpsPos2.heading,
        );
        if (_povHeading.isNaN || delta.abs() > 2.0) {
          _povHeading = gpsPos2.heading;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!(wd.isActive && _followMode)) return;
          _applyFollowCamera(here, _povHeading);
        });
      } else if (wasFollowing) {
        // Stopped but had a heading — hold last heading, recenter.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!(wd.isActive && _followMode)) return;
          _applyFollowCamera(here, _povHeading);
        });
      } else if (_followMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_followMode) return;
          _mapController.move(here, _mapController.camera.zoom);
        });
      }
    } else if (!_povHeading.isNaN) {
      _povHeading = double.nan;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.rotate(0);
      });
    }

    ref.watch(notificationServiceProvider.select((n) => n.classAlertedMacs.length));
    final detectionLayers = _buildDetectionLayers(wd);
    final darkBase = mapStyle.isDark;

    final mapWidget = FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                backgroundColor: mapStyle.isDark ? Colors.black : Colors.white,
                onMapReady: _onMapReady,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onMapEvent: (event) {
                  const userSources = {
                    MapEventSource.dragStart,
                    MapEventSource.onDrag,
                    MapEventSource.dragEnd,
                    MapEventSource.multiFingerGestureStart,
                    MapEventSource.onMultiFinger,
                    MapEventSource.multiFingerEnd,
                    MapEventSource.scrollWheel,
                    MapEventSource.doubleTap,
                    MapEventSource.doubleTapHold,
                    MapEventSource.doubleTapZoomAnimationController,
                    MapEventSource.flingAnimationController,
                  };
                  if (userSources.contains(event.source)) {
                    if (_followMode) setState(() => _followMode = false);
                  }
                  if (event is MapEventMove ||
                      event is MapEventMoveEnd ||
                      event is MapEventDoubleTapZoom ||
                      event is MapEventDoubleTapZoomEnd ||
                      event is MapEventFlingAnimation ||
                      event is MapEventFlingAnimationEnd ||
                      event is MapEventScrollWheelZoom ||
                      event is MapEventNonRotatedSizeChange) {
                    final z = _mapController.camera.zoom;
                    if ((z - _currentZoom).abs() > 0.05) {
                      setState(() => _currentZoom = z);
                    }
                  }
                  if (event is MapEventMoveEnd ||
                      event is MapEventFlingAnimationEnd ||
                      event is MapEventDoubleTapZoomEnd ||
                      event is MapEventScrollWheelZoom) {
                    _refreshAlprForView();
                  }
                  if (event is MapEventRotate || event is MapEventRotateEnd) {
                    final r = _mapController.camera.rotation;
                    if ((r - _currentRotation).abs() > 0.5) {
                      setState(() => _currentRotation = r);
                    }
                  }
                },
              ),
              children: [
                mapTileLayer(mapStyle),
                ..._territoryLayers(ref.watch(wdgwarsProvider)),
                ..._alprLayers(ref.watch(deflockProvider)),
                if (detectionLayers.heat.isNotEmpty)
                  CircleLayer(circles: detectionLayers.heat),
                ..._exclusionZoneLayers(),
                if (wd.routePoints.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: wd.routePoints,
                      color: Colors.white.withValues(alpha: 0.85),
                      strokeWidth: 2.4,
                      borderColor: darkBase
                          ? Colors.black.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.45),
                      borderStrokeWidth: 1.0,
                    ),
                  ]),
                if (detectionLayers.rings.isNotEmpty)
                  CircleLayer(circles: detectionLayers.rings),
                if (detectionLayers.trails.isNotEmpty)
                  PolylineLayer(polylines: detectionLayers.trails),
                if (detectionLayers.tethers.isNotEmpty)
                  PolylineLayer(polylines: detectionLayers.tethers),
                if (_currentZoom < 16.0) ...[
                  if (detectionLayers.pins.isNotEmpty)
                    MarkerLayer(markers: detectionLayers.pins),
                  if (detectionLayers.clusters.isNotEmpty)
                    MarkerLayer(markers: detectionLayers.clusters),
                ] else ...[
                  if (detectionLayers.clusters.isNotEmpty)
                    MarkerLayer(markers: detectionLayers.clusters),
                  if (detectionLayers.pins.isNotEmpty)
                    MarkerLayer(markers: detectionLayers.pins),
                ],
                if (selfPos != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(selfPos.latitude, selfPos.longitude),
                      width: 16,
                      height: 16,
                      child: const _CurrentPosMarker(),
                    ),
                  ]),
              ],
            );

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Builder(builder: (context) {
          final pills = [
            for (final m in WardriveController.selectableTargets)
              if (m != WardriveTarget.wigle &&
                  ((wd.isActive && wd.isTargetSelected(m)) ||
                      targetEngineRunning(appEngines, m)))
                _ScanningPill(color: m.color, label: m.label),
          ];

          return Stack(children: [
            Positioned.fill(child: mapWidget),

            // Stats bar (top, only when active)
            if (wd.isActive)
              Positioned(
                top: 0, left: 0, right: 0,
                child: _MeasuredBox(
                  statsKey: _statsKey,
                  onHeightChanged: (h) {
                    if ((_statsHeight - h).abs() > 1) {
                      setState(() => _statsHeight = h);
                    }
                  },
                  child: WardriveStats(stats: wd.currentStats),
                ),
              ),

            if (wd.radioTransition != null)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  color: t.background.withValues(alpha: 0.96),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        wd.radioTransition == 'stopping'
                            ? 'RADIO SHUTTING DOWN…'
                            : 'RADIO STARTING UP…',
                        style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: (wd.isActive
                      ? _statsHeight
                      : (wd.hasSessionData ? _completedBarHeight : 0)) +
                  8,
              left: 0, right: 0,
              child: _MeasuredBox(
                statsKey: _chipsKey,
                onHeightChanged: (h) {
                  if ((_chipsHeight - h).abs() > 1) {
                    setState(() => _chipsHeight = h);
                  }
                },
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      if (pills.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: pills,
                        ),
                      if (_focusedDetection != null)
                        _FocusedDetectionChip(
                          detection: _focusedDetection!,
                          classLabel: _classLabelOf(_focusedDetection!),
                          onShowAll: _showAllOfClass,
                          onClear: _clearFocusedDetection,
                        )
                      else if (_classGroup.isNotEmpty)
                        _ClassGroupChip(
                          label: _classGroupLabel,
                          count: _classGroup.length,
                          onClear: _clearClassGroup,
                        ),
                      if (wd.isActive && (wd.inExclusion || wd.geofenceSuppressed > 0))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: t.surface.withValues(alpha: 0.92),
                            border: Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.7)),
                          ),
                          child: Text(
                            wd.inExclusion
                                ? 'RADIOS OFF — INSIDE EXCLUSION ZONE'
                                : '${wd.geofenceSuppressed} HIDDEN — INSIDE EXCLUSION ZONE',
                            style: TextStyle(
                              color: AppTheme.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Map style + wardrive theme pickers (top-left)
            Positioned(
              top: wd.isActive
                  ? _statsHeight + 8
                  : (wd.hasSessionData ? _completedBarHeight + 8 : 8),
              left: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapStyleButton(
                    ref: ref,
                    mapStyle: mapStyle,
                    onAlprToggled: _refreshAlprForView,
                  ),
                  const SizedBox(width: 8),
                  _LayerLoadingPill(
                    alprLoading: ref.watch(deflockProvider).loading,
                    territoriesLoading:
                        ref.watch(wdgwarsProvider).territoriesLoading,
                  ),
                ],
              ),
            ),

            // Idle: completed session summary (if map data present)
            if (!wd.isActive && wd.hasSessionData)
              Positioned(
                top: 0, left: 0, right: 0,
                child: _MeasuredBox(
                  statsKey: _completedBarKey,
                  onHeightChanged: (h) {
                    if ((_completedBarHeight - h).abs() > 1) {
                      setState(() => _completedBarHeight = h);
                    }
                  },
                  child: _CompletedSessionBar(
                    wd: wd,
                    onZoomDetection: (d) => _zoomToDetection(d),
                  ),
                ),
              ),

            // Idle: mode selector + start
            if (!wd.isActive)
              Positioned(
                bottom: 24, left: 0, right: 0,
                child: _IdleControls(
                  wd: wd,
                  ref: ref,
                  onGeofenceReturn: _loadExclusionZones,
                ),
              ),

            // Active: focus button (top-right, below stats + chip rows)
            if (wd.isActive)
              Positioned(
                top: _statsHeight + 8 + _chipsHeight + 8,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _IconBtn(
                      icon: _followMode
                          ? Icons.my_location
                          : Icons.gps_not_fixed,
                      onTap: () => _focusMap(wd),
                      active: _followMode,
                      tooltip: _followMode
                          ? 'Following: map follows you and rotates with heading'
                          : 'Center on me + follow',
                    ),
                    if (_currentRotation.abs() > 0.5) ...[
                      const SizedBox(height: 6),
                      _CompassResetBtn(
                        rotation: _currentRotation,
                        onTap: () {
                          _mapController.rotate(0);
                          setState(() => _currentRotation = 0);
                        },
                      ),
                    ],
                    if (wd.includesFlock) ...[
                      const SizedBox(height: 6),
                      FlockPanel(
                        detections: wd.flockDetections,
                        onDetectionTap: (d) => _zoomToDetection(d),
                      ),
                    ],
                    if (wd.includesDrone) ...[
                      const SizedBox(height: 6),
                      FlockPanel(
                        detections: wd.droneDetections,
                        icon: Icons.flight,
                        accent: Engine.skySpy.color,
                        onDetectionTap: (d) => _zoomToDetection(d),
                      ),
                    ],
                    if (wd.includesDetector) ...[
                      const SizedBox(height: 6),
                      FlockPanel(
                        detections: wd.detectorDetections,
                        icon: Icons.radar,
                        accent: Engine.detector.color,
                        onDetectionTap: (d) => _zoomToDetection(d),
                      ),
                    ],
                    if (wd.foxhuntTarget != null) ...[
                      const SizedBox(height: 6),
                      _FoxhuntBadge(mac: wd.foxhuntTarget!),
                    ],
                  ],
                ),
              ),

            // Active: node stats overlay (top-left, below map style btn)
            if (wd.isActive &&
                ((ref.watch(appStateProvider).isManagerConnected && ref.watch(appStateProvider).meshEnabled) ||
                    ref.watch(phoneBleSourceProvider).scanning))
              Positioned(
                top: _statsHeight + 8 + math.max(40.0, _chipsHeight + 8),
                left: 12,
                child: _NodeStatsOverlay(ref: ref),
              ),

            // Active: pause/stop controls + flock panel below
            if (wd.isActive)
              Positioned(
                bottom: 16, left: 0, right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _runControls(ref, wd),
                    const SizedBox(height: 8),
                    if (wd.dedupedDetections.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: _FeedToggle(
                                count: wd.dedupedDetections.length,
                                collapsed: _feedCollapsed,
                                onTap: () => setState(
                                    () => _feedCollapsed = !_feedCollapsed),
                              ),
                            ),
                            if (!_feedCollapsed) ...[
                              const SizedBox(height: 4),
                              _DetectionList(
                                detections: wd.dedupedDetections,
                                onDetectionTap: (d) => _zoomToDetection(d),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            mapAttribution(mapStyle),
          ]);
        }),
      ),
    );
  }

  _DetectionLayers _buildDetectionLayers(WardriveController wd) {
    final recentLen = ref.read(appStateProvider).recentDetections.length;
    final focus = _focusedDetection;
    final alerted = ref.read(notificationServiceProvider).classAlertedMacs.length;
    final key = '$alerted|${wd.dedupedDetections.length}|$recentLen|${wd.flockFilter}|'
        '${wd.detectorFilter}|${_currentZoom.toStringAsFixed(1)}|${wd.sessionId}|'
        '${focus == null ? '' : '${focus.macAddress}|${focus.engine.name}'}|'
        '$_classGroupLabel|${_classGroup.length}';
    if (_cachedLayersKey == key && _cachedLayers != null) return _cachedLayers!;
    final layers = _computeDetectionLayers(wd);
    _cachedLayers = layers;
    _cachedLayersKey = key;
    return layers;
  }

  _DetectionLayers _computeDetectionLayers(WardriveController wd) {
    final appState = ref.read(appStateProvider);
    final alertedMacs = ref.read(notificationServiceProvider).classAlertedMacs;
    final alertKinds = ref.read(notificationServiceProvider).classAlertKinds;
    bool isAlerted(Detection d) => alertedMacs.contains(d.macAddress.toUpperCase());
    final source = <Detection>[...wd.dedupedDetections];
    final seenKeys = <String>{
      for (final d in source) '${d.macAddress}|${d.engine.name}',
    };
    for (final d in appState.recentDetections) {
      if (d.engine != Engine.skySpy &&
          d.engine != Engine.flockBle &&
          d.engine != Engine.flockWifi &&
          d.engine != Engine.detector) {
        continue;
      }
      if (!_hasMapCoord(d.latitude, d.longitude) &&
          droneRidPoint(d) == null) {
        continue;
      }
      if (seenKeys.add('${d.macAddress}|${d.engine.name}')) source.add(d);
    }
    final allGeo = source
        .where((d) =>
            _hasMapCoord(d.latitude, d.longitude) || droneRidPoint(d) != null)
        .where((d) => wd.isWithinSession(
            d.latitude ?? droneRidPoint(d)!.latitude,
            d.longitude ?? droneRidPoint(d)!.longitude))
        .toList();
    final focused = _focusedDetection;
    final filterActive = wd.flockFilter || wd.detectorFilter;
    final List<Detection> geoDetections;
    if (focused != null) {
      final hits = allGeo
          .where((d) =>
              d.macAddress == focused.macAddress && d.engine == focused.engine)
          .toList();
      // The feed can focus a detection this session's map never held.
      geoDetections = hits.isNotEmpty
          ? hits
          : (_hasMapCoord(focused.latitude, focused.longitude)
              ? [focused]
              : const <Detection>[]);
    } else if (_classGroup.isNotEmpty) {
      geoDetections = _classGroup;
    } else if (filterActive) {
      geoDetections = allGeo.where((d) {
        if (wd.flockFilter &&
            (d.engine == Engine.flockBle || d.engine == Engine.flockWifi)) {
          return true;
        }
        if (wd.detectorFilter && (d.engine == Engine.detector || isAlerted(d))) return true;
        return false;
      }).toList();
    } else {
      geoDetections = allGeo;
    }
    if (geoDetections.isEmpty) return const _DetectionLayers.empty();

    final zoom = _currentZoom;
    final zoomScale = ((zoom - 12.0) / 5.0).clamp(0.55, 1.7);

    final priority = <Detection>[];
    final clusterable = <Detection>[];
    for (final d in geoDetections) {
      final isFlock = d.engine == Engine.flockBle || d.engine == Engine.flockWifi;
      final isDrone = d.engine == Engine.skySpy;
      final isDetector = d.engine == Engine.detector;
      if (isFlock || isDrone || isDetector || isAlerted(d)) {
        priority.add(d);
      } else {
        clusterable.add(d);
      }
    }

    final droneById = <String, Detection>{};
    final priorityDeduped = <Detection>[];
    for (final d in priority) {
      if (d.engine != Engine.skySpy) {
        priorityDeduped.add(d);
        continue;
      }
      final id = (d.odid?.uavId?.isNotEmpty ?? false)
          ? d.odid!.uavId!
          : d.macAddress;
      final ex = droneById[id];
      if (ex == null || odidCompleteness(d.odid) > odidCompleteness(ex.odid)) {
        droneById[id] = d;
      }
    }
    priorityDeduped.addAll(droneById.values);
    priority
      ..clear()
      ..addAll(priorityDeduped);

    final meanLat = clusterable.isNotEmpty
        ? clusterable.first.latitude!
        : (priority.isNotEmpty
            ? (priority.first.latitude ??
                droneRidPoint(priority.first)?.latitude ??
                0.0)
            : 0.0);
    final mPerPx = _metersPerPixel(meanLat, zoom);
    final pixelBucketRadius = 28.0;
    final bucketRadiusM = max(wd.markerDistanceM.toDouble(),
        pixelBucketRadius * mPerPx);
    final cellM = bucketRadiusM * 2.0;
    final cosMean = cos(meanLat * pi / 180);

    final centers = <LatLng>[];
    final counts = <int>[];
    final engineMix = <Map<Engine, int>>[];
    final sumLat = <double>[];
    final sumLon = <double>[];
    final cellToIdx = <int, int>{};
    final clusterIdxOf = <int>[]; // parallel to clusterable
    for (final d in clusterable) {
      final gx = (d.latitude! * 111320.0 / cellM).floor();
      final gy = (d.longitude! * 111320.0 * cosMean / cellM).floor();
      final key = (gx & 0x3FFFFFF) << 26 | (gy & 0x3FFFFFF);
      var idx = cellToIdx[key];
      if (idx == null) {
        idx = centers.length;
        cellToIdx[key] = idx;
        centers.add(LatLng(d.latitude!, d.longitude!));
        counts.add(0);
        engineMix.add(<Engine, int>{});
        sumLat.add(0);
        sumLon.add(0);
      }
      counts[idx] = counts[idx] + 1;
      sumLat[idx] = sumLat[idx] + d.latitude!;
      sumLon[idx] = sumLon[idx] + d.longitude!;
      engineMix[idx][d.engine] = (engineMix[idx][d.engine] ?? 0) + 1;
      clusterIdxOf.add(idx);
    }
    for (var i = 0; i < centers.length; i++) {
      centers[i] = LatLng(sumLat[i] / counts[i], sumLon[i] / counts[i]);
    }

    final sortedCounts = List<int>.from(counts)..sort();
    int percentile(double p) {
      if (sortedCounts.isEmpty) return 1;
      final idx = (sortedCounts.length * p).floor()
          .clamp(0, sortedCounts.length - 1);
      return sortedCounts[idx];
    }
    final p50 = percentile(0.50);
    final p90 = percentile(0.90);
    final p99 = percentile(0.99);

    final heatRadiusM = max(bucketRadiusM * 0.42, 6.0);
    final heatStride = clusterable.length > 800
        ? (clusterable.length / 800).ceil()
        : 1;
    final heat = <CircleMarker>[];
    for (var i = 0; i < clusterable.length; i += heatStride) {
      final d = clusterable[i];
      final ci = clusterIdxOf[i];
      final densityTint = _percentileBlend(
          d.engine.color, counts[ci], p50, p90, p99);
      heat.add(CircleMarker(
        point: LatLng(d.latitude!, d.longitude!),
        radius: heatRadiusM,
        useRadiusInMeter: true,
        color: densityTint.withValues(alpha: 0.07),
        borderStrokeWidth: 0,
      ));
    }

    final clusters = <Marker>[];
    for (var i = 0; i < centers.length; i++) {
      final center = centers[i];
      final n = counts[i];
      final entries = engineMix[i].entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final dominant = entries.first.key;
      final secondary = entries.length > 1 && entries[1].value > 0
          ? entries[1].key
          : null;

      final base = 22.0 + 8.0 * (log(n + 1) / ln10);
      final size = (base * zoomScale).clamp(26.0, 60.0);
      final domColor = dominant.color;
      final secColor = secondary?.color;
      final heatColor = _percentileBlend(domColor, n, p50, p90, p99);
      clusters.add(Marker(
        point: center,
        width: size + 16,
        height: size + 16,
        alignment: Alignment.center,
        rotate: true,
        child: _ClusterDot(
          fill: heatColor,
          engineColor: domColor,
          secondaryEngineColor: secColor,
          size: size,
          count: n,
        ),
      ));
    }

    final pins = <Marker>[];
    final tethers = <Polyline>[];
    final trails = <Polyline>[];
    final rings = <CircleMarker>[];
    final grpCount = <String, int>{};
    for (final d in priority) {
      final k = plotKey(d);
      if (k.isNotEmpty) grpCount[k] = (grpCount[k] ?? 0) + 1;
    }
    final grpSeen = <String, int>{};
    for (final d in priority) {
      final isDrone = d.engine == Engine.skySpy;
      final isDetector = d.engine == Engine.detector;
      final pinHead = (24.0 * zoomScale).clamp(18.0, 32.0);
      final pk = plotKey(d);
      final gi = grpSeen[pk] ?? 0;
      grpSeen[pk] = gi + 1;
      final bRad = _routeBearingRad(
          LatLng(d.latitude ?? 0, d.longitude ?? 0), wd.routePoints);
      final base =
          bRad != null ? bRad + _currentRotation * pi / 180.0 : -pi / 2;
      final fan = fanGeometry(gi, grpCount[pk] ?? 1, baseAngle: base);

      if (isDrone) {
        final color = droneColorForMac(d.macAddress);
        final ridPt = droneRidPoint(d);

        if (ridPt == null) {
          final isBle = isBleMethod(d.method);
          final rangeM = rssiToMeters(d.rssi, isBle: isBle);
          final obs = LatLng(d.latitude!, d.longitude!);
          rings.add(CircleMarker(
            point: obs,
            radius: rangeM,
            useRadiusInMeter: true,
            color: Colors.transparent,
            borderColor: color.withValues(alpha: 0.9),
            borderStrokeWidth: 2.0,
          ));
          final droneBox = (fan.length + 22) * 2;
          pins.add(Marker(
            point: obs,
            width: droneBox,
            height: droneBox,
            alignment: Alignment.center,
            rotate: true,
            child: FannedPin(
              geo: fan,
              lineColor: color,
              headExtent: 22,
              head: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showDetectionDetails(context, ref, d),
                child: DroneRangePin(
                  color: color,
                  label: rssiRangeLabel(d.rssi, isBle: isBle),
                  fresh: droneIsFresh(d),
                ),
              ),
            ),
          ));
          continue;
        }

        final dronePt = ridPt;
        final trackKey = AppState.droneTrackKey(d);
        final droneTrack = appState.droneTrack(trackKey);
        if (droneTrack != null && droneTrack.length >= 2) {
          trails.add(Polyline(
            points: droneTrack,
            color: color,
            strokeWidth: 2.2,
          ));
        }
        final pilotTrack = appState.pilotTrack(trackKey);
        if (pilotTrack != null && pilotTrack.length >= 2) {
          trails.add(Polyline(
            points: pilotTrack,
            color: color.withValues(alpha: 0.8),
            strokeWidth: 1.8,
            pattern: StrokePattern.dashed(segments: const [5, 5]),
          ));
        }
        final box = pinHead + 16;
        pins.add(Marker(
          point: dronePt,
          width: box,
          height: box,
          alignment: Alignment.center,
          rotate: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDetectionDetails(context, ref, d),
            child: DronePin(color: color, size: pinHead, fresh: droneIsFresh(d)),
          ),
        ));
        final pilotPt = pilotRidPoint(d);
        if (pilotPt != null) {
          final psize = pinHead * 0.8;
          final pbox = psize + 14;
          pins.add(Marker(
            point: pilotPt,
            width: pbox,
            height: pbox,
            alignment: Alignment.center,
            rotate: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showDetectionDetails(context, ref, d),
              child: PilotPin(
                color: color,
                size: psize,
                isTakeoff: (d.odid?.opLocationType ?? -1) == 0,
              ),
            ),
          ));
          tethers.add(Polyline(
            points: [dronePt, pilotPt],
            color: color.withValues(alpha: 0.65),
            strokeWidth: 1.6,
            pattern: StrokePattern.dashed(segments: const [6, 6]),
          ));
        }
        continue;
      }

      final classPin = isAlerted(d) && d.engine != Engine.detector && d.engine != Engine.flockBle && d.engine != Engine.flockWifi;
      final alertKind = alertKinds[d.macAddress.toUpperCase()];
      final pinColor = classPin ? alertKindColor(alertKind) : d.engine.color;
      final box = (fan.length + pinHead + 5) * 2;
      pins.add(Marker(
        point: LatLng(d.latitude!, d.longitude!),
        width: box,
        height: box,
        alignment: Alignment.center,
        rotate: true,
        child: FannedPin(
          geo: fan,
          lineColor: pinColor,
          headExtent: pinHead + 5,
          head: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDetectionDetails(context, ref, d),
            child: Container(
              width: pinHead,
              height: pinHead,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pinColor,
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Icon(
                isDetector
                    ? Icons.radar
                    : OuiLookupService.isLawEnforcement(d.macAddress)
                        ? Icons.local_police
                        : classPin
                            ? alertKindIcon(alertKind)
                            : Icons.videocam,
                size: pinHead * 0.58,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ));
    }

    return _DetectionLayers(
        heat: heat,
        clusters: clusters,
        pins: pins,
        tethers: tethers,
        trails: trails,
        rings: rings);
  }

  static double? _routeBearingRad(LatLng p, List<LatLng> route) {
    if (route.length < 2) return null;
    final cosLat = cos(p.latitude * pi / 180);
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final dLat = route[i].latitude - p.latitude;
      final dLon = (route[i].longitude - p.longitude) * cosLat;
      final d = dLat * dLat + dLon * dLon;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    final a = route[(best - 1).clamp(0, route.length - 1)];
    final b = route[(best + 1).clamp(0, route.length - 1)];
    final dN = b.latitude - a.latitude;
    final dE = (b.longitude - a.longitude) * cosLat;
    if (dN == 0 && dE == 0) return null;
    return atan2(dE, dN);
  }

  static double _shortAngleDelta(double from, double to) {
    var d = (to - from) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  static double _metersPerPixel(double lat, double zoom) =>
      156543.03392 * cos(lat * pi / 180) / pow(2, zoom);

  static const List<Color> _densityStops = [
    Color(0xFF3B82F6), // blue     — singletons / very sparse
    Color(0xFF06B6D4), // cyan
    Color(0xFF22C55E), // green
    Color(0xFFEAB308), // yellow
    Color(0xFFF97316), // orange
    Color(0xFFEF4444), // red
    Color(0xFFEC4899), // magenta  — peak density
  ];

  static Color _densityLerp(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final scaled = clamped * (_densityStops.length - 1);
    final idx = scaled.floor().clamp(0, _densityStops.length - 2);
    final f = scaled - idx;
    return Color.lerp(_densityStops[idx], _densityStops[idx + 1], f)!;
  }

  static Color _percentileBlend(
      Color engineColor, int count, int p50, int p90, int p99) {
    double t;
    if (count <= p50) {
      final span = max(1, p50);
      t = 0.5 * (count / span);
    } else if (count <= p90) {
      final span = max(1, p90 - p50);
      t = 0.5 + 0.33 * ((count - p50) / span);
    } else {
      final span = max(1, p99 - p90);
      t = 0.83 + 0.17 * ((count - p90) / span).clamp(0.0, 1.0);
    }
    return _densityLerp(t);
  }

  Widget _runControls(WidgetRef ref, WardriveController wd) {
    if (wd.state == WardriveState.idle) return const SizedBox.shrink();
    return WardriveRunCard(
      showButtons: wd.radioTransition != 'stopping',
      stats: wd.currentStats,
      targets: wd.activeLabel,
      paused: wd.state == WardriveState.paused,
      onPause: () => ref.read(wardriveProvider).pauseSession(),
      onResume: () => ref.read(wardriveProvider).resumeSession(),
      onStop: () => ref.read(wardriveProvider).stopSession(),
    );
  }
}

