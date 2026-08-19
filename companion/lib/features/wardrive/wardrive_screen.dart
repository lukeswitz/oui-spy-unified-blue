import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/watchlist_state.dart';

import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_provider.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/wardrive/drone_markers.dart';
import 'package:oui_spy/features/geofence/geofence_screen.dart';
import 'package:oui_spy/features/wardrive/flock_panel.dart';
import 'package:oui_spy/features/wardrive/wardrive_stats.dart';
import 'package:oui_spy/features/wardrive/wardrive_theme.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:share_plus/share_plus.dart';

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
  String _cachedLayersKey = '';
  List<Geofence> _exclusionZones = [];
  bool _priming = false;
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

  Future<bool> _primeLocationPermission() async {
    if (_priming || !mounted) return false;
    _priming = true;
    try {
      var status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        status = await Geolocator.requestPermission();
      }
      if (!mounted) return false;
      if (status == LocationPermission.denied ||
          status == LocationPermission.deniedForever) {
        _showPermissionGateDialog();
        return false;
      }
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return false;
      if (!servicesOn) {
        _showServicesOffDialog();
        return false;
      }

      if (Platform.isIOS) {
        if (status == LocationPermission.whileInUse) {
          await _showIosAlwaysUpgradeDialog();
        }
      } else if (Platform.isAndroid) {
        final always = await ph.Permission.locationAlways.status;
        if (!always.isGranted && mounted) {
          await _showAndroidAlwaysUpgradeDialog();
        }
      }
      return true;
    } finally {
      _priming = false;
    }
  }

  Future<void> _requestAlwaysLocation() async {
    final always = await ph.Permission.locationAlways.request();
    if (!always.isGranted) {
      await ph.openAppSettings();
    }
  }

  Future<bool> _confirmRadioRoles() async {
    final app = ref.read(appStateProvider);
    final wd = ref.read(wardriveProvider);
    if (!app.isManagerConnected) return true;
    final mgrId = AppState.canonicalNodeId(app.nodeId);
    final nodes = app.liveKnownNodes.where((id) => id != mgrId).toList()..sort();
    if (nodes.isEmpty) return true;
    final roles = <String, int>{
      for (final n in nodes) n: app.wardriveRadioForNode(n),
    };
    if (!mounted) return false;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _RadioRolePopup(
        nodes: nodes,
        labelFor: app.labelForNode,
        initial: roles,
      ),
    );
    if (result == null) return false;
    await app.applyNodeRadioRoles(result);
    if (!app.isManagerConnected && result.length == 1) {
      final mask = result.values.first;
      wd.setRadio(WardriveController.radioFromMask(mask));
      app.setEngineRadio(Engine.wardrive, mask);
    }
    return true;
  }

  Future<void> _showIosAlwaysUpgradeDialog() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('ios_always_upgrade_dismissed') == true) return;
    if (!mounted) return;
    final t = AppTheme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Enable "Always" Location',
          style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'iOS only shows "While Using" in the first prompt. For wardriving with screen off, set:\n\n'
          'Settings → OUI-SPY → Location → Always',
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await p.setBool('ios_always_upgrade_dismissed', true);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text("DON'T ASK AGAIN", style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('LATER', style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Geolocator.openAppSettings();
            },
            child: const Text('OPEN SETTINGS', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAndroidAlwaysUpgradeDialog() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('android_always_upgrade_dismissed') == true) return;
    if (!mounted) return;
    final t = AppTheme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Enable "Always" Location',
          style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'For background tracking, Android requires "Allow all the time".\n\n'
          'Settings → Apps → OUI-SPY → Permissions → Location → Allow all the time',
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await p.setBool('android_always_upgrade_dismissed', true);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text("DON'T ASK AGAIN", style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('LATER', style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _requestAlwaysLocation();
            },
            child: const Text('ALLOW ALL THE TIME', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  void _showPermissionGateDialog() {
    final t = AppTheme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Location Permission Required',
          style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'OUI-SPY needs location access to tag wardrive detections.\n\n'
          'Open Settings → OUI-SPY → Location and choose "While Using" or "Always".',
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('LATER', style: TextStyle(color: t.textDim)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Geolocator.openAppSettings();
            },
            child: const Text('OPEN SETTINGS', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  void _showServicesOffDialog() {
    final t = AppTheme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Location Services Off',
          style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'Enable Settings → Privacy & Security → Location Services to wardrive.',
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showReconnectPrompt(WardriveController wd) async {
    final t = AppTheme.of(context);
    final cont = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            child: const Text('CONTINUE', style: TextStyle(color: AppTheme.accent)),
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

  /// Tapping a detection isolates it: the map drops every other pin until
  /// the focus chip is cleared.
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
    const zoneColor = Color(0x30E6A85A); // warning @ 0.19
    const zoneBorder = Color(0x99E6A85A); // warning @ 0.6

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

  /// WDGWars gang territory hulls, culled to the visible viewport.
  List<Widget> _territoryLayers(WdgwarsProvider wdg) {
    if (!wdg.showTerritories || wdg.territories.isEmpty) return const [];

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
    final wt = ref.watch(wardriveThemeDataProvider);
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
    final povActive =
        gpsPos2 != null && (wt.driverPov || (wd.isActive && _followMode));
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
          if (!(wt.driverPov || (wd.isActive && _followMode))) return;
          _applyFollowCamera(here, _povHeading);
        });
      } else if (wasFollowing) {
        // Stopped but had a heading — hold last heading, recenter.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!(wt.driverPov || (wd.isActive && _followMode))) return;
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

    final detectionLayers = _buildDetectionLayers(wd, wt);
    final tileUrl = wt.mapTileOverride ?? mapStyle.urlTemplate;
    final darkBase = wt.mapTileOverride != null ? true : mapStyle.isDark;

    final mapWidget = FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                backgroundColor: darkBase ? const Color(0xFF0A0A0A) : const Color(0xFFE8E8EE),
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
                  if (event is MapEventRotate || event is MapEventRotateEnd) {
                    final r = _mapController.camera.rotation;
                    if ((r - _currentRotation).abs() > 0.5) {
                      setState(() => _currentRotation = r);
                    }
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: tileUrl,
                  userAgentPackageName: 'tech.colonelpanic.ouispy',
                  maxZoom: 19,
                  tileBuilder: wt.tileTint != null
                      ? (context, tileWidget, tile) => ColorFiltered(
                            colorFilter: wt.tileTint!,
                            child: tileWidget,
                          )
                      : null,
                ),
                ..._territoryLayers(ref.watch(wdgwarsProvider)),
                if (detectionLayers.heat.isNotEmpty)
                  CircleLayer(circles: detectionLayers.heat),
                ..._exclusionZoneLayers(),
                if (wd.routePoints.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: wd.routePoints,
                      color: wt.routeColor.withValues(alpha: wt.routeAlpha),
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
                      width: wt.synthwaveSky ? 56 : 16,
                      height: wt.synthwaveSky ? 56 : 16,
                      child: _CurrentPosMarker(theme: wt),
                    ),
                  ]),
              ],
            );

    Widget mapStack = mapWidget;
    const horizonFrac = 0.34;
    final isPov = wt.synthwaveSky;

    // Speed-tied effects sample current speed (m/s).
    final speed = wd.currentPosition?.speed ?? 0.0;
    final units = ref.watch(unitSystemProvider);
    final speedDisplay = units == UnitSystem.imperial
        ? (wd.currentPosition?.speedMph ?? 0.0)
        : (wd.currentPosition?.speedKmh ?? 0.0);
    final speedUnit = units == UnitSystem.imperial ? 'MPH' : 'KM/H';

    return Scaffold(
      backgroundColor: wt.synthwaveSky ? Colors.black : t.background,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight;
          final w = c.maxWidth;
          final horizonY = isPov ? h * horizonFrac : 0.0;

          return Stack(children: [
            // Sky on top band.
            if (wt.synthwaveSky)
              Positioned(
                top: 0, left: 0, right: 0, height: horizonY,
                child: IgnorePointer(child: _SynthwaveSky(theme: wt)),
              ),
            // Tilted map fills bottom band.
            Positioned(
              top: horizonY, left: 0, right: 0, bottom: 0,
              child: mapStack,
            ),
            if (_focusedDetection != null)
              Positioned(
                top: horizonY + 8, left: 0, right: 0,
                child: Center(
                  child: _FocusedDetectionChip(
                    detection: _focusedDetection!,
                    onClear: _clearFocusedDetection,
                  ),
                ),
              ),
            if (wt.synthwaveSky)
              Positioned(
                top: horizonY - 28, left: 0, right: 0, height: 36,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MountainsPainter(
                      ridge: wt.accent,
                      glow: wt.secondary,
                    ),
                  ),
                ),
              ),
            if (wt.synthwaveSky)
              Positioned(
                top: horizonY, left: 0, right: 0, bottom: 0,
                child: IgnorePointer(
                  child: _SynthwaveGrid(
                    color: wt.accent,
                    accent: wt.secondary,
                    speed: speed,
                  ),
                ),
              ),
            // Palm tree silhouettes streaming past on both sides (perspective).
            if (wt.synthwaveSky)
              Positioned(
                top: horizonY, left: 0, right: 0, bottom: 0,
                child: IgnorePointer(
                  child: _PalmStreaker(
                    silhouette: const Color(0xFF0A0014),
                    glow: wt.accent,
                    speed: speed,
                  ),
                ),
              ),
            // Speed lines stream into the horizon from the vanishing point.
            if (wt.speedLines && wd.isActive)
              Positioned(
                top: 0, left: 0, right: 0, bottom: 0,
                child: IgnorePointer(
                  child: _SpeedLines(
                    color: wt.accent,
                    speed: speed,
                    horizonY: horizonY,
                    width: w,
                  ),
                ),
              ),
            // CRT scanline filter — subtle aged-screen feel across whole UI.
            if (wt.synthwaveSky)
              const Positioned.fill(
                child: IgnorePointer(child: _CrtScanlines()),
              ),
            // Capture flash burst when score increments.
            if (wt.detectionBanner && wd.isActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: _CaptureFlash(
                    color: wt.tertiary,
                    score: wd.dedupedDetections.length,
                  ),
                ),
              ),
            // Big digital speedometer.
            if (wt.speedoHud && wd.isActive)
              Positioned(
                bottom: 96, left: 0, right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _SpeedoHud(
                      theme: wt,
                      speed: speedDisplay,
                      unit: speedUnit,
                    ),
                  ),
                ),
              ),
            // Arcade-style score chip top-right.
            if (wt.scoreChip && wd.isActive)
              Positioned(
                top: _statsHeight + 8, right: 12,
                child: IgnorePointer(
                  child: _ScoreChip(
                    theme: wt,
                    score: wd.dedupedDetections.length,
                  ),
                ),
              ),

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
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        wd.radioTransition == 'stopping'
                            ? 'RADIO SHUTTING DOWN…'
                            : 'RADIO STARTING UP…',
                        style: const TextStyle(
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
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final m in WardriveController.selectableTargets)
                        if (m != WardriveTarget.wigle &&
                            ((wd.isActive && wd.isTargetSelected(m)) ||
                                _targetEngineRunning(appEngines, m)))
                          _ScanningPill(color: m.color, label: m.label),
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
              child: _MapStyleButton(ref: ref, mapStyle: mapStyle),
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
                  appEngines: appEngines,
                  isManagerConnected: ref.watch(
                      appStateProvider.select((s) => s.isManagerConnected)),
                  enginesRunning: WardriveController.selectableTargets.any((m) =>
                      m != WardriveTarget.wigle &&
                      _targetEngineRunning(appEngines, m)),
                  onGeofenceReturn: _loadExclusionZones,
                  onStart: () async {
                    if (!await _primeLocationPermission()) return;
                    if (!await _confirmRadioRoles()) return;
                    await ref.read(wardriveProvider).startSession();
                  },
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
                        accent: const Color(0xFF4AFFEA),
                        onDetectionTap: (d) => _zoomToDetection(d),
                      ),
                    ],
                    if (wd.includesDetector) ...[
                      const SizedBox(height: 6),
                      FlockPanel(
                        detections: wd.detectorDetections,
                        icon: Icons.radar,
                        accent: const Color(0xFF4A9EFF),
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
            if (wd.isActive && ref.watch(appStateProvider).isManagerConnected && ref.watch(appStateProvider).meshEnabled)
              Positioned(
                top: _statsHeight + 48, left: 12,
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
          ]);
        }),
      ),
    );
  }

  _DetectionLayers _buildDetectionLayers(WardriveController wd, WardriveThemeData wt) {
    final recentLen = ref.read(appStateProvider).recentDetections.length;
    final focus = _focusedDetection;
    final key = '${wd.dedupedDetections.length}|$recentLen|${wd.flockFilter}|'
        '${wd.detectorFilter}|${_currentZoom.toStringAsFixed(1)}|${wd.sessionId}|'
        '${focus == null ? '' : '${focus.macAddress}|${focus.engine.name}'}';
    if (_cachedLayersKey == key && _cachedLayers != null) return _cachedLayers!;
    final layers = _computeDetectionLayers(wd, wt);
    _cachedLayers = layers;
    _cachedLayersKey = key;
    return layers;
  }

  _DetectionLayers _computeDetectionLayers(WardriveController wd, WardriveThemeData wt) {
    final appState = ref.read(appStateProvider);
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
    } else if (filterActive) {
      geoDetections = allGeo.where((d) {
        if (wd.flockFilter &&
            (d.engine == Engine.flockBle || d.engine == Engine.flockWifi)) {
          return true;
        }
        if (wd.detectorFilter && d.engine == Engine.detector) return true;
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
      if (isFlock || isDrone || isDetector) {
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
          wt.engineColor(d.engine), counts[ci], p50, p90, p99);
      heat.add(CircleMarker(
        point: LatLng(d.latitude!, d.longitude!),
        radius: heatRadiusM,
        useRadiusInMeter: true,
        color: densityTint.withValues(alpha: wt.markerSaturation),
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
      final domColor = wt.engineColor(dominant);
      final secColor = secondary != null ? wt.engineColor(secondary) : null;
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
          neon: wt.neonClusters,
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

      final pinColor = wt.engineColor(d.engine);
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
                boxShadow: const [
                  BoxShadow(
                      color: Color(0xAA000000),
                      blurRadius: 4,
                      spreadRadius: 0.5),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                isDetector
                    ? Icons.radar
                    : OuiLookupService.isLawEnforcement(d.macAddress)
                        ? Icons.local_police
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

  /// Geographic bearing (rad, clockwise from north) of the route polyline at
  /// its vertex nearest [p]. Null when the route is too short to have a
  /// direction. Leaders are drawn perpendicular to this so heads sit off to
  /// the side of the path instead of overlapping it.
  // ponytail: O(detections·routePoints) nearest scan; build a grid index if a
  // long session's marker rebuild ever lags.
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
    if (wd.radioTransition != null) {
      return const SizedBox.shrink();
    }
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
  const _IdleControls({required this.wd, required this.ref, required this.appEngines, required this.isManagerConnected, required this.enginesRunning, this.onGeofenceReturn, required this.onStart});
  final WardriveController wd;
  final WidgetRef ref;
  final AppState appEngines;
  final bool isManagerConnected;
  final bool enginesRunning;
  final VoidCallback? onGeofenceReturn;
  final Future<void> Function() onStart;

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
                children: WardriveController.selectableTargets.map((m) {
                  final liveTargets = {
                    for (final x in WardriveController.selectableTargets)
                      if (_targetEngineRunning(appEngines, x)) x
                  };
                  final sel = _targetEngineRunning(appEngines, m) ||
                      (liveTargets.isEmpty && wd.isTargetSelected(m));
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(wardriveProvider).onChipTap(m, liveTargets),
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
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(m.icon, size: 16, color: sel ? m.color : th.textDim),
                                if (sel)
                                  Positioned(
                                    right: -6, top: -5,
                                    child: Icon(Icons.check_circle, size: 9, color: m.color),
                                  ),
                              ],
                            ),
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
              if (!isManagerConnected) ...[
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
                            final mask = switch (r) {
                              WardriveRadio.wifi => 0x01,
                              WardriveRadio.ble => 0x02,
                              WardriveRadio.both => 0x03,
                            };
                            final app = ref.read(appStateProvider);
                            for (final tt in wd.selectedTargets) {
                              final maskEngine = tt.radioMaskEngine;
                              if (maskEngine != null) {
                                app.setEngineRadio(maskEngine, mask);
                              }
                            }
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
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  ref.context,
                  MaterialPageRoute(builder: (_) => const GeofenceScreen()),
                );
                onGeofenceReturn?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: th.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: th.border),
                ),
                child: Icon(Icons.fence, size: 14, color: AppTheme.warning),
              ),
            ),
            const SizedBox(width: 12),
            if (enginesRunning)
              _Pill(
                label: 'STOP',
                color: AppTheme.error,
                onTap: () => ref.read(wardriveProvider).stopSession(),
              )
            else
              _Pill(
                label: 'START',
                color: wd.selectedTargets.isEmpty
                    ? t.color.withValues(alpha: 0.35)
                    : t.color,
                onTap: () {
                  if (wd.selectedTargets.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select at least one target to scan'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                    return;
                  }
                  ref.read(gpsProvider).onMessage = (msg) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          backgroundColor: AppTheme.accent,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  };
                  onStart();
                },
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
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.18)
                : t.surface.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? AppTheme.accent.withValues(alpha: 0.7)
                  : t.border,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? AppTheme.accent : t.textSecondary,
          ),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

