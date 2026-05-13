import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/app_database.dart';

/// Runtime geofence exclusion filter for wardrive modes.
/// Loads active geofences marked [excludeFromWardrive] and checks whether
/// a GPS coordinate falls inside any of them.
class GeofenceFilter extends ChangeNotifier {
  GeofenceFilter(this._db) {
    reload();
  }

  final AppDatabase _db;
  List<_GeofenceZone> _zones = [];

  /// Number of active exclusion zones.
  int get zoneCount => _zones.length;

  /// Reload exclusion geofences from DB. Call on start and when user edits zones.
  Future<void> reload() async {
    final rows = await _db.getWardriveExclusionGeofences();
    _zones = rows.map(_GeofenceZone.fromGeofence).toList();
    notifyListeners();
  }

  /// Returns true if [lat],[lon] is inside ANY exclusion geofence.
  /// Fast path: returns false immediately when no zones configured.
  bool isExcluded(double lat, double lon) {
    if (_zones.isEmpty) return false;
    for (final zone in _zones) {
      if (zone.contains(lat, lon)) return true;
    }
    return false;
  }

  /// Check with nullable coords — returns false if coords are null.
  bool isExcludedNullable(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    return isExcluded(lat, lon);
  }
}

/// Internal representation of a parsed geofence zone for fast runtime checks.
sealed class _GeofenceZone {
  bool contains(double lat, double lon);

  factory _GeofenceZone.fromGeofence(Geofence g) {
    final type = g.zoneType;
    if (type == 'polygon' && g.polygonJson != null) {
      return _PolygonZone._parse(g.polygonJson!);
    }
    if (type == 'corridor' && g.corridorJson != null) {
      return _CorridorZone._parse(g.corridorJson!);
    }
    // Default: circle
    return _CircleZone(
      centerLat: g.centerLat ?? 0,
      centerLon: g.centerLon ?? 0,
      radiusM: g.radiusM ?? 0,
    );
  }
}

class _CircleZone implements _GeofenceZone {
  _CircleZone({
    required this.centerLat,
    required this.centerLon,
    required this.radiusM,
  });

  final double centerLat;
  final double centerLon;
  final double radiusM;

  @override
  bool contains(double lat, double lon) {
    final distM = _haversineMeters(centerLat, centerLon, lat, lon);
    return distM <= radiusM;
  }
}

class _PolygonZone implements _GeofenceZone {
  _PolygonZone(this.points);

  final List<_LatLon> points;

  factory _PolygonZone._parse(String json) {
    final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    final pts = list
        .map((p) => _LatLon(
              (p['lat'] as num).toDouble(),
              (p['lon'] as num).toDouble(),
            ))
        .toList();
    return _PolygonZone(pts);
  }

  /// Ray-casting algorithm for point-in-polygon.
  @override
  bool contains(double lat, double lon) {
    if (points.length < 3) return false;
    bool inside = false;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      final pi = points[i];
      final pj = points[j];
      if ((pi.lon > lon) != (pj.lon > lon) &&
          lat < (pj.lat - pi.lat) * (lon - pi.lon) / (pj.lon - pi.lon) + pi.lat) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }
}

class _CorridorZone implements _GeofenceZone {
  _CorridorZone(this.segments, this.widthM);

  final List<_LatLon> segments;
  final double widthM;

  factory _CorridorZone._parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final width = (data['width_m'] as num?)?.toDouble() ?? 100.0;
    final pts = (data['points'] as List).cast<Map<String, dynamic>>();
    final segments = pts
        .map((p) => _LatLon(
              (p['lat'] as num).toDouble(),
              (p['lon'] as num).toDouble(),
            ))
        .toList();
    return _CorridorZone(segments, width);
  }

  /// Point is within corridor if distance to any segment <= widthM/2.
  @override
  bool contains(double lat, double lon) {
    if (segments.length < 2) return false;
    final halfW = widthM / 2;
    for (int i = 0; i < segments.length - 1; i++) {
      final d = _distToSegmentMeters(
        lat, lon,
        segments[i].lat, segments[i].lon,
        segments[i + 1].lat, segments[i + 1].lon,
      );
      if (d <= halfW) return true;
    }
    return false;
  }
}

class _LatLon {
  const _LatLon(this.lat, this.lon);
  final double lat;
  final double lon;
}

// -- Geo math helpers --

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // Earth radius in meters
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

double _toRad(double deg) => deg * math.pi / 180;

/// Approximate distance from point to line segment in meters.
/// Uses flat-earth approximation (fast, accurate at geofence scale <10km).
double _distToSegmentMeters(
  double pLat, double pLon,
  double aLat, double aLon,
  double bLat, double bLon,
) {
  // Convert to approximate meters using lat midpoint
  final cosLat = math.cos(_toRad((aLat + bLat) / 2));
  final mPerDegLat = 111320.0;
  final mPerDegLon = 111320.0 * cosLat;

  final px = (pLon - aLon) * mPerDegLon;
  final py = (pLat - aLat) * mPerDegLat;
  final bx = (bLon - aLon) * mPerDegLon;
  final by = (bLat - aLat) * mPerDegLat;

  final dot = px * bx + py * by;
  final lenSq = bx * bx + by * by;
  if (lenSq == 0) return math.sqrt(px * px + py * py);

  final t = (dot / lenSq).clamp(0.0, 1.0);
  final projX = t * bx;
  final projY = t * by;
  final dx = px - projX;
  final dy = py - projY;
  return math.sqrt(dx * dx + dy * dy);
}

final geofenceFilterProvider = ChangeNotifierProvider<GeofenceFilter>((ref) {
  final db = ref.watch(databaseProvider);
  return GeofenceFilter(db);
});
