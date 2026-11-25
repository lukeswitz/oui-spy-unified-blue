// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:oui_spy/core/models/detection.dart';

String xmlEscape(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String detectionsJson(List<Detection> detections) {
  final buf = StringBuffer('[\n');
  for (int i = 0; i < detections.length; i++) {
    final d = detections[i];
    buf.write('  ');
    buf.write(jsonEncode({
      'mac': d.macAddress,
      'engine': d.engine.name,
      'method': d.method,
      'rssi': d.rssi,
      'channel': d.channel,
      'timestamp': d.appTimestamp.toIso8601String(),
      if (d.latitude != null) 'lat': d.latitude,
      if (d.latitude != null) 'lon': d.longitude,
      if (d.deviceName.isNotEmpty) 'name': d.deviceName,
      if (d.odid?.uavId != null) 'uav_id': d.odid!.uavId,
    }));
    if (i < detections.length - 1) buf.write(',');
    buf.write('\n');
  }
  buf.write(']\n');
  return buf.toString();
}

String detectionsKml(List<Detection> detections) {
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
  buf.writeln('<Document><name>OUI-SPY Detections</name>');
  for (final d in detections.where((d) => d.latitude != null)) {
    buf.writeln('<Placemark>');
    buf.writeln('  <name>${xmlEscape(d.macAddress)}</name>');
    buf.writeln('  <description>${xmlEscape('${d.engine.name} | ${d.method} | ${d.rssi}dBm')}</description>');
    buf.writeln('  <Point><coordinates>${d.longitude},${d.latitude},0</coordinates></Point>');
    buf.writeln('</Placemark>');
  }
  buf.writeln('</Document></kml>');
  return buf.toString();
}
