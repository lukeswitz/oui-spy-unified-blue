import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/wardrive/drone_markers.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DroneMapView extends ConsumerStatefulWidget {
  const DroneMapView({super.key, required this.drones});
  final List<Detection> drones;

  @override
  ConsumerState<DroneMapView> createState() => _DroneMapViewState();
}

class _DroneMapViewState extends ConsumerState<DroneMapView> {
  final _mc = MapController();
  bool _ready = false;
  int _fitForCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsProvider).start();
    });
  }

  @override
  void dispose() {
    _mc.dispose();
    super.dispose();
  }

  List<LatLng> _allPoints() {
    final pts = <LatLng>[];
    for (final d in widget.drones) {
      final dp = droneRidPoint(d);
      if (dp != null) pts.add(dp);
      final pp = pilotRidPoint(d);
      if (pp != null) pts.add(pp);
    }
    final here = ref.read(gpsProvider).lastPosition;
    if (here != null) pts.add(LatLng(here.latitude, here.longitude));
    return pts;
  }

  void _fit() {
    if (!_ready) return;
    final pts = _allPoints();
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mc.move(pts.first, 15);
      return;
    }
    _mc.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final mapStyle = ref.watch(mapStyleProvider);
    final here = ref.watch(gpsProvider).lastPosition;
    const color = AppTheme.skySpy;

    final markers = <Marker>[];
    final tethers = <Polyline>[];
    for (final d in widget.drones) {
      final dp = droneRidPoint(d);
      if (dp != null) {
        markers.add(Marker(
          point: dp,
          width: 42,
          height: 42,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDetectionDetails(context, ref, d),
            child: DronePin(color: color, size: 26, fresh: droneIsFresh(d)),
          ),
        ));
      }
      final pp = pilotRidPoint(d);
      if (pp != null) {
        markers.add(Marker(
          point: pp,
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDetectionDetails(context, ref, d),
            child: const PilotPin(color: color, size: 22),
          ),
        ));
        if (dp != null) {
          tethers.add(Polyline(
            points: [dp, pp],
            color: color.withValues(alpha: 0.6),
            strokeWidth: 1.6,
            pattern: StrokePattern.dashed(segments: const [6, 6]),
          ));
        }
      }
    }

    if (_ready && widget.drones.length != _fitForCount) {
      _fitForCount = widget.drones.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }

    final initialCenter = here != null
        ? LatLng(here.latitude, here.longitude)
        : (markers.isNotEmpty ? markers.first.point : const LatLng(0, 0));

    return FlutterMap(
      mapController: _mc,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14,
        backgroundColor: mapStyle.isDark
            ? const Color(0xFF0A0A0A)
            : const Color(0xFFE8E8EE),
        onMapReady: () {
          _ready = true;
          _fit();
        },
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: mapStyle.urlTemplate,
          userAgentPackageName: 'tech.colonelpanic.ouispy',
          maxZoom: 19,
        ),
        if (tethers.isNotEmpty) PolylineLayer(polylines: tethers),
        if (here != null)
          MarkerLayer(markers: [
            Marker(
              point: LatLng(here.latitude, here.longitude),
              width: 16,
              height: 16,
              child: const _SelfDot(),
            ),
          ]),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}

class _SelfDot extends StatelessWidget {
  const _SelfDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.gpsGood,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gpsGood.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
