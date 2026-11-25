// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/cta2063.dart';
import 'package:oui_spy/core/models/detection.dart';

const _distance = Distance();

bool validCoord(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  if (!lat.isFinite || !lon.isFinite) return false;
  if (lat == 0 && lon == 0) return false;
  return lat.abs() <= 90 && lon.abs() <= 180;
}

double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

String droneIdOf(Detection d) {
  final id = d.odid?.uavId;
  return (id != null && id.isNotEmpty) ? id : d.macAddress;
}

class DroneReport {
  const DroneReport({
    required this.ts,
    required this.id,
    required this.mac,
    this.lat,
    this.lon,
    this.height,
    this.alt,
    this.speed,
    this.heading,
    this.status,
    this.pilotLat,
    this.pilotLon,
    this.rssi,
    this.node = '',
    this.hereLat,
    this.hereLon,
    this.maker = '',
  });

  final DateTime ts;
  final String id;
  final String mac;
  final double? lat;
  final double? lon;
  final int? height;
  final int? alt;
  final int? speed;
  final int? heading;
  final int? status;
  final double? pilotLat;
  final double? pilotLon;
  final int? rssi;
  final String node;
  final double? hereLat;
  final double? hereLon;
  final String maker;

  LatLng? get dronePoint => validCoord(lat, lon) ? LatLng(lat!, lon!) : null;
  LatLng? get pilotPoint =>
      validCoord(pilotLat, pilotLon) ? LatLng(pilotLat!, pilotLon!) : null;
  LatLng? get herePoint =>
      validCoord(hereLat, hereLon) ? LatLng(hereLat!, hereLon!) : null;

  factory DroneReport.fromDetection(Detection d) {
    final o = d.odid;
    final serial = o?.uavId;
    final maker = serial == null || serial.isEmpty
        ? ''
        : cta2063Maker(serial, idType: o?.idType) ?? '';
    return DroneReport(
      ts: d.appTimestamp,
      id: droneIdOf(d),
      mac: d.macAddress,
      lat: o?.droneLat,
      lon: o?.droneLon,
      height: o?.heightAgl,
      alt: o?.altitudeMsl,
      speed: o?.droneSpeed,
      heading: o?.droneHeading,
      status: o?.status,
      pilotLat: o?.pilotLat,
      pilotLon: o?.pilotLon,
      rssi: d.rssi,
      node: d.sourceNodeId,
      hereLat: d.latitude,
      hereLon: d.longitude,
      maker: maker,
    );
  }

  Map<String, dynamic> toJson() => {
        'ts': ts.millisecondsSinceEpoch,
        'id': id,
        'mac': mac,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (height != null) 'hagl': height,
        if (alt != null) 'alt': alt,
        if (speed != null) 'spd': speed,
        if (heading != null) 'hdg': heading,
        if (status != null) 'st': status,
        if (pilotLat != null) 'plat': pilotLat,
        if (pilotLon != null) 'plon': pilotLon,
        if (rssi != null) 'rssi': rssi,
        if (node.isNotEmpty) 'node': node,
        if (hereLat != null) 'hlat': hereLat,
        if (hereLon != null) 'hlon': hereLon,
        if (maker.isNotEmpty) 'maker': maker,
      };

  factory DroneReport.fromJson(Map<String, dynamic> j) => DroneReport(
        ts: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num).toInt()),
        id: j['id'] as String? ?? (j['mac'] as String? ?? ''),
        mac: j['mac'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        height: (j['hagl'] as num?)?.toInt(),
        alt: (j['alt'] as num?)?.toInt(),
        speed: (j['spd'] as num?)?.toInt(),
        heading: (j['hdg'] as num?)?.toInt(),
        status: (j['st'] as num?)?.toInt(),
        pilotLat: (j['plat'] as num?)?.toDouble(),
        pilotLon: (j['plon'] as num?)?.toDouble(),
        rssi: (j['rssi'] as num?)?.toInt(),
        node: j['node'] as String? ?? '',
        hereLat: (j['hlat'] as num?)?.toDouble(),
        hereLon: (j['hlon'] as num?)?.toDouble(),
        maker: j['maker'] as String? ?? '',
      );
}

const _gapGrounded = Duration(seconds: 300);
const _gapAirborne = Duration(seconds: 1500);
const _airborneHeight = 10;

Duration flightGap(DroneReport prev, DroneReport next) =>
    (prev.height ?? 0) >= _airborneHeight && (next.height ?? 0) >= _airborneHeight
        ? _gapAirborne
        : _gapGrounded;

class DroneFlight {
  DroneFlight(this.reports);

  final List<DroneReport> reports;

  String get id => reports.first.id;
  DateTime get start => reports.first.ts;
  DateTime get end => reports.last.ts;
  Duration get duration => end.difference(start);