class _CompassResetBtn extends StatelessWidget {
  const _CompassResetBtn({required this.rotation, required this.onTap});
  final double rotation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Tooltip(
      message: 'Tap to reset north up',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.55),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Transform.rotate(
              angle: -rotation * pi / 180.0,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(28, 28),
                    painter: _CompassNeedlePainter(),
                  ),
                  const Positioned(
                    top: 2,
                    child: Text(
                      'N',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final red = Paint()..color = const Color(0xFFE54848);
    final gray = Paint()..color = const Color(0xFF888888);
    final pathN = ui.Path()
      ..moveTo(c.dx, c.dy - 10)
      ..lineTo(c.dx - 4, c.dy)
      ..lineTo(c.dx + 4, c.dy)
      ..close();
    final pathS = ui.Path()
      ..moveTo(c.dx, c.dy + 10)
      ..lineTo(c.dx - 4, c.dy)
      ..lineTo(c.dx + 4, c.dy)
      ..close();
    canvas.drawPath(pathN, red);
    canvas.drawPath(pathS, gray);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MeasuredBox extends StatefulWidget {
  const _MeasuredBox({
    required this.statsKey,
    required this.onHeightChanged,
    required this.child,
  });
  final GlobalKey statsKey;
  final ValueChanged<double> onHeightChanged;
  final Widget child;

  @override
  State<_MeasuredBox> createState() => _MeasuredBoxState();
}

class _MeasuredBoxState extends State<_MeasuredBox> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _MeasuredBox old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final box = widget.statsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.onHeightChanged(box.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: widget.statsKey, child: widget.child);
  }
}

class _MapStyleButton extends StatelessWidget {
  const _MapStyleButton({required this.ref, required this.mapStyle});
  final WidgetRef ref;
  final MapStyle mapStyle;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final wdg = ref.watch(wdgwarsProvider);
    return PopupMenuButton<MapStyle?>(
      initialValue: mapStyle,
      onSelected: (style) {
        if (style == null) {
          ref.read(wdgwarsProvider).setShowTerritories(!wdg.showTerritories);
        } else {
          ref.read(mapStyleProvider.notifier).setStyle(style);
        }
      },
      offset: const Offset(0, 40),
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.border),
      ),
      itemBuilder: (_) => [
        ...MapStyle.values.map((style) {
          final selected = style == mapStyle;
          return PopupMenuItem<MapStyle?>(
            value: style,
            height: 36,
            child: Row(
              children: [
                Icon(
                  style.isDark ? Icons.dark_mode : Icons.light_mode,
                  size: 14,
                  color: selected ? AppTheme.accent : t.textDim,
                ),
                const SizedBox(width: 8),
                Text(
                  style.label,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : t.textPrimary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 14, color: AppTheme.accent),
                ],
              ],
            ),
          );
        }),
        if (wdg.isLoggedIn) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem<MapStyle?>(
            value: null,
            height: 36,
            child: Row(
              children: [
                Icon(
                  Icons.flag,
                  size: 14,
                  color: wdg.showTerritories ? AppTheme.wdgwars : t.textDim,
                ),
                const SizedBox(width: 8),
                Text(
                  'WDG TERRITORY',
                  style: TextStyle(
                    color: wdg.showTerritories
                        ? AppTheme.wdgwars
                        : t.textPrimary,
                    fontSize: 12,
                    fontWeight: wdg.showTerritories
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                if (wdg.territoriesLoading)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppTheme.wdgwars,
                    ),
                  )
                else if (wdg.showTerritories)
                  Icon(Icons.check, size: 14, color: AppTheme.wdgwars),
              ],
            ),
          ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.border),
        ),
        child: Icon(Icons.layers, size: 16, color: t.textSecondary),
      ),
    );
  }
}

