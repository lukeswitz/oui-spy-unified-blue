// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/painting.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_tags.dart';

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _cell(Object? v) {
  final s = v == null ? '' : '$v';
  if (s.contains(RegExp('[",\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _iso(DateTime t) => t.toUtc().toIso8601String();

String _kmlColor(DroneTag? tag) {
  final c = tag?.color ?? const Color(0xFF9AA0A6);
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return 'ff${h(c.b)}${h(c.g)}${h(c.r)}';
}

/// Drone reports in the export formats the Drones page offers.
class DroneExport {
  const DroneExport._();

  static const csvHeader = 'time_utc,id,mac,maker,tag,lat,lon,height_agl_m,'
      'alt_msl_m,speed_ms,heading_deg,status,pilot_lat,pilot_lon,rssi_dbm,'
      'node,detected_from_lat,detected_from_lon,range_to_drone_m';

  static String csv(List<DroneReport> reports,
      {Map<String, DroneTag> tags = const {}}) {
    final b = StringBuffer()..writeln(csvHeader);
    final sorted = [...reports]..sort((a, b) => a.ts.compareTo(b.ts));
    for (final r in sorted) {
      final here = r.herePoint;
      final drone = r.dronePoint;
      final range = here != null && drone != null
          ? metersBetween(here, drone).round()
          : null;
      b.writeln([
        _iso(r.ts),
        r.id,
        r.mac.toUpperCase(),
        r.maker,
        tags[r.id]?.name ?? '',
        r.lat,
        r.lon,
        r.height,
        r.alt,
        r.speed,
        r.heading,
        r.status,
        r.pilotLat,
        r.pilotLon,
        r.rssi,
        r.node,
        r.hereLat,
        r.hereLon,
        range,
      ].map(_cell).join(','));
    }
    return b.toString();
  }

  static String kml(List<DroneReport> reports,
      {Map<String, DroneTag> tags = const {}, String title = 'OUI-SPY drones'}) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
      ..writeln('<Document><name>${_xml(title)}</name>');
    for (final tag in [null, ...DroneTag.values]) {
      b.writeln('<Style id="${tag?.name ?? 'untagged'}">'
          '<LineStyle><color>${_kmlColor(tag)}</color><width>3</width></LineStyle>'
          '</Style>');
    }
    final byId = reportsById(reports);
    for (final e in byId.entries) {
      final tag = tags[e.key];
      final style = '#${tag?.name ?? 'untagged'}';
      final flights = splitFlights(e.value);
      b.writeln('<Folder><name>${_xml(e.key)}</name>');
      for (var i = 0; i < flights.length; i++) {
        final f = flights[i];
        final label = '${_xml(e.key)} flight ${i + 1}';
        final path = f.path;
        if (path.length >= 2) {
          b
            ..writeln('<Placemark><name>$label</name><styleUrl>$style</styleUrl>')
            ..writeln('<TimeSpan><begin>${_iso(f.start)}</begin><end>${_iso(f.end)}</end></TimeSpan>')
            ..writeln('<LineString><altitudeMode>clampToGround</altitudeMode><coordinates>')
            ..writeln(path.map((p) => '${p.longitude},${p.latitude},0').join(' '))
            ..writeln('</coordinates></LineString></Placemark>');
        }
        final last = f.lastDronePoint;
        if (last != null) {
          b.writeln('<Placemark><name>$label end</name>'
              '<TimeStamp><when>${_iso(f.end)}</when></TimeStamp>'
              '<Point><coordinates>${last.longitude},${last.latitude},0</coordinates></Point></Placemark>');
        }
        final pilot = f.lastPilotPoint;
        if (pilot != null) {
          b.writeln('<Placemark><name>$label pilot</name>'
              '<Point><coordinates>${pilot.longitude},${pilot.latitude},0</coordinates></Point></Placemark>');
        }
        final here = f.detectionPoint;
        if (here != null) {
          b.writeln('<Placemark><name>$label detection location</name>'
              '<TimeStamp><when>${_iso(f.start)}</when></TimeStamp>'
              '<Point><coordinates>${here.longitude},${here.latitude},0</coordinates></Point></Placemark>');
          if (last != null) {
            final range = f.detectionRange?.round();
            b.writeln('<Placemark><name>$label range${range == null ? '' : ' $range m'}</name>'
                '<styleUrl>$style</styleUrl>'
                '<LineString><coordinates>${here.longitude},${here.latitude},0 '
                '${last.longitude},${last.latitude},0</coordinates></LineString></Placemark>');
          }
        }
      }
      b.writeln('</Folder>');
    }
    b.writeln('</Document></kml>');
    return b.toString();
  }
}