  List<LatLng> get path =>
      [for (final r in reports) if (r.dronePoint != null) r.dronePoint!];

  LatLng? get detectionPoint {
    for (final r in reports) {
      final p = r.herePoint;
      if (p != null) return p;
    }
    return null;
  }

  LatLng? get lastDronePoint {
    for (var i = reports.length - 1; i >= 0; i--) {
      final p = reports[i].dronePoint;
      if (p != null) return p;
    }
    return null;
  }

  LatLng? get lastPilotPoint {
    for (var i = reports.length - 1; i >= 0; i--) {
      final p = reports[i].pilotPoint;
      if (p != null) return p;
    }
    return null;
  }

  double? get detectionRange {
    final here = detectionPoint;
    final drone = lastDronePoint;
    if (here == null || drone == null) return null;
    return metersBetween(here, drone);
  }

  int? get maxHeight => _maxInt((r) => r.height);
  int? get maxAlt => _maxInt((r) => r.alt);
  int? get maxSpeed => _maxInt((r) => r.speed);

  int? _maxInt(int? Function(DroneReport) f) {
    int? best;
    for (final r in reports) {
      final v = f(r);
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  double get flownMeters {
    var sum = 0.0;
    LatLng? prev;
    for (final p in path) {
      if (prev != null) sum += metersBetween(prev, p);
      prev = p;
    }
    return sum;
  }

  double? get farthestFromPilot {
    double? best;
    for (final r in reports) {
      final d = r.dronePoint;
      final p = r.pilotPoint;
      if (d == null || p == null) continue;
      final m = metersBetween(p, d);
      if (best == null || m > best) best = m;
    }
    return best;
  }
}

List<DroneFlight> splitFlights(Iterable<DroneReport> reports) {
  final sorted = [...reports]..sort((a, b) => a.ts.compareTo(b.ts));
  final flights = <DroneFlight>[];
  var current = <DroneReport>[];
  for (final r in sorted) {
    if (current.isNotEmpty &&
        r.ts.difference(current.last.ts) > flightGap(current.last, r)) {
      flights.add(DroneFlight(current));
      current = <DroneReport>[];
    }
    current.add(r);
  }
  if (current.isNotEmpty) flights.add(DroneFlight(current));
  return flights;
}

Map<String, List<DroneReport>> reportsById(Iterable<DroneReport> reports) {
  final out = <String, List<DroneReport>>{};
  for (final r in reports) {
    out.putIfAbsent(r.id, () => []).add(r);
  }
  for (final l in out.values) {
    l.sort((a, b) => a.ts.compareTo(b.ts));
  }
  return out;
}

const droneLiveWindow = Duration(seconds: 60);
const odidStatusAirborne = 2;

class DroneSummary {
  DroneSummary({required this.id, required this.reports, required this.now});

  final String id;
  final List<DroneReport> reports;
  final DateTime now;

  DroneReport get last => reports.last;
  DroneReport get first => reports.first;
  Set<String> get macs => {for (final r in reports) r.mac};
  bool get live => now.difference(last.ts) <= droneLiveWindow;
  bool get airborne => live && last.status == odidStatusAirborne;
  bool get hasPilot => reports.any((r) => r.pilotPoint != null);
  int? get topHeight {
    int? best;
    for (final r in reports) {
      final v = r.height;
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  String get maker {
    for (var i = reports.length - 1; i >= 0; i--) {
      if (reports[i].maker.isNotEmpty) return reports[i].maker;
    }
    return '';
  }

  List<DroneFlight> get flights => splitFlights(reports);
}

class DroneCounts {
  const DroneCounts({
    required this.live,
    required this.airborne,
    required this.pilots,
    required this.topHeight,
    required this.inWindow,
  });

  final int live;
  final int airborne;
  final int pilots;
  final int? topHeight;
  final int inWindow;
}

List<DroneSummary> summarizeDrones(Iterable<DroneReport> reports, DateTime now) {
  final out = [
    for (final e in reportsById(reports).entries)
      DroneSummary(id: e.key, reports: e.value, now: now),
  ];
  out.sort((a, b) {
    if (a.airborne != b.airborne) return a.airborne ? -1 : 1;
    return b.last.ts.compareTo(a.last.ts);
  });
  return out;
}

DroneCounts countDrones(List<DroneSummary> drones) {
  int? top;
  for (final d in drones) {
    final h = d.topHeight;
    if (h != null && (top == null || h > top)) top = h;
  }
  return DroneCounts(
    live: drones.where((d) => d.live).length,
    airborne: drones.where((d) => d.airborne).length,
    pilots: drones.where((d) => d.hasPilot).length,
    topHeight: top,
    inWindow: drones.length,
  );
}
