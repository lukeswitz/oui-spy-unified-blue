import 'dart:math' as math;

class TrackPoint {
  final int atMs;
  final double lat;
  final double lon;
  const TrackPoint(this.atMs, this.lat, this.lon);
}

class CellSighting {
  final String mac;
  final String name;
  final bool ble;
  final double lat;
  final double lon;
  final int lastMs;
  const CellSighting(this.mac, this.name, this.ble, this.lat, this.lon, this.lastMs);
}

class Stop {
  final double lat;
  final double lon;
  final int startMs;
  final int endMs;
  const Stop(this.lat, this.lon, this.startMs, this.endMs);
}

class StopsHit {
  final String mac;
  final String name;
  final bool ble;
  final int stops;
  final int lastMs;
  const StopsHit(this.mac, this.name, this.ble, this.stops, this.lastMs);
}

class StopsReport {
  static const windowMs = 7 * 24 * 3600 * 1000;
  static const cellDeg = 0.0015;
  static const stayM = 150.0;
  static const dwellMs = 5 * 60 * 1000;
  static const gapMs = 3 * 60 * 1000;
  static const apartM = 500.0;
  static const heardAtStopM = 200.0;
  static const minStops = 2;

  static double meters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }

  static List<Stop> stops(List<TrackPoint> track) {
    final sorted = [...track]..sort((a, b) => a.atMs.compareTo(b.atMs));
    final raw = <Stop>[];
    var run = <TrackPoint>[];
    void close() {
      if (run.length >= 2 && run.last.atMs - run.first.atMs >= dwellMs) {
        final lat = run.map((p) => p.lat).reduce((a, b) => a + b) / run.length;
        final lon = run.map((p) => p.lon).reduce((a, b) => a + b) / run.length;
        raw.add(Stop(lat, lon, run.first.atMs, run.last.atMs));
      }
      run = [];
    }

    for (final p in sorted) {
      if (run.isNotEmpty &&
          (p.atMs - run.last.atMs > gapMs || meters(run.first.lat, run.first.lon, p.lat, p.lon) > stayM)) {
        close();
      }
      run.add(p);
    }
    close();

    final merged = <Stop>[];
    for (final s in raw) {
      final i = merged.indexWhere((m) => meters(m.lat, m.lon, s.lat, s.lon) <= apartM);
      if (i < 0) {
        merged.add(s);
      } else {
        final m = merged[i];
        merged[i] = Stop(m.lat, m.lon, math.min(m.startMs, s.startMs), math.max(m.endMs, s.endMs));
      }
    }
    return merged;
  }

  static List<StopsHit> build(List<TrackPoint> track, List<CellSighting> cells) {
    final places = stops(track);
    if (places.length < minStops) return const [];
    final byMac = <String, (String, bool, Set<int>, int)>{};
    for (final c in cells) {
      for (var i = 0; i < places.length; i++) {
        if (meters(places[i].lat, places[i].lon, c.lat, c.lon) > heardAtStopM) continue;
        final cur = byMac[c.mac];
        final name = cur == null || cur.$1.isEmpty ? c.name : cur.$1;
        final seen = cur?.$3 ?? <int>{};
        seen.add(i);
        byMac[c.mac] = (name, c.ble, seen, math.max(cur?.$4 ?? 0, c.lastMs));
      }
    }
    final out = [
      for (final e in byMac.entries)
        if (e.value.$3.length >= minStops) StopsHit(e.key, e.value.$1, e.value.$2, e.value.$3.length, e.value.$4),
    ]..sort((a, b) => b.stops != a.stops ? b.stops.compareTo(a.stops) : b.lastMs.compareTo(a.lastMs));
    return out;
  }
}
