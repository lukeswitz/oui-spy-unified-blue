import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

class AircraftPhoto {
  const AircraftPhoto(this.thumb, this.large, this.by, this.link);
  final String? thumb;
  final String? large;
  final String? by;
  final String? link;

  static final Map<String, Future<AircraftPhoto?>> _cache = {};
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    responseType: ResponseType.json,
  ));

  static Future<AircraftPhoto?> forIcao(String icao) {
    final key = icao.toUpperCase().trim();
    if (key.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(key, () => _fetch(key));
  }

  static Future<AircraftPhoto?> _fetch(String icao) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
          'https://api.planespotters.net/pub/photos/hex/$icao');
      final photos = (r.data?['photos'] as List?) ?? const [];
      if (photos.isEmpty) return null;
      final p = photos.first as Map<String, dynamic>;
      String? src(String k) => (p[k] as Map<String, dynamic>?)?['src'] as String?;
      return AircraftPhoto(src('thumbnail'), src('thumbnail_large') ?? src('thumbnail'),
          p['photographer'] as String?, p['link'] as String?);
    } on Exception {
      // planespotters unreachable or no photo for this hex: show placeholder, non-fatal.
      return null;
    }
  }
}

class AdsbList extends StatelessWidget {
  const AdsbList({super.key, required this.aircraft, required this.t});
  final List<AdsbAircraft> aircraft;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final list = [...aircraft]
      ..sort((a, b) =>
          (b.lastSeen ?? b.firstSeen).compareTo(a.lastSeen ?? a.firstSeen));
    if (list.isEmpty) {
      return Center(
        child: Text('No aircraft yet — listening on 1090 MHz',
            style: TextStyle(color: t.textDim, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: list.length,
      itemBuilder: (_, i) => _AdsbCard(a: list[i], t: t),
    );
  }
}

class AdsbMap extends ConsumerStatefulWidget {
  const AdsbMap({super.key, required this.aircraft, required this.t});
  final List<AdsbAircraft> aircraft;
  final ResolvedTheme t;

  @override
  ConsumerState<AdsbMap> createState() => _AdsbMapState();
}

class _AdsbMapState extends ConsumerState<AdsbMap> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final mapStyle = ref.watch(mapStyleProvider);
    final accent = AppTheme.themed(AppTheme.skySpy);
    final fixed = widget.aircraft.where((a) => a.hasFix).toList();
    if (fixed.isEmpty) {
      return Center(
        child: Text('No aircraft with a position fix yet',
            style: TextStyle(color: widget.t.textDim, fontSize: 13)),
      );
    }
    final polylines = <Polyline>[
      for (final a in fixed)
        if (a.track.length >= 2)
          Polyline(
            points: [for (final p in a.track) LatLng(p.$1, p.$2)],
            color: accent.withValues(alpha: 0.7),
            strokeWidth: 2,
          ),
    ];
    final markers = <Marker>[
      for (final a in fixed)
        Marker(
          point: LatLng(a.lat!, a.lon!),
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () => _detail(a),
            child: Transform.rotate(
              angle: a.heading * math.pi / 180,
              child: Icon(Icons.navigation, color: accent, size: 24),
            ),
          ),
        ),
    ];
    var minLat = fixed.first.lat!, maxLat = fixed.first.lat!;
    var minLon = fixed.first.lon!, maxLon = fixed.first.lon!;
    for (final a in fixed) {
      minLat = math.min(minLat, a.lat!);
      maxLat = math.max(maxLat, a.lat!);
      minLon = math.min(minLon, a.lon!);
      maxLon = math.max(maxLon, a.lon!);
    }
    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && fixed.length > 1) {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
          padding: const EdgeInsets.all(40),
        ));
      }
    });
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: fixed.length == 1 ? 11 : 9,
        backgroundColor: mapStyle.isDark ? Colors.black : Colors.white,
      ),
      children: [
        mapTileLayer(mapStyle),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
        mapAttribution(mapStyle),
      ],
    );
  }

  void _detail(AdsbAircraft a) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.t.surface,
      isScrollControlled: true,
      builder: (_) => _AdsbDetail(a: a, t: widget.t),
    );
  }
}

