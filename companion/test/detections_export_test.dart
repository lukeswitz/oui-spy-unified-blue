// Copyright (c) 2026 Luke Switzer
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/export/detections_export.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

const _nasty = r'A"B\C<D>&E';

Detection _det({String name = _nasty, String? uav = _nasty, double? lat = 10.5}) => Detection(
      id: '1',
      sessionId: 's',
      nodeId: 'n',
      macAddress: 'AA:BB:CC:DD:EE:FF',
      engine: Engine.detector,
      method: _nasty,
      rssi: -61,
      channel: 6,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
      deviceName: name,
      latitude: lat,
      longitude: lat == null ? null : 20.25,
      odid: uav == null ? null : OdidExtension(uavId: uav),
    );

void main() {
  test('JSON export round-trips quotes, backslashes, angle brackets and ampersands', () {
    final out = jsonDecode(detectionsJson([_det(), _det(name: '', uav: null, lat: null)])) as List;
    expect(out, hasLength(2));
    final a = out[0] as Map<String, dynamic>;
    expect(a['name'], _nasty);
    expect(a['uav_id'], _nasty);
    expect(a['method'], _nasty);
    expect(a['mac'], 'AA:BB:CC:DD:EE:FF');
    expect(a['engine'], 'detector');
    expect(a['rssi'], -61);
    expect(a['channel'], 6);
    expect(a['lat'], 10.5);
    expect(a['lon'], 20.25);
    expect(a['timestamp'], '2026-01-02T03:04:05.000Z');
    final b = out[1] as Map<String, dynamic>;
    expect(b.containsKey('name'), isFalse);
    expect(b.containsKey('uav_id'), isFalse);
    expect(b.containsKey('lat'), isFalse);
  });

  test('JSON export of no detections is an empty array', () {
    expect(jsonDecode(detectionsJson(const [])), isEmpty);
  });

  test('KML export escapes XML specials in names and descriptions', () {
    final kml = detectionsKml([_det(), _det(lat: null)]);
    expect(kml, contains('A&quot;B\\C&lt;D&gt;&amp;E'));
    final text = kml.replaceAll(RegExp(r'<[A-Za-z/?][^<>]*>'), '');
    expect(text.contains('<'), isFalse);
    expect(text.contains('>'), isFalse);
    expect(RegExp(r'&(?!(amp|lt|gt|quot|apos);)').hasMatch(text), isFalse);
    expect(RegExp('<Placemark>').allMatches(kml), hasLength(1));
    expect(kml, contains('<coordinates>20.25,10.5,0</coordinates>'));
  });

  test('xmlEscape handles all five specials and drops control characters', () {
    expect(xmlEscape('&<>"\'\x01'), '&amp;&lt;&gt;&quot;&apos;');
  });
}