class _FocusedDetectionChip extends StatelessWidget {
  const _FocusedDetectionChip({required this.detection, required this.onClear});
  final Detection detection;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final name = detection.deviceName.isNotEmpty
        ? detection.deviceName
        : (detection.ssid.isNotEmpty ? detection.ssid : detection.macAddress);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onClear,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: detection.engine.color.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(detection.engine.icon, size: 12, color: detection.engine.color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('SHOW ALL',
                  style: TextStyle(
                    color: t.textDim,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  )),
              const SizedBox(width: 4),
              Icon(Icons.close, size: 12, color: t.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionList extends StatelessWidget {
  const _DetectionList({required this.detections, this.onDetectionTap});
  final List<Detection> detections;
  final void Function(Detection)? onDetectionTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    if (detections.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<Detection>>{};
    for (final d in detections) {
      final key = d.engine == Engine.wardrive
          ? (d.isBleDetection ? 'WARDRIVE BLE' : 'WARDRIVE WIFI')
          : d.engine.label;
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
            ...entry.value.take(10).map((d) => _DetListRow(d: d, onTap: onDetectionTap)),
          ],
        ],
      ),
    );
  }
}

class _FeedToggle extends StatelessWidget {
  const _FeedToggle({
    required this.count,
    required this.collapsed,
    required this.onTap,
  });
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: t.background.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14,
              color: t.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              collapsed ? 'DEVICES  $count' : 'HIDE DEVICES',
              style: TextStyle(
                color: t.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetListRow extends ConsumerWidget {
  const _DetListRow({required this.d, this.onTap});
  final Detection d;
  final void Function(Detection)? onTap;

  void _showCopySheet(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final vendor = ref.read(ouiLookupProvider).lookup(d.macAddress);
    final items = <(String, String)>[
      ('MAC', d.macAddress.toUpperCase()),
      if (d.ssid.isNotEmpty) ('SSID', d.ssid),
      if (d.deviceName.isNotEmpty) ('Name', d.deviceName),
      if (vendor != null) ('Vendor', vendor),
      if (d.odid?.uavId != null) ('UAV ID', d.odid!.uavId!),
      if (d.latitude != null)
        ('Location', '${d.latitude!.toStringAsFixed(5)}, ${d.longitude!.toStringAsFixed(5)}'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COPY', style: TextStyle(
              color: t.textDim, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 2,
            )),
            const SizedBox(height: 8),
            for (final (label, value) in items)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.copy, size: 14, color: t.textDim),
                title: Text(label, style: TextStyle(color: t.textDim, fontSize: 10)),
                subtitle: Text(value, style: TextStyle(
                  color: t.textPrimary, fontSize: 12, fontFamily: 'monospace',
                )),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copied'),
                      backgroundColor: t.surface,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
    final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
    final bool isWifiAp = d.isWifiDetection;
    final bool isHidden = isWifiAp && d.ssid.isEmpty && d.deviceName.isEmpty;
    final vendor = ref.read(ouiLookupProvider).lookup(d.macAddress);
    final label = isHidden
        ? '<hidden>'
        : d.ssid.isNotEmpty
            ? d.ssid
            : d.deviceName.isNotEmpty
                ? d.deviceName
                : vendor ?? '';
    final hasGps = d.latitude != null && d.longitude != null;

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showCopySheet(context, ref);
        }
      },
      child: GestureDetector(
      onTap: hasGps && onTap != null ? () => onTap!(d) : null,
      onLongPress: () => _showCopySheet(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Padding(
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
              style: TextStyle(
                color: vendor != null && d.ssid.isEmpty && d.deviceName.isEmpty
                    ? t.textDim
                    : t.textSecondary,
                fontSize: 9,
              ),
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
    ),
    ),
    );
  }
}

class _DetectionLayers {
  const _DetectionLayers({
    required this.heat,
    required this.clusters,
    required this.pins,
    this.tethers = const [],
    this.trails = const [],
    this.rings = const [],
  });
  const _DetectionLayers.empty()
      : heat = const [],
        clusters = const [],
        pins = const [],
        tethers = const [],
        trails = const [],
        rings = const [];
  final List<CircleMarker> heat;
  final List<Marker> clusters;
  final List<Marker> pins;
  final List<Polyline> tethers;
  final List<Polyline> trails;
  final List<CircleMarker> rings;
}

class _ClusterDot extends StatelessWidget {
  const _ClusterDot({
    required this.fill,
    required this.engineColor,
    required this.secondaryEngineColor,
    required this.size,
    required this.count,
    this.neon = false,
  });
  final Color fill;
  final Color engineColor;
  final Color? secondaryEngineColor;
  final double size;
  final int count;
  final bool neon;