class _AdsbCard extends StatelessWidget {
  const _AdsbCard({required this.a, required this.t});
  final AdsbAircraft a;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.themed(AppTheme.skySpy);
    final title = a.callsign.trim().isNotEmpty ? a.callsign.trim() : a.icao.toUpperCase();
    return InkWell(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: t.surfaceLight,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 96,
              height: 72,
              child: _Thumb(icao: a.icao, t: t, accent: accent),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(title,
                            style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 15,
                                fontFamily: AppTheme.mono,
                                fontWeight: FontWeight.w700)),
                      ),
                      Text(a.icao.toUpperCase(),
                          style: TextStyle(
                              color: accent, fontSize: 11, fontFamily: AppTheme.mono)),
                    ]),
                    const SizedBox(height: 4),
                    Text(_line(a),
                        style: TextStyle(color: t.textSecondary, fontSize: 12)),
                    if (a.hasFix)
                      Text('${a.lat!.toStringAsFixed(4)}, ${a.lon!.toStringAsFixed(4)}',
                          style: TextStyle(color: t.textDim, fontSize: 11))
                    else
                      Text('no position fix',
                          style: TextStyle(color: t.textDim, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _line(AdsbAircraft a) {
    final parts = <String>[];
    if (a.altFt != 0) parts.add('${a.altFt} ft');
    if (a.velocityKt != 0) parts.add('${a.velocityKt} kt');
    if (a.heading != 0) parts.add('${a.heading}°');
    return parts.isEmpty ? 'no telemetry yet' : parts.join('  ·  ');
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      isScrollControlled: true,
      builder: (ctx) => _AdsbDetail(a: a, t: t),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.icao, required this.t, required this.accent});
  final String icao;
  final ResolvedTheme t;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: t.fill,
      child: Icon(Icons.flight, color: accent.withValues(alpha: 0.6), size: 28),
    );
    return FutureBuilder<AircraftPhoto?>(
      future: AircraftPhoto.forIcao(icao),
      builder: (context, snap) {
        final url = snap.data?.thumb;
        if (url == null) return placeholder;
        return Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (c, child, p) =>
                p == null ? child : Container(color: t.fill));
      },
    );
  }
}

class _AdsbDetail extends StatelessWidget {
  const _AdsbDetail({required this.a, required this.t});
  final AdsbAircraft a;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.themed(AppTheme.skySpy);
    final title = a.callsign.trim().isNotEmpty ? a.callsign.trim() : a.icao.toUpperCase();
    final rows = <(String, String)>[
      ('ICAO', a.icao.toUpperCase()),
      if (a.callsign.trim().isNotEmpty) ('Callsign', a.callsign.trim()),
      if (a.altFt != 0) ('Altitude', '${a.altFt} ft'),
      if (a.velocityKt != 0) ('Ground speed', '${a.velocityKt} kt'),
      if (a.heading != 0) ('Heading', '${a.heading}°'),
      if (a.hasFix)
        ('Position', '${a.lat!.toStringAsFixed(5)}, ${a.lon!.toStringAsFixed(5)}'),
      ('First seen', _hms(a.firstSeen)),
      if (a.lastSeen != null) ('Last seen', _hms(a.lastSeen!)),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.fill,
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(children: [
              Icon(Icons.flight, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontFamily: AppTheme.mono,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: Icon(Icons.close, color: t.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<AircraftPhoto?>(
                    future: AircraftPhoto.forIcao(a.icao),
                    builder: (context, snap) {
                      final p = snap.data;
                      final url = p?.large ?? p?.thumb;
                      if (url == null) return const SizedBox.shrink();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRect(
                          child: Image.network(url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        ),
                        if ((p?.by ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('© ${p!.by} / planespotters.net',
                                style: TextStyle(color: t.textDim, fontSize: 10)),
                          ),
                        const SizedBox(height: 12),
                      ]);
                    },
                  ),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(r.$1,
                                style: TextStyle(color: t.textDim, fontSize: 13)),
                          ),
                          Expanded(
                            child: Text(r.$2,
                                style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 13,
                                    fontFamily: AppTheme.mono)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hms(DateTime d) {
    final l = d.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(l.hour)}:${p(l.minute)}:${p(l.second)}';
  }
}
