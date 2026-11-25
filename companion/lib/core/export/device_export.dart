// Copyright (c) 2026 Luke Switzer
import 'dart:convert';

import 'package:oui_spy/core/export/detections_csv.dart';
import 'package:oui_spy/core/models/detection.dart';

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Every sighting of one device, in the export formats the app offers.
class DeviceExport {
  const DeviceExport._();

  static String csv(List<Detection> rows) => DetectionsCsv.generate(rows);

  static String json(List<Detection> rows, {String name = '', String group = '', String notes = ''}) =>
      const JsonEncoder.withIndent('  ').convert({
        if (rows.isNotEmpty) 'mac': rows.first.macAddress.toUpperCase(),
        if (name.isNotEmpty) 'name': name,
        if (group.isNotEmpty) 'group': group,
        if (notes.isNotEmpty) 'notes': notes,
        'sightings': [
          for (final d in rows)
            {
              'timestamp': d.appTimestamp.toUtc().toIso8601String(),
              'engine': d.engine.name,
              'method': d.method,
              'rssi': d.rssi,
              'channel': d.channel,
              if (d.deviceName.isNotEmpty) 'device_name': d.deviceName,
              if (d.ssid.isNotEmpty) 'ssid': d.ssid,
              if (d.sourceNodeId.isNotEmpty) 'node': d.sourceNodeId,
              if (d.latitude != null && d.longitude != null) 'lat': d.latitude,
              if (d.latitude != null && d.longitude != null) 'lon': d.longitude,
              if (d.detector?.filterDescription case final w? when w.isNotEmpty) 'reason': w,
            },
        ],
      });

  static String kml(List<Detection> rows, {String title = 'OUI-SPY device'}) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
      ..writeln('<Document><name>${_xml(title)}</name>');
    for (final d in rows) {
      final lat = d.latitude, lon = d.longitude;
      if (lat == null || lon == null || (lat == 0 && lon == 0)) continue;
      b
        ..writeln('<Placemark>')
        ..writeln('  <name>${_xml(title)}</name>')
        ..writeln('  <TimeStamp><when>${d.appTimestamp.toUtc().toIso8601String()}</when></TimeStamp>')
        ..writeln('  <description>${_xml('${d.macAddress.toUpperCase()} | ${d.engine.name} | ${d.method} | ${d.rssi} dBm')}</description>')
        ..writeln('  <Point><coordinates>$lon,$lat,0</coordinates></Point>')
        ..writeln('</Placemark>');
    }
    b.writeln('</Document></kml>');
    return b.toString();
  }
}