  @override
  Widget build(BuildContext context) {
    final label = count >= 1000
        ? '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k'
        : '$count';
    final ringColor = secondaryEngineColor ?? engineColor;
    return RepaintBoundary(
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: CustomPaint(
          painter: _ClusterPainter(
            fill: fill,
            engineColor: engineColor,
            ringColor: ringColor,
            neon: neon,
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.16 + 4),
            child: count > 1
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: neon ? ringColor : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.0,
                          letterSpacing: -0.3,
                          shadows: neon
                              ? [
                                  Shadow(
                                    color: ringColor.withValues(alpha: 0.8),
                                    blurRadius: 8,
                                  ),
                                ]
                              : const [
                                  Shadow(blurRadius: 3, color: Colors.black87),
                                ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _ClusterPainter extends CustomPainter {
  const _ClusterPainter({
    required this.fill,
    required this.engineColor,
    required this.ringColor,
    required this.neon,
  });
  final Color fill;
  final Color engineColor;
  final Color ringColor;
  final bool neon;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 8;
    if (neon) {
      // Glowing hex ring — synthwave wireframe vibe.
      final path = ui.Path();
      for (var i = 0; i < 6; i++) {
        final a = (pi / 3) * i - pi / 2;
        final x = c.dx + r * cos(a);
        final y = c.dy + r * sin(a);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      // Outer glow.
      canvas.drawPath(
        path,
        Paint()
          ..color = ringColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      // Inner fill.
      canvas.drawPath(
        path,
        Paint()..color = ringColor.withValues(alpha: 0.10),
      );
      // Crisp ring.
      canvas.drawPath(
        path,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    } else {
      canvas.drawCircle(
        c,
        r + 7,
        Paint()
          ..color = fill.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Body.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0),
      );
      // Glow.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = fill.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Stroke.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClusterPainter old) =>
      old.fill != fill ||
      old.engineColor != engineColor ||
      old.ringColor != ringColor ||
      old.neon != neon;
}

class _CompletedSessionBar extends ConsumerStatefulWidget {
  const _CompletedSessionBar({required this.wd, required this.onZoomDetection});
  final WardriveController wd;
  final void Function(Detection) onZoomDetection;

  @override
  ConsumerState<_CompletedSessionBar> createState() => _CompletedSessionBarState();
}

class _CompletedSessionBarState extends ConsumerState<_CompletedSessionBar> {
  WardriveController get wd => widget.wd;

  bool get _flockExpanded => wd.flockFilter;
  bool get _detectorExpanded => wd.detectorFilter;

  void _showFlockCopySheet(BuildContext context, Detection d) {
    final t = AppTheme.of(context);
    final items = <(String, String)>[
      ('MAC', d.macAddress.toUpperCase()),
      if (d.deviceName.isNotEmpty) ('Name', d.deviceName),
      if (d.latitude != null)
        ('Location', '${d.latitude!.toStringAsFixed(5)}, ${d.longitude!.toStringAsFixed(5)}'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COPY', style: TextStyle(
              color: t.textDim, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 2,
            )),
            const SizedBox(height: 8),
            for (final (label, value) in items)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.copy, size: 14, color: t.textDim),
                title: Text(label, style: TextStyle(color: t.textDim, fontSize: 10)),
                subtitle: Text(value, style: TextStyle(
                  color: t.textPrimary, fontSize: 12, fontFamily: 'monospace',
                )),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copied'),
                      backgroundColor: t.surface,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    final wigle = ref.watch(wigleProvider);
    final wdg = ref.watch(wdgwarsProvider);
    final sid = wd.lastCompletedSessionId ?? wd.sessionId;
    final isUploaded = wigle.isUploaded(sid);
    final isUploading = wigle.isUploading(sid);
    final wdgUploaded = wdg.isUploaded(sid);
    final wdgUploading = wdg.isUploading(sid);
    final wdgQueued = wdg.isQueued(sid);
    final flockDets = wd.flockDetections;
    final detectorDets = wd.detectorDetections;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: stats text
          Row(
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
                behavior: HitTestBehavior.opaque,
                onTap: () => wd.clearMapData(),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, size: 14, color: t.textDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: cam chip + action buttons
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: wd.flockCount > 0
                    ? () => wd.toggleFlockFilter()
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _flockExpanded
                        ? AppTheme.flockBle.withValues(alpha: 0.25)
                        : wd.flockCount > 0
                            ? AppTheme.flockBle.withValues(alpha: 0.10)
                            : t.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _flockExpanded
                          ? AppTheme.flockBle.withValues(alpha: 0.7)
                          : wd.flockCount > 0
                              ? AppTheme.flockBle.withValues(alpha: 0.35)
                              : t.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, size: 12,
                          color: wd.flockCount > 0
                              ? AppTheme.flockBle
                              : t.textDim),
                      const SizedBox(width: 4),
                      Text(
                        '${wd.flockCount}',
                        style: TextStyle(
                          color: wd.flockCount > 0
                              ? AppTheme.flockBle
                              : t.textDim,
                          fontSize: 10,
                          fontFamily: 'monospace', fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (wd.flockCount > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          _flockExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 12, color: AppTheme.flockBle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: wd.droneCount > 0
                      ? const Color(0xFF4AFFEA).withValues(alpha: 0.10)
                      : t.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: wd.droneCount > 0
                        ? const Color(0xFF4AFFEA).withValues(alpha: 0.35)
                        : t.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flight, size: 12,
                        color: wd.droneCount > 0
                            ? const Color(0xFF4AFFEA)
                            : t.textDim),
                    const SizedBox(width: 4),
                    Text(
                      '${wd.droneCount}',
                      style: TextStyle(
                        color: wd.droneCount > 0
                            ? const Color(0xFF4AFFEA)
                            : t.textDim,
                        fontSize: 10,
                        fontFamily: 'monospace', fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: wd.detectorCount > 0
                    ? () => wd.toggleDetectorFilter()
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _detectorExpanded
                        ? AppTheme.detector.withValues(alpha: 0.25)
                        : wd.detectorCount > 0
                            ? AppTheme.detector.withValues(alpha: 0.10)
                            : t.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _detectorExpanded
                          ? AppTheme.detector.withValues(alpha: 0.7)
                          : wd.detectorCount > 0
                              ? AppTheme.detector.withValues(alpha: 0.35)
                              : t.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radar, size: 12,
                          color: wd.detectorCount > 0
                              ? AppTheme.detector
                              : t.textDim),
                      const SizedBox(width: 4),
                      Text(
                        '${wd.detectorCount}',
                        style: TextStyle(
                          color: wd.detectorCount > 0
                              ? AppTheme.detector
                              : t.textDim,
                          fontSize: 10,
                          fontFamily: 'monospace', fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (wd.detectorCount > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          _detectorExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 12, color: AppTheme.detector,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _shareCsv(context),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined, size: 14, color: AppTheme.accent),
                      SizedBox(width: 4),
                      Text('CSV', style: TextStyle(
                        color: AppTheme.accent, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5,
                      )),
                    ],
                  ),
                ),
              ),
              if (wigle.isLoggedIn) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isUploaded || isUploading
                      ? null
                      : () => _uploadToWigle(context, ref, sid),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isUploaded ? AppTheme.success : AppTheme.warning)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (isUploaded ? AppTheme.success : AppTheme.warning)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUploading)
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppTheme.warning,
                            ),
                          )
                        else
                          Icon(
                            isUploaded ? Icons.cloud_done : Icons.cloud_upload_outlined,
                            size: 14,
                            color: isUploaded ? AppTheme.success : AppTheme.warning,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          isUploaded ? 'SENT' : 'WIGLE',
                          style: TextStyle(
                            color: isUploaded ? AppTheme.success : AppTheme.warning,
                            fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (wdg.isLoggedIn) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: wdgUploaded || wdgUploading
                      ? null
                      : () => _uploadToWdgwars(context, ref, sid),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (wdgUploaded ? AppTheme.success : AppTheme.wdgwars)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (wdgUploaded ? AppTheme.success : AppTheme.wdgwars)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (wdgQueued)
                          const Icon(Icons.hourglass_top,
                              size: 14, color: AppTheme.wdgwars)
                        else if (wdgUploading)
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppTheme.wdgwars,
                            ),
                          )
                        else
                          Icon(
                            wdgUploaded ? Icons.cloud_done : Icons.sports_esports,
                            size: 14,
                            color: wdgUploaded ? AppTheme.success : AppTheme.wdgwars,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          wdgQueued
                              ? 'QUEUED'
                              : wdgUploading
                                  ? 'SENDING'
                                  : (wdgUploaded ? 'SENT' : 'WDG'),
                          style: TextStyle(
                            color: wdgUploaded ? AppTheme.success : AppTheme.wdgwars,
                            fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Expandable flock detections panel
          if (_flockExpanded && flockDets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.flockBle.withValues(alpha: 0.3)),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                shrinkWrap: true,
                itemCount: flockDets.length,
                itemBuilder: (_, i) {
                  final d = flockDets[i];
                  final isBle = d.engine == Engine.flockBle;
                  final engineColor = isBle ? AppTheme.flockBle : AppTheme.flockWifi;
                  final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
                  final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
                  final hasGps = d.latitude != null && d.longitude != null;
                  final isRaven = d.flock?.isRaven ?? false;

                  return Listener(
                    onPointerDown: (event) {
                      if (event.kind == PointerDeviceKind.mouse &&
                          event.buttons == kSecondaryMouseButton) {
                        _showFlockCopySheet(context, d);
                      }
                    },
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: hasGps ? () => widget.onZoomDetection(d) : null,
                    onLongPress: () => _showFlockCopySheet(context, d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: i < flockDets.length - 1
                            ? Border(bottom: BorderSide(
                                color: t.border.withValues(alpha: 0.5), width: 0.5))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3, height: 20,
                            decoration: BoxDecoration(
                              color: engineColor,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      d.macAddress.toUpperCase(),
                                      style: TextStyle(
                                        color: t.textPrimary, fontSize: 10,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3, vertical: 0.5),
                                      decoration: BoxDecoration(
                                        color: engineColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        isBle ? 'BLE' : 'WiFi',
                                        style: TextStyle(
                                          color: engineColor, fontSize: 7,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (isRaven) ...[
                                      const SizedBox(width: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3, vertical: 0.5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.warning.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: const Text('RAVEN',
                                          style: TextStyle(
                                            color: AppTheme.warning, fontSize: 7,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'ch${d.channel}',
                                      style: TextStyle(
                                        color: t.textDim, fontSize: 8,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    if (hasGps) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.location_on, size: 8,
                                          color: AppTheme.success.withValues(alpha: 0.7)),
                                    ],
                                    if (!hasGps) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.location_off, size: 8,
                                          color: t.textDim),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${d.rssi}',
                            style: TextStyle(
                              color: rssiColor, fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('dBm', style: TextStyle(
                            color: t.textDim, fontSize: 7,
                          )),
                        ],
                      ),
                    ),
                  ),
                  );
                },
              ),
            ),
          ],
          if (_detectorExpanded && detectorDets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.detector.withValues(alpha: 0.3)),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                shrinkWrap: true,
                itemCount: detectorDets.length,
                itemBuilder: (_, i) {
                  final d = detectorDets[i];
                  final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
                  final rssiColor =
                      Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
                  final hasGps = d.latitude != null && d.longitude != null;
                  final desc = d.detector?.filterDescription ?? '';
                  final isFullMac = d.detector?.isFullMac ?? false;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: hasGps ? () => widget.onZoomDetection(d) : null,
                    onLongPress: () => _showFlockCopySheet(context, d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: i < detectorDets.length - 1
                            ? Border(
                                bottom: BorderSide(
                                    color: t.border.withValues(alpha: 0.5),
                                    width: 0.5))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3, height: 20,
                            decoration: BoxDecoration(
                              color: AppTheme.detector,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      d.macAddress.toUpperCase(),
                                      style: TextStyle(
                                        color: t.textPrimary, fontSize: 10,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3, vertical: 0.5),
                                      decoration: BoxDecoration(
                                        color: AppTheme.detector
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        isFullMac ? 'MAC' : 'OUI',
                                        style: const TextStyle(
                                          color: AppTheme.detector, fontSize: 7,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (desc.isNotEmpty || d.deviceName.isNotEmpty)
                                  Text(
                                    desc.isNotEmpty ? desc : d.deviceName,
                                    style: TextStyle(
                                      color: t.textDim, fontSize: 9,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (!hasGps) ...[
                            Icon(Icons.location_off,
                                size: 8, color: t.textDim),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '${d.rssi}',
                            style: TextStyle(
                              color: rssiColor, fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('dBm', style: TextStyle(
                            color: t.textDim, fontSize: 7,
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
          const SnackBar(content: Text('No detection data found for this session')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'OUI-SPY WiGLE CSV',
      sharePositionOrigin: origin,
    );
  }

  Future<void> _uploadToWigle(BuildContext context, WidgetRef wRef, String sid) async {
    if (sid.isEmpty) return;
    if (!await _confirmWigleUpload(context)) return;
    if (!context.mounted) return;
    final wigle = wRef.read(wigleProvider);
    final result = await wigle.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          content: Text(
            'Queued for WiGLE processing',
          ),
        ),
      );
    } else if (wigle.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wigle.error}'),
        ),
      );
    }
  }

  Future<void> _uploadToWdgwars(BuildContext context, WidgetRef wRef, String sid) async {
    if (sid.isEmpty) return;
    if (!await _confirmWdgwarsUpload(context)) return;
    if (!context.mounted) return;
    final wdg = wRef.read(wdgwarsProvider);
    final result = await wdg.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.wdgwars,
          content: Text(result.summary,
              style: const TextStyle(color: Color(0xFF0D1117))),
        ),
      );
    } else if (wdg.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wdg.error}'),
        ),
      );
    }
  }
}

class _SessionHistorySheet extends ConsumerStatefulWidget {
  const _SessionHistorySheet();

  @override
  ConsumerState<_SessionHistorySheet> createState() =>
      _SessionHistorySheetState();
}

class _SessionHistorySheetState extends ConsumerState<_SessionHistorySheet> {
  bool _selectMode = false;
  final Set<String> _selected = <String>{};
  bool _importing = false;

  void _toggleSelect(String sid) {
    setState(() {
      if (_selected.contains(sid)) {
        _selected.remove(sid);
      } else {
        _selected.add(sid);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectMode
                            ? '${_selected.length} SELECTED'
                            : 'WARDRIVE SESSIONS',
                        style: TextStyle(
                          color: t.textPrimary, fontSize: 12,
                          fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    if (_selectMode) ...[
                      _ToolbarChip(
                        label: 'DELETE',
                        color: AppTheme.error,
                        enabled: _selected.isNotEmpty,
                        onTap: () => _deleteSelected(context),
                      ),
                      const SizedBox(width: 6),
                      _ToolbarChip(
                        label: 'CANCEL',
                        color: t.textDim,
                        onTap: _exitSelectMode,
                      ),
                    ] else ...[
                      _ToolbarChip(
                        label: 'SELECT',
                        color: AppTheme.accent,
                        onTap: () => setState(() => _selectMode = true),
                      ),
                      const SizedBox(width: 6),
                      _ToolbarChip(
                        label: _importing ? 'IMPORTING' : 'IMPORT',
                        color: AppTheme.warning,
                        isLoading: _importing,
                        onTap: _importing ? null : () => _importCsv(context),
                      ),
                      const SizedBox(width: 6),
                      _ToolbarChip(
                        label: 'CLEAR ALL',
                        color: AppTheme.error,
                        onTap: () => _clearAllSessions(context, ref),
                      ),
                    ],
                  ],
                ),
              ),
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
                    final wigle = ref.watch(wigleProvider);
                    final wdg = ref.watch(wdgwarsProvider);
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: sessions.length,
                      itemBuilder: (_, i) {
                        final sid = sessions[i].id;
                        final isSelected = _selected.contains(sid);
                        return _SessionRow(
                          session: sessions[i],
                          flockCountFuture: db.flockMacCount(sid),
                          detectorCountFuture: db.detectorMacCount(sid),
                          droneCountFuture: db.droneMacCount(sid),
                          wifiBleFuture: db.wifiBleUniqueCounts(sid),
                          selectable: _selectMode,
                          selected: isSelected,
                          onTap: () {
                            if (_selectMode) {
                              _toggleSelect(sid);
                            } else {
                              Navigator.pop(context);
                              ref.read(wardriveProvider).loadSession(sid);
                            }
                          },
                          onLongPress: () {
                            if (!_selectMode) {
                              setState(() {
                                _selectMode = true;
                                _selected.add(sid);
                              });
                            }
                          },
                          onShare: () => _shareSession(context, ref, sid),
                          onDelete: () => _deleteSession(context, ref, sessions[i]),
                          onUploadWigle: wigle.isLoggedIn
                              ? () => _uploadToWigle(context, ref, sid)
                              : null,
                          wigleUploaded: wigle.isUploaded(sid),
                          wigleUploading: wigle.isUploading(sid),
                          onUploadWdgwars: wdg.isLoggedIn
                              ? () => _uploadToWdgwars(context, ref, sid)
                              : null,
                          wdgwarsUploaded: wdg.isUploaded(sid),
                          wdgwarsUploading: wdg.isUploading(sid),
                          wdgwarsQueued: wdg.isQueued(sid),
                        );
                      },
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

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selected.isEmpty) return;
    final t = AppTheme.of(context);
    final db = ref.read(databaseProvider);
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Delete $count Sessions', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Delete $count selected sessions and all their detections? This cannot be undone.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final wd = ref.read(wardriveProvider);
    final toDelete = _selected.toList();
    for (final sid in toDelete) {
      await db.deleteSession(sid);
      if (wd.loadedSessionId == sid) {
        wd.clearLoadedSession();
      }
    }
    if (mounted) _exitSelectMode();
  }

  Future<void> _importCsv(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final path = file.path;
    if (path.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not access selected file')),
      );
      return;
    }
    setState(() => _importing = true);
    try {
      final db = ref.read(databaseProvider);
      final watchlist =
          List<WatchlistEntry>.from(ref.read(watchlistProvider).entries);
      final res = await WigleCsvImport.importFile(
        db,
        File(path),
        watchlist: watchlist,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.success,
        content: Text(
          'Imported ${res.detectionCount} detections '
          '(${res.uniqueMacs} unique MACs'
          '${res.detectorMacs > 0 ? ", ${res.detectorMacs} watchlist" : ""}'
          '${res.flockMacs > 0 ? ", ${res.flockMacs} flock" : ""}'
          '${res.skipped > 0 ? ", ${res.skipped} skipped" : ""})',
        ),
      ));
    } on FormatException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.error,
        content: Text('Import failed: ${e.message}'),
      ));
    } on FileSystemException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.error,
        content: Text('Import failed: ${e.message}'),
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clearAllSessions(BuildContext context, WidgetRef ref) async {
    final t = AppTheme.of(context);
    final db = ref.read(databaseProvider);
    final sessions = await db.getWardriveSessions();
    final completed = sessions.where((s) => s.endedAt != null).toList();
    if (completed.isEmpty) return;
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Clear All Sessions', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'Delete all ${completed.length} wardrive sessions and their detections? This cannot be undone.',
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
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final s in completed) {
        await db.deleteSession(s.id);
      }
      ref.read(wardriveProvider).clearMapData();
    }
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
      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 100, 100);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'OUI-SPY WiGLE CSV',
        sharePositionOrigin: origin,
      );
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No detection data found for this session')),
        );
      }
    }
  }

  Future<void> _uploadToWigle(BuildContext context, WidgetRef ref, String sid) async {
    final wigle = ref.read(wigleProvider);
    final wd = ref.read(wardriveProvider);

    if (wigle.isUploading(sid)) return;
    if (!await _confirmWigleUpload(context)) return;
    if (!context.mounted) return;

    final result = await wigle.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          content: Text(
            'Queued for WiGLE processing',
          ),
        ),
      );
    } else if (wigle.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wigle.error}'),
        ),
      );
    }
  }

  Future<void> _uploadToWdgwars(BuildContext context, WidgetRef ref, String sid) async {
    final wdg = ref.read(wdgwarsProvider);
    final wd = ref.read(wardriveProvider);

    if (wdg.isUploading(sid)) return;
    if (!await _confirmWdgwarsUpload(context)) return;
    if (!context.mounted) return;

    final result = await wdg.uploadSession(sid, wd);
    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.wdgwars,
          content: Text(result.summary,
              style: const TextStyle(color: Color(0xFF0D1117))),
        ),
      );
    } else if (wdg.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Upload failed: ${wdg.error}'),
        ),
      );
    }
  }
}

