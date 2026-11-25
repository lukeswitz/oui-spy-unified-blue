// Copyright (c) 2026 Luke Switzer
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const double kTriDefaultP0 = -59;
const double kTriDefaultN = 2.7;
const Duration kTriWindow = Duration(seconds: 60);
const double kTriGoodErrorM = 25;

/// Log-distance path loss: RSSI = p0 - 10 n log10(d), solved for d in meters.
double rssiToDistanceM(num rssi, {double p0 = kTriDefaultP0, double n = kTriDefaultN}) =>
    math.pow(10, (p0 - rssi) / (10 * n)).toDouble();

class TriRange {
  const TriRange(this.nodeId, this.at, this.distM);
  final String nodeId;
  final LatLng at;
  final double distM;
}

class TriFix {
  const TriFix({required this.at, required this.errM, required this.ranges});
  final LatLng at;
  final double errM;
  final List<TriRange> ranges;
}

class TriDeviceFix {
  const TriDeviceFix({required this.mac, required this.fix, required this.heardAt});
  final String mac;
  final TriFix fix;
  final DateTime heardAt;
}

const double _mPerDegLat = 110540.0;
const double _mPerDegLonEq = 111320.0;

/// Weighted least squares on the range residuals |x - p_i| - d_i, weights 1/d_i^2,
/// solved by Levenberg-Marquardt from the weighted centroid. errM is the RMS residual.
TriFix? solveTriangulation(List<TriRange> ranges) {
  final rs = [
    for (final r in ranges)
      if (r.distM.isFinite && r.distM > 0 && r.at.latitude.isFinite && r.at.longitude.isFinite) r,
  ];
  if (rs.length < 3) return null;
  final lat0 = rs.fold<double>(0, (a, r) => a + r.at.latitude) / rs.length;
  final lon0 = rs.fold<double>(0, (a, r) => a + r.at.longitude) / rs.length;
  final kx = _mPerDegLonEq * math.cos(lat0 * math.pi / 180);
  final n = rs.length;
  final px = [for (final r in rs) (r.at.longitude - lon0) * kx];
  final py = [for (final r in rs) (r.at.latitude - lat0) * _mPerDegLat];
  final d = [for (final r in rs) r.distM];
  final w = [for (final r in rs) 1 / (math.max(r.distM, 1.0) * math.max(r.distM, 1.0))];

  var sw = 0.0, x = 0.0, y = 0.0;
  for (var i = 0; i < n; i++) {
    sw += w[i];
    x += w[i] * px[i];
    y += w[i] * py[i];
  }
  x /= sw;
  y /= sw;

  double cost(double cx, double cy) {
    var c = 0.0;
    for (var i = 0; i < n; i++) {
      final r = math.sqrt(math.pow(cx - px[i], 2) + math.pow(cy - py[i], 2)) - d[i];
      c += w[i] * r * r;
    }
    return c;
  }

  var lambda = 1e-3;
  var current = cost(x, y);
  var converged = false;
  for (var iter = 0; iter < 100 && !converged; iter++) {
    var a11 = 0.0, a12 = 0.0, a22 = 0.0, g1 = 0.0, g2 = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x - px[i];
      final dy = y - py[i];
      final rho = math.sqrt(dx * dx + dy * dy);
      final jx = rho < 1e-9 ? 0.0 : dx / rho;
      final jy = rho < 1e-9 ? 0.0 : dy / rho;
      final r = rho - d[i];
      a11 += w[i] * jx * jx;
      a12 += w[i] * jx * jy;
      a22 += w[i] * jy * jy;
      g1 += w[i] * jx * r;
      g2 += w[i] * jy * r;
    }
    var improved = false;
    for (var tries = 0; tries < 12; tries++) {
      final b11 = a11 + lambda * (a11 + 1e-12);
      final b22 = a22 + lambda * (a22 + 1e-12);
      final det = b11 * b22 - a12 * a12;
      if (det.abs() < 1e-300) {
        lambda *= 10;
        continue;
      }
      final sx = -(b22 * g1 - a12 * g2) / det;
      final sy = -(b11 * g2 - a12 * g1) / det;
      final next = cost(x + sx, y + sy);
      if (next.isFinite && next <= current) {
        final step = math.sqrt(sx * sx + sy * sy);
        x += sx;
        y += sy;
        current = next;
        lambda = math.max(lambda / 3, 1e-12);
        improved = true;
        if (step < 1e-6) converged = true;
        break;
      }
      lambda *= 4;
    }
    if (!improved) break;
  }

  var sq = 0.0;
  for (var i = 0; i < n; i++) {
    final r = math.sqrt(math.pow(x - px[i], 2) + math.pow(y - py[i], 2)) - d[i];
    sq += r * r;
  }
  final rms = math.sqrt(sq / n);
  final lat = lat0 + y / _mPerDegLat;
  final lon = lon0 + x / kx;
  if (!rms.isFinite || !lat.isFinite || !lon.isFinite) return null;
  return TriFix(at: LatLng(lat, lon), errM: rms, ranges: rs);
}

