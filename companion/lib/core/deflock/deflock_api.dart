import 'dart:io';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// Plain lat/lon box so the core layer stays free of map-widget types.
class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;
}

class DeflockApiException implements Exception {
  DeflockApiException(this.message, {this.retryAfter});
  final String message;
  final Duration? retryAfter;
  @override
  String toString() => message;
}

/// One `man_made=surveillance` + `surveillance:type=ALPR` node from OSM —
/// the same dataset DeFlock renders.
class AlprNode {
  const AlprNode({
    required this.id,
    required this.position,
    this.operator,
    this.direction,
    this.zone,
    this.manufacturer,
  });

  final int id;
  final LatLng position;
  final String? operator;
  final String? direction;
  final String? zone;
  final String? manufacturer;

  bool get isFlock {
    final o = (operator ?? '').toLowerCase();
    final m = (manufacturer ?? '').toLowerCase();
    return o.contains('flock') || m.contains('flock');
  }

  String get label {
    final o = operator?.trim();
    if (o != null && o.isNotEmpty) return o;
    final m = manufacturer?.trim();
    if (m != null && m.isNotEmpty) return m;
    return 'ALPR';
  }

  String get osmUrl => 'https://www.openstreetmap.org/node/$id';

  static AlprNode? fromElement(Map<String, dynamic> e) {
    final lat = e['lat'];
    final lon = e['lon'];
    final id = e['id'];
    if (lat is! num || lon is! num || id is! num) return null;
    final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    String? tag(String k) {
      final v = tags[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return AlprNode(
      id: id.toInt(),
      position: LatLng(lat.toDouble(), lon.toDouble()),
      operator: tag('operator'),
      direction: tag('camera:direction') ?? tag('direction'),
      zone: tag('surveillance:zone'),
      manufacturer: tag('manufacturer'),
    );
  }
}

/// Read-only Overpass client for ALPR nodes. Queries run only when the user
/// turns the layer on or asks for a prefetch — never on app start.
class DeflockApi {
  DeflockApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {
                HttpHeaders.userAgentHeader:
                    'oui-spy-companion (github.com/lukeswitz/oui-spy-unified-blue)',
              },
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;

  static const List<String> endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static String query(GeoBounds b) {
    final south = b.south.toStringAsFixed(5);
    final west = b.west.toStringAsFixed(5);
    final north = b.north.toStringAsFixed(5);
    final east = b.east.toStringAsFixed(5);
    final box = '($south,$west,$north,$east)';
    final base = 'node["man_made"="surveillance"]["surveillance:type"=';
    return '[out:json][timeout:60];'
        '($base"ALPR"]$box;$base"alpr"]$box;);'
        'out body;';
  }

  /// ALPR nodes inside [bounds]. Falls through to the next mirror on 429/5xx.
  Future<List<AlprNode>> fetchBounds(GeoBounds bounds) async {
    DeflockApiException? last;
    for (final url in endpoints) {
      try {
        return await _fetchFrom(url, bounds);
      } on DeflockApiException catch (e) {
        last = e;
      }
    }
    throw last ?? DeflockApiException('Overpass unreachable');
  }

  Future<List<AlprNode>> _fetchFrom(String url, GeoBounds bounds) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>(
        url,
        data: {'data': query(bounds)},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      final host = Uri.parse(url).host;
      final detail = e.message ?? e.error?.toString() ?? '';
      throw DeflockApiException(
          'Overpass $host ${e.type.name}${detail.isEmpty ? '' : ': $detail'}');
    }

    final code = resp.statusCode ?? 0;
    if (code == 429) {
      throw DeflockApiException('Overpass rate limited — try again shortly',
          retryAfter: const Duration(seconds: 30));
    }
    if (code != 200) {
      throw DeflockApiException('Overpass HTTP $code');
    }

    final data = resp.data;
    final map = data is Map ? data.cast<String, dynamic>() : null;
    final elements = map?['elements'];
    if (elements is! List) {
      throw DeflockApiException('Overpass returned no element list');
    }

    final nodes = <AlprNode>[];
    for (final e in elements) {
      if (e is Map) {
        final n = AlprNode.fromElement(e.cast<String, dynamic>());
        if (n != null) nodes.add(n);
      }
    }
    return nodes;
  }
}