Future<bool> _confirmWdgwarsUpload(BuildContext context) async {
  final t = AppTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Upload to WDGWars?',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
      content: Text(
        'This publishes this session — network MACs, SSIDs and GPS coordinates — '
        'to the WDGWars map for your gang. Once uploaded it cannot be retracted.',
        style: TextStyle(color: t.textDim, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.wdgwars,
            foregroundColor: const Color(0xFF0D1117),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('UPLOAD'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<bool> _confirmWigleUpload(BuildContext context) async {
  final t = AppTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('Upload to WiGLE?',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700)),
      content: Text(
        'This publishes this session — network MACs, SSIDs and GPS coordinates — '
        'to the public WiGLE.net database. Once uploaded it cannot be retracted.',
        style: TextStyle(color: t.textDim, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.background,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('UPLOAD'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
    this.onLongPress,
    this.selectable = false,
    this.selected = false,
    this.onUploadWigle,
    this.wigleUploaded = false,
    this.wigleUploading = false,
    this.onUploadWdgwars,
    this.wdgwarsUploaded = false,
    this.wdgwarsUploading = false,
    this.wdgwarsQueued = false,
    this.flockCountFuture,
    this.detectorCountFuture,
    this.droneCountFuture,
    this.wifiBleFuture,
  });
  final Session session;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final bool selectable;
  final bool selected;
  final VoidCallback? onUploadWigle;
  final bool wigleUploaded;
  final bool wigleUploading;
  final VoidCallback? onUploadWdgwars;
  final bool wdgwarsUploaded;
  final bool wdgwarsUploading;
  final bool wdgwarsQueued;
  final Future<int>? flockCountFuture;
  final Future<int>? detectorCountFuture;
  final Future<int>? droneCountFuture;
  final Future<({int wifi, int ble})>? wifiBleFuture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    final wd = ref.watch(wardriveProvider);
    final isRescanning = wd.rescanSessionId == session.id;
    final start = DateTime.fromMillisecondsSinceEpoch(session.startedAt);
    final dateStr = AppTime.dateTime(start);
    final duration = session.endedAt != null
        ? Duration(milliseconds: session.endedAt! - session.startedAt)
        : Duration.zero;
    final durStr = '${duration.inMinutes}m ${duration.inSeconds % 60}s';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : t.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.accent : t.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 440;
            final selectBox = selectable
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: selected ? AppTheme.accent : t.textDim,
                    ),
                  )
                : const SizedBox.shrink();
            final routeIcon = const Icon(Icons.route, size: 16, color: AppTheme.accent);
            final dateText = Text(dateStr, style: TextStyle(
              color: t.textPrimary, fontSize: 11,
              fontFamily: 'monospace', fontWeight: FontWeight.w500,
            ));
            final durText = SizedBox(
              width: 46,
              child: Text(durStr, style: TextStyle(
                color: t.textDim, fontSize: 10,
                fontFamily: 'monospace',
              )),
            );
            final wifiStat = SizedBox(
              width: 44,
              child: FutureBuilder<({int wifi, int ble})>(
                future: wifiBleFuture,
                builder: (_, wbSnap) {
                  final wb = wbSnap.data;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi, size: 11, color: AppTheme.accent),
                      const SizedBox(width: 2),
                      Text(
                        '${wb?.wifi ?? session.uniqueMacCount}',
                        style: TextStyle(
                          color: AppTheme.accent, fontSize: 10,
                          fontFamily: 'monospace', fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
            final bleStat = SizedBox(
              width: 40,
              child: FutureBuilder<({int wifi, int ble})>(
                future: wifiBleFuture,
                builder: (_, wbSnap) {
                  final wb = wbSnap.data;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth, size: 11, color: Colors.blue),
                      const SizedBox(width: 1),
                      Text(
                        '${wb?.ble ?? 0}',
                        style: const TextStyle(
                          color: Colors.blue, fontSize: 10,
                          fontFamily: 'monospace', fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
            final distText = Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 66,
                child: Text(
                  UnitFormatter.distance(session.distanceKm, units),
                  style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
            final flockStat = SizedBox(
              width: 32,
              child: flockCountFuture == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<int>(
                      future: flockCountFuture,
                      builder: (_, snap) {
                        final fc = snap.data ?? 0;
                        if (fc == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, size: 11, color: AppTheme.flockBle),
                            const SizedBox(width: 2),
                            Text(
                              '$fc',
                              style: const TextStyle(
                                color: AppTheme.flockBle, fontSize: 10,
                                fontFamily: 'monospace', fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            );
            final detectorStat = SizedBox(
              width: 32,
              child: detectorCountFuture == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<int>(
                      future: detectorCountFuture,
                      builder: (_, snap) {
                        final dc = snap.data ?? 0;
                        if (dc == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.radar, size: 11, color: AppTheme.detector),
                            const SizedBox(width: 2),
                            Text(
                              '$dc',
                              style: const TextStyle(
                                color: AppTheme.detector, fontSize: 10,
                                fontFamily: 'monospace', fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            );
            final droneStat = SizedBox(
              width: 32,
              child: droneCountFuture == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<int>(
                      future: droneCountFuture,
                      builder: (_, snap) {
                        final dc = snap.data ?? 0;
                        if (dc == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.flight,
                                size: 11, color: Color(0xFF4AFFEA)),
                            const SizedBox(width: 2),
                            Text(
                              '$dc',
                              style: const TextStyle(
                                color: Color(0xFF4AFFEA), fontSize: 10,
                                fontFamily: 'monospace', fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            );
            final csvBtn = _SessionIconBtn(
              icon: Icons.file_download_outlined,
              label: 'CSV',
              color: AppTheme.accent,
              onTap: onShare,
            );
            final wigleBtn = onUploadWigle == null
                ? null
                : _SessionIconBtn(
                    icon: wigleUploading
                        ? Icons.cloud_sync
                        : (wigleUploaded
                            ? Icons.cloud_done
                            : Icons.cloud_upload_outlined),
                    label: wigleUploading
                        ? 'SENDING'
                        : (wigleUploaded ? 'SENT' : 'WIGLE'),
                    color: wigleUploading
                        ? AppTheme.warning
                        : (wigleUploaded ? AppTheme.success : AppTheme.warning),
                    onTap: (wigleUploaded || wigleUploading) ? null : onUploadWigle,
                    isLoading: wigleUploading,
                  );
            final wdgwarsBtn = onUploadWdgwars == null
                ? null
                : _SessionIconBtn(
                    icon: wdgwarsQueued
                        ? Icons.hourglass_top
                        : (wdgwarsUploading
                            ? Icons.cloud_sync
                            : (wdgwarsUploaded
                                ? Icons.cloud_done
                                : Icons.sports_esports)),
                    label: wdgwarsQueued
                        ? 'QUEUED'
                        : (wdgwarsUploading
                            ? 'SENDING'
                            : (wdgwarsUploaded ? 'SENT' : 'WDG')),
                    color: wdgwarsUploaded ? AppTheme.success : AppTheme.wdgwars,
                    onTap: (wdgwarsUploaded || wdgwarsUploading) ? null : onUploadWdgwars,
                    isLoading: wdgwarsUploading && !wdgwarsQueued,
                  );
            final delBtn = _SessionIconBtn(
              icon: Icons.delete_forever_outlined,
              label: 'DEL',
              color: AppTheme.error,
              onTap: onDelete,
            );
            final actionButtons = <Widget>[
              csvBtn,
              const SizedBox(width: 4),
              if (wigleBtn != null) ...[
                wigleBtn,
                const SizedBox(width: 4),
              ],
              if (wdgwarsBtn != null) ...[
                wdgwarsBtn,
                const SizedBox(width: 4),
              ],
              delBtn,
            ];
            final buttons = <Widget>[
              csvBtn,
              ?wigleBtn,
              ?wdgwarsBtn,
              delBtn,
            ];
            final actionBar = Row(
              children: [
                for (int i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: buttons[i]),
                ],
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (narrow) ...[
                  Row(
                    children: [
                      selectBox,
                      routeIcon,
                      const SizedBox(width: 8),
                      Expanded(child: dateText),
                      durText,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      wifiStat,
                      bleStat,
                      distText,
                      flockStat,
                      droneStat,
                      detectorStat,
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  actionBar,
                ] else
                  Row(
                    children: [
                      selectBox,
                      routeIcon,
                      const SizedBox(width: 8),
                      dateText,
                      const SizedBox(width: 10),
                      durText,
                      wifiStat,
                      bleStat,
                      distText,
                      flockStat,
                      droneStat,
                      detectorStat,
                      const Spacer(),
                      ...actionButtons,
                    ],
                  ),
                if (isRescanning) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.detector,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        wd.rescanTotal == 0
                            ? 'CHECKING OUIs'
                            : 'CHECK ${wd.rescanCur}/${wd.rescanTotal}'
                                '${wd.rescanNewDetector > 0 ? ' +${wd.rescanNewDetector}d' : ''}'
                                '${wd.rescanNewFlock > 0 ? ' +${wd.rescanNewFlock}f' : ''}',
                        style: const TextStyle(
                          color: AppTheme.detector,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionIconBtn extends StatelessWidget {
  const _SessionIconBtn({
    required this.icon,
    required this.color,
    this.label,
    this.onTap,
    this.isLoading = false,
  });
  final IconData icon;
  final Color color;
  final String? label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || isLoading;
    final c = enabled ? color : color.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 26,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 5),
        constraints: BoxConstraints(minWidth: label == null ? 26 : 0),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: c),
              )
            else
              Icon(icon, size: 15, color: c),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label!,
                style: TextStyle(
                  color: c,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.label,
    required this.color,
    this.onTap,
    this.enabled = true,
    this.isLoading = false,
  });
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final live = enabled && onTap != null && !isLoading;
    final c = live ? color : color.withValues(alpha: 0.35);
    return GestureDetector(
      onTap: live ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 9, height: 9,
                child: CircularProgressIndicator(strokeWidth: 1.2, color: c),
              ),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(
              color: c.withValues(alpha: 0.9),
              fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
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


class _NodeStatsOverlay extends ConsumerWidget {
  const _NodeStatsOverlay({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final appState = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final selfId = AppState.canonicalNodeId(appState.nodeId);
    final nodeCount =
        appState.liveKnownNodes
            .where((id) => id != selfId && !appState.isManagerNode(id))
            .length;
    final label = '$nodeCount NODE${nodeCount == 1 ? '' : 'S'}';
    final color =
        nodeCount > 0 ? AppTheme.success : AppTheme.warning;
    final perNode = <String, int>{...wd.detectionsPerNode};
    final selfRaw = wd.localWifiCount + wd.localBleCount;
    if (selfRaw > 0) {
      final selfBucket = appState.nodeId.isNotEmpty ? appState.nodeId : 'LOCAL';
      perNode[selfBucket] = (perNode[selfBucket] ?? 0) + selfRaw;
    }
    final nodeEntries = perNode.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (nodeEntries.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...nodeEntries.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: e.key == 'LOCAL'
                              ? AppTheme.accent
                              : AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        '${appState.labelForNode(e.key)}: ${e.value}',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _CurrentPosMarker extends StatefulWidget {
  const _CurrentPosMarker({required this.theme});
  final WardriveThemeData theme;

  @override
  State<_CurrentPosMarker> createState() => _CurrentPosMarkerState();
}

class _CurrentPosMarkerState extends State<_CurrentPosMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.theme.synthwaveSky) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _CurrentPosMarker old) {
    super.didUpdateWidget(old);
    if (widget.theme.synthwaveSky && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.theme.synthwaveSky && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.theme.currentPosColor;
    final dot = CustomPaint(
      size: const Size(14, 14),
      painter: _DotPainter(color: c),
    );
    if (!widget.theme.synthwaveSky) {
      return Center(child: dot);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = Curves.easeOut.transform(_ctrl.value);
        final ringSize = 56.0 * v;
        final ringOpacity = (1.0 - v).clamp(0.0, 1.0) * 0.55;
        return Stack(alignment: Alignment.center, children: [
          Opacity(
            opacity: ringOpacity,
            child: CustomPaint(
              size: Size(ringSize, ringSize),
              painter: _RingPainter(color: c, strokeWidth: 1.0),
            ),
          ),
          dot,
        ]);
      },
    );
  }
}

class _DotPainter extends CustomPainter {
  const _DotPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c, size.width / 2 + 1.5,
      Paint()..color = color.withValues(alpha: 0.25),
    );
    canvas.drawCircle(c, size.width / 2, Paint()..color = color);
    canvas.drawCircle(
      c, size.width / 2 - 1.2,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.drawCircle(c, 2.4, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant _DotPainter old) => old.color != color;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}



class _SynthwaveSky extends StatefulWidget {
  const _SynthwaveSky({required this.theme});
  final WardriveThemeData theme;
  @override
  State<_SynthwaveSky> createState() => _SynthwaveSkyState();
}

class _SynthwaveSkyState extends State<_SynthwaveSky>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SynthwaveSkyPainter(
          phase: _ctrl.value,
          accent: widget.theme.accent,
          secondary: widget.theme.secondary,
          tertiary: widget.theme.tertiary,
        ),
      ),
    );
  }
}

class _SynthwaveSkyPainter extends CustomPainter {
  const _SynthwaveSkyPainter({
    required this.phase,
    required this.accent,
    required this.secondary,
    required this.tertiary,
  });
  final double phase;
  final Color accent;
  final Color secondary;
  final Color tertiary;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height;

    // Sky gradient: deep space at top → magenta → cyan glow at horizon.
    final skyRect = Rect.fromLTWH(0, 0, size.width, horizonY);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF050014),
            const Color(0xFF1A0033),
            const Color(0xFF52004A),
            accent.withValues(alpha: 0.65),
            secondary.withValues(alpha: 0.45),
          ],
          stops: const [0.0, 0.35, 0.7, 0.92, 1.0],
        ).createShader(skyRect),
    );

    // Retro sun — full disc sits in the sky, kissing the horizon.
    final sunRadius = size.width * 0.22;
    final sunCenter = Offset(size.width / 2, horizonY - sunRadius * 0.15);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, horizonY));

    // Sun gradient body.
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tertiary, accent, accent.withValues(alpha: 0.9)],
        ).createShader(
          Rect.fromCircle(center: sunCenter, radius: sunRadius),
        ),
    );

    // Slatted horizontal bands cutting the sun (classic synthwave).
    final bandPaint = Paint()..color = const Color(0xFF050014);
    for (var i = 1; i <= 6; i++) {
      final t = i / 7.0;
      final y = horizonY - sunRadius * (t * t);
      final h = 2.0 + i * 0.6;
      canvas.drawRect(
        Rect.fromLTWH(sunCenter.dx - sunRadius, y, sunRadius * 2, h),
        bandPaint,
      );
    }
    canvas.restore();

    // Sun glow halo.
    canvas.drawCircle(
      sunCenter,
      sunRadius * 1.4,
      Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    // Stars — animated twinkle via phase.
    final starPaint = Paint()..color = Colors.white;
    double rng(int seed) => ((seed * 9301 + 49297) % 233280) / 233280.0;
    for (var i = 0; i < 60; i++) {
      final sx = rng(i * 7) * size.width;
      final sy = rng(i * 11) * horizonY * 0.7;
      final twinkle =
          (sin((phase * 2 * pi) + i.toDouble()) * 0.5 + 0.5) * 0.7 + 0.3;
      canvas.drawCircle(
        Offset(sx, sy),
        0.8 + rng(i * 13) * 0.6,
        starPaint..color = Colors.white.withValues(alpha: twinkle * 0.8),
      );
    }

    // Horizon hairline — crisp neon edge where sky meets ground.
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      Paint()
        ..color = secondary
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(0, horizonY + 1.2),
      Offset(size.width, horizonY + 1.2),
      Paint()
        ..color = secondary.withValues(alpha: 0.35)
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _SynthwaveSkyPainter old) =>
      old.phase != phase;
}

class _SpeedLines extends StatefulWidget {
  const _SpeedLines({
    required this.color,
    required this.speed,
    required this.horizonY,
    required this.width,
  });
  final Color color;
  final double speed; // m/s
  final double horizonY;
  final double width;
  @override
  State<_SpeedLines> createState() => _SpeedLinesState();
}

class _SpeedLinesState extends State<_SpeedLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    // Intensity ramps with speed; idle = subtle, highway = strong.
    final intensity = (widget.speed / 25.0).clamp(0.0, 1.0);
    if (intensity < 0.02) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SpeedLinesPainter(
          phase: _ctrl.value,
          color: widget.color,
          intensity: intensity,
          horizonY: widget.horizonY,
        ),
      ),
    );
  }
}

class _SpeedLinesPainter extends CustomPainter {
  const _SpeedLinesPainter({
    required this.phase,
    required this.color,
    required this.intensity,
    required this.horizonY,
  });
  final double phase;
  final Color color;
  final double intensity;
  final double horizonY;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Offset(size.width / 2, horizonY);
    double rng(int seed) => ((seed * 9301 + 49297) % 233280) / 233280.0;
    const count = 22;
    for (var i = 0; i < count; i++) {
      final t = ((i / count) + phase) % 1.0;
      final eased = t * t; // accelerate toward viewer
      // Pick an exit angle around the lower 2/3 of screen.
      final angle = (rng(i) * 1.6 - 0.8) + (rng(i * 3) - 0.5) * 0.4;
      final dirX = sin(angle);
      final dirY = cos(angle).abs() + 0.4;
      final maxLen = size.height * 1.4;
      final start = Offset(
        vp.dx + dirX * (maxLen * eased * 0.85),
        vp.dy + dirY * (maxLen * eased * 0.85),
      );
      final end = Offset(
        vp.dx + dirX * (maxLen * eased),
        vp.dy + dirY * (maxLen * eased),
      );
      final alpha = (intensity * (0.55 - (eased * 0.4))).clamp(0.0, 0.7);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 1.2 + eased * 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter old) =>
      old.phase != phase ||
      old.color != color ||
      old.intensity != intensity ||
      old.horizonY != horizonY;
}

class _SpeedoHud extends StatelessWidget {
  const _SpeedoHud({
    required this.theme,
    required this.speed,
    required this.unit,
  });
  final WardriveThemeData theme;
  final double speed;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final s = speed.clamp(0, 999).toInt();
    // Chrome shader — vertical sunset gradient across the digits.
    final chromeShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFFFE066),
        theme.tertiary,
        theme.accent,
        const Color(0xFFB0008C),
      ],
      stops: const [0.0, 0.35, 0.65, 1.0],
    ).createShader(const Rect.fromLTWH(0, 0, 240, 56));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.accent.withValues(alpha: 0.75),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accent.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lightning bolt accent.
          Icon(
            Icons.electric_bolt,
            color: theme.secondary,
            size: 22,
            shadows: [
              Shadow(
                color: theme.secondary.withValues(alpha: 0.85),
                blurRadius: 10,
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Chrome-gradient digits with magenta neon glow under.
          Stack(children: [
            // Glow layer.
            Text(
              s.toString().padLeft(3, '0'),
              style: TextStyle(
                color: theme.accent.withValues(alpha: 0.0),
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 44,
                height: 1.0,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                    color: theme.accent.withValues(alpha: 0.9),
                    blurRadius: 22,
                  ),
                ],
              ),
            ),
            // Chrome shader fill.
            Text(
              s.toString().padLeft(3, '0'),
              style: TextStyle(
                foreground: Paint()..shader = chromeShader,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 44,
                height: 1.0,
                letterSpacing: 4,
              ),
            ),
          ]),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit,
                style: TextStyle(
                  color: theme.secondary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 36, height: 2,
                decoration: BoxDecoration(
                  color: theme.secondary,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(
                      color: theme.secondary.withValues(alpha: 0.7),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.theme, required this.score});
  final WardriveThemeData theme;
  final int score;

  @override
  Widget build(BuildContext context) {
    final s = score.clamp(0, 999999);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.tertiary.withValues(alpha: 0.85),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.tertiary.withValues(alpha: 0.55),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'SCORE',
            style: TextStyle(
              color: theme.secondary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            s.toString().padLeft(6, '0'),
            style: TextStyle(
              color: theme.tertiary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: theme.tertiary.withValues(alpha: 0.85),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _MountainsPainter extends CustomPainter {
  const _MountainsPainter({required this.ridge, required this.glow});
  final Color ridge;
  final Color glow;

  static const _peaks = <double>[
    0.0, 0.18, 0.04, 0.40, 0.10, 0.55, 0.22, 0.72, 0.30,
    0.62, 0.42, 0.80, 0.55, 0.50, 0.66, 0.78, 0.78, 0.45,
    0.88, 0.62, 1.0, 0.30,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path();
    final baseY = size.height;
    path.moveTo(0, baseY);
    for (var i = 0; i < _peaks.length; i += 2) {
      final x = _peaks[i] * size.width;
      final y = baseY - _peaks[i + 1] * size.height;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, baseY);
    path.close();
    // Fill = deep silhouette.
    canvas.drawPath(path, Paint()..color = const Color(0xFF0A0014));
    // Underline glow.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = ridge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Crisp top edge.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = glow.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _MountainsPainter old) =>
      old.ridge != ridge || old.glow != glow;
}


class _SynthwaveGrid extends StatefulWidget {
  const _SynthwaveGrid({
    required this.color,
    required this.accent,
    required this.speed,
  });
  final Color color;
  final Color accent;
  final double speed;
  @override
  State<_SynthwaveGrid> createState() => _SynthwaveGridState();
}

class _SynthwaveGridState extends State<_SynthwaveGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SynthwaveGridPainter(
          phase: _ctrl.value,
          color: widget.color,
          accent: widget.accent,
          speed: widget.speed,
        ),
      ),
    );
  }
}

class _SynthwaveGridPainter extends CustomPainter {
  const _SynthwaveGridPainter({
    required this.phase,
    required this.color,
    required this.accent,
    required this.speed,
  });
  final double phase;
  final Color color;
  final Color accent;
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Offset(size.width / 2, 0);
    final bottomY = size.height;

    // Speed factor influences scroll rate. Idle = lazy drift; highway = rush.
    final scrollRate = 1.0 + (speed / 8.0).clamp(0.0, 4.0);
    final scrolled = (phase * scrollRate) % 1.0;

    const verticalCount = 14;
    for (var i = -verticalCount ~/ 2; i <= verticalCount ~/ 2; i++) {
      final t = i / (verticalCount / 2);
      final x = vp.dx + t * size.width * 1.4;
      final fadeT = 1.0 - (t.abs() * 0.5);
      canvas.drawLine(
        vp,
        Offset(x, bottomY),
        Paint()
          ..shader = ui.Gradient.linear(
            vp,
            Offset(x, bottomY),
            [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.45 * fadeT),
              color.withValues(alpha: 0.85 * fadeT),
            ],
            const [0.0, 0.5, 1.0],
          )
          ..strokeWidth = 0.9 + (1.0 - t.abs()) * 0.6,
      );
    }

    const horizontalCount = 12;
    for (var i = 0; i < horizontalCount; i++) {
      final t = ((i / horizontalCount) + scrolled) % 1.0;
      // Perspective y curve.
      final yT = t * t;
      final y = yT * bottomY;
      // Alpha fades at horizon and viewer extremes.
      final alpha = (sin(t * pi) * 0.65 + 0.2).clamp(0.0, 0.85);
      // Width grows with t (closer = bigger).
      final spread = size.width * (0.2 + 1.2 * t);
      final xStart = vp.dx - spread;
      final xEnd = vp.dx + spread;
      canvas.drawLine(
        Offset(xStart, y),
        Offset(xEnd, y),
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 0.8 + t * 1.4,
      );
      // Subtle glow underneath the closest lines.
      if (t > 0.6) {
        canvas.drawLine(
          Offset(xStart, y),
          Offset(xEnd, y),
          Paint()
            ..color = accent.withValues(alpha: alpha * 0.35)
            ..strokeWidth = 4.0
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SynthwaveGridPainter old) =>
      old.phase != phase ||
      old.color != color ||
      old.accent != accent ||
      old.speed != speed;
}


class _PalmStreaker extends StatefulWidget {
  const _PalmStreaker({
    required this.silhouette,
    required this.glow,
    required this.speed,
  });
  final Color silhouette;
  final Color glow;
  final double speed;
  @override
  State<_PalmStreaker> createState() => _PalmStreakerState();
}

class _PalmStreakerState extends State<_PalmStreaker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _PalmStreakerPainter(
          phase: _ctrl.value,
          silhouette: widget.silhouette,
          glow: widget.glow,
          speed: widget.speed,
        ),
      ),
    );
  }
}

class _PalmStreakerPainter extends CustomPainter {
  const _PalmStreakerPainter({
    required this.phase,
    required this.silhouette,
    required this.glow,
    required this.speed,
  });
  final double phase;
  final Color silhouette;
  final Color glow;
  final double speed;

  void _drawPalm(Canvas canvas, Offset base, double scale, Color fill) {
    // Trunk
    final trunk = Paint()..color = fill;
    canvas.drawRect(
      Rect.fromCenter(
        center: base.translate(0, -22 * scale),
        width: 3.0 * scale,
        height: 44 * scale,
      ),
      trunk,
    );
    // Fronds — 6 angled blades from top of trunk.
    final top = base.translate(0, -44 * scale);
    final fronds = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = (-pi / 2) + (i - 2.5) * 0.45;
      final dx = cos(a) * 18 * scale;
      final dy = sin(a) * 18 * scale;
      canvas.drawLine(top, top.translate(dx, dy), fronds);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Scroll rate ramps with speed. Idle = slow drift; fast = blur past.
    final scrollRate = 1.0 + (speed / 6.0).clamp(0.0, 4.0);
    const totalPalms = 6;
    for (var side = 0; side < 2; side++) {
      // side 0 = left, 1 = right.
      final isRight = side == 1;
      for (var i = 0; i < totalPalms; i++) {
        // Phase per palm — staggered so they don't all line up.
        final t = ((i / totalPalms) + phase * scrollRate +
                (isRight ? 0.5 / totalPalms : 0.0)) %
            1.0;
        // y curve: t² so palms bunch near horizon, spread near bottom.
        final yT = t * t;
        final y = yT * size.height;
        // x curve: palms drift outward from the road edge as they approach.
        final edge = isRight ? size.width : 0.0;
        final centerPull = isRight ? -1.0 : 1.0;
        final x = edge + centerPull * (size.width * 0.18) * (1.0 - t) +
            centerPull * (size.width * 0.08) * t;
        // Scale grows with distance traveled.
        final scale = 0.25 + t * 1.4;
        final alpha = (sin(t * pi) * 0.95 + 0.05).clamp(0.15, 1.0);
        // Subtle pink rim light first.
        _drawPalm(
          canvas,
          Offset(x, y),
          scale * 1.08,
          glow.withValues(alpha: alpha * 0.4),
        );
        // Solid silhouette on top.
        _drawPalm(canvas, Offset(x, y), scale, silhouette.withValues(alpha: alpha));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PalmStreakerPainter old) =>
      old.phase != phase || old.speed != speed;
}


class _CrtScanlines extends StatelessWidget {
  const _CrtScanlines();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CrtScanlinesPainter());
  }
}

class _CrtScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = const Color(0x14000000);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), dark);
    }
    // Soft chromatic-aberration vignette edge tint.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: const [
            Color(0x00000000),
            Color(0x33000000),
          ],
          stops: const [0.7, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _CrtScanlinesPainter old) => false;
}


class _CaptureFlash extends StatefulWidget {
  const _CaptureFlash({required this.color, required this.score});
  final Color color;
  final int score;
  @override
  State<_CaptureFlash> createState() => _CaptureFlashState();
}

class _CaptureFlashState extends State<_CaptureFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _lastScore = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _lastScore = widget.score;
  }

  @override
  void didUpdateWidget(covariant _CaptureFlash old) {
    super.didUpdateWidget(old);
    if (widget.score > _lastScore) {
      _lastScore = widget.score;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        if (_ctrl.value == 0 || _ctrl.value == 1) {
          return const SizedBox.shrink();
        }
        final v = _ctrl.value;
        return CustomPaint(
          painter: _CaptureFlashPainter(
            phase: v,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _CaptureFlashPainter extends CustomPainter {
  const _CaptureFlashPainter({required this.phase, required this.color});
  final double phase;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    // Two stages — initial pop then fade.
    final pop = (1.0 - phase) * (1.0 - phase); // ease-out
    final ringR = size.shortestSide * (0.1 + phase * 1.6);
    final center = Offset(size.width / 2, size.height / 2);
    // Full-screen tint pop.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.12 * pop),
    );
    // Expanding ring.
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: pop * 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: pop),
    );
  }

  @override
  bool shouldRepaint(covariant _CaptureFlashPainter old) =>
      old.phase != phase || old.color != color;
}

bool _targetEngineRunning(AppState app, WardriveTarget m) {
  bool on(Engine e) => app.getEngineState(e) != EngineState.disabled;
  return switch (m) {
    WardriveTarget.flock => on(Engine.flockBle) || on(Engine.flockWifi),
    WardriveTarget.drone => on(Engine.skySpy),
    WardriveTarget.detector => on(Engine.detector),
    WardriveTarget.wigle => on(Engine.wardrive),
    WardriveTarget.wigleFlock =>
      on(Engine.wardrive) || on(Engine.flockBle) || on(Engine.flockWifi),
  };
}

class _ScanningPill extends StatefulWidget {
  const _ScanningPill({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  State<_ScanningPill> createState() => _ScanningPillState();
}

class _ScanningPillState extends State<_ScanningPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: widget.color.withValues(alpha: 0.6), blurRadius: 6)],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(widget.label, style: TextStyle(
            color: widget.color, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _RadioRolePopup extends StatefulWidget {
  const _RadioRolePopup({
    required this.nodes,
    required this.labelFor,
    required this.initial,
  });

  final List<String> nodes;
  final String Function(String) labelFor;
  final Map<String, int> initial;

  @override
  State<_RadioRolePopup> createState() => _RadioRolePopupState();
}

class _RadioRolePopupState extends State<_RadioRolePopup> {
  late final Map<String, int> _roles = {
    for (final n in widget.nodes) n: widget.initial[n] ?? 0x03,
  };

  static const _wifiColor = Color(0xFF6B8AFF);
  static const _bleColor = Color(0xFF9B6BFF);
  static const _bothColor = Color(0xFF5AE6D6);

  static Color _radioColor(int mask) => switch (mask & 0x03) {
    0x01 => _wifiColor,
    0x02 => _bleColor,
    _ => _bothColor,
  };

  static String _maskLabel(int mask) => switch (mask & 0x03) {
    0x01 => 'WIFI',
    0x02 => 'BLE',
    _ => 'BOTH',
  };

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          const Icon(Icons.settings_input_antenna, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          Text('NODE RADIOS', style: TextStyle(
            color: t.textPrimary, fontSize: 15,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Assign each node WiFi, BLE, or Both for this wardrive. '
                'WiFi nodes split channels; BLE nodes cover BLE.',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
            ),
            ...widget.nodes.map((id) {
              final mask = _roles[id] ?? 0x03;
              final selColor = _radioColor(mask);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selColor.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9, height: 9,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: selColor,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color: selColor.withValues(alpha: 0.6), blurRadius: 6)],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.labelFor(id),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                        ),
                        Text(
                          _maskLabel(mask),
                          style: TextStyle(
                              color: selColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: WidgetStateProperty.all(
                              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          backgroundColor: WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected)
                                  ? selColor.withValues(alpha: 0.22)
                                  : Colors.transparent),
                          side: WidgetStateProperty.all(
                              BorderSide(color: selColor.withValues(alpha: 0.45))),
                        ),
                        segments: const [
                          ButtonSegment(
                              value: 0x01,
                              icon: Icon(Icons.wifi, size: 15, color: _wifiColor),
                              label: Text('WiFi')),
                          ButtonSegment(
                              value: 0x02,
                              icon: Icon(Icons.bluetooth, size: 15, color: _bleColor),
                              label: Text('BLE')),
                          ButtonSegment(
                              value: 0x03,
                              icon: Icon(Icons.sensors, size: 15, color: _bothColor),
                              label: Text('Both')),
                        ],
                        selected: {mask},
                        onSelectionChanged: (s) =>
                            setState(() => _roles[id] = s.first),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.background,
          ),
          onPressed: () => Navigator.pop(context, _roles),
          child: const Text('START'),
        ),
      ],
    );
  }
}