class _Sample {
  const _Sample(this.ms, this.rssi);
  final int ms;
  final int rssi;
}

/// Keeps the last [window] of RSSI per device and node, and fixes devices heard by 3+ placed nodes.
class TriangulationEngine {
  TriangulationEngine({this.window = kTriWindow, this.maxSamples = 20, this.maxDevices = 4000});

  final Duration window;
  final int maxSamples;
  final int maxDevices;
  final Map<String, Map<String, List<_Sample>>> _samples = {};

  int get deviceCount => _samples.length;

  void add(String mac, String nodeId, int rssi, DateTime at) {
    if (mac.isEmpty || nodeId.isEmpty) return;
    final ms = at.millisecondsSinceEpoch;
    final cutoff = ms - window.inMilliseconds;
    final key = mac.toUpperCase();
    if (!_samples.containsKey(key) && _samples.length >= maxDevices) prune(at);
    final list = (_samples[key] ??= {})[nodeId] ??= [];
    list.removeWhere((s) => s.ms < cutoff);
    list.add(_Sample(ms, rssi));
    if (list.length > maxSamples) list.removeRange(0, list.length - maxSamples);
  }

  void prune(DateTime now) {
    final cutoff = now.millisecondsSinceEpoch - window.inMilliseconds;
    _samples.removeWhere((_, nodes) {
      nodes.removeWhere((_, list) {
        list.removeWhere((s) => s.ms < cutoff);
        return list.isEmpty;
      });
      return nodes.isEmpty;
    });
  }

  List<TriDeviceFix> compute(
    DateTime now,
    Map<String, LatLng> placed, {
    double p0 = kTriDefaultP0,
    double n = kTriDefaultN,
  }) {
    prune(now);
    final out = <TriDeviceFix>[];
    for (final e in _samples.entries) {
      final ranges = <TriRange>[];
      var newest = 0;
      for (final node in e.value.entries) {
        final at = placed[node.key];
        if (at == null || node.value.isEmpty) continue;
        final mean = node.value.fold<int>(0, (a, s) => a + s.rssi) / node.value.length;
        ranges.add(TriRange(node.key, at, rssiToDistanceM(mean, p0: p0, n: n)));
        for (final s in node.value) {
          if (s.ms > newest) newest = s.ms;
        }
      }
      if (ranges.length < 3) continue;
      final fix = solveTriangulation(ranges);
      if (fix == null) continue;
      out.add(TriDeviceFix(
        mac: e.key,
        fix: fix,
        heardAt: DateTime.fromMillisecondsSinceEpoch(newest),
      ));
    }
    out.sort((a, b) => b.heardAt.compareTo(a.heardAt));
    return out;
  }
}
