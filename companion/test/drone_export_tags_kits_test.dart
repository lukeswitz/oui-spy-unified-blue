// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_kits.dart';
import 'package:oui_spy/core/drone_tags.dart';
import 'package:oui_spy/core/export/drone_export.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/wardrive/drone_markers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime.utc(2026, 1, 1, 12);

DroneReport _r(int sec, {double lat = 10.0, double lon = 20.0, double? hlat, double? hlon, String id = 'SERIAL1'}) =>
    DroneReport(
      ts: _t0.add(Duration(seconds: sec)),
      id: id,
      mac: 'AA:BB:CC:DD:EE:FF',
      lat: lat,
      lon: lon,
      height: 40,
      speed: 4,
      pilotLat: 9.999,
      pilotLon: 19.999,
      hereLat: hlat,
      hereLon: hlon,
      rssi: -60,
      maker: 'DJI',
    );

void main() {
  group('export', () {
    test('CSV has one row per report with the tag and range to the drone', () {
      final csv = DroneExport.csv(
        [_r(0, hlat: 10.0, hlon: 20.001), _r(10, lat: 10.001)],
        tags: {'SERIAL1': DroneTag.hostile},
      );
      final lines = csv.trim().split('\n');
      expect(lines.first, DroneExport.csvHeader);
      expect(lines.length, 3);
      expect(lines[1], contains('hostile'));
      expect(lines[1], contains('2026-01-01T12:00:00.000Z'));
      expect(lines[1].split(',').last, '110');
    });

    test('KML has the path, pilot, detection location and the dashed range line', () {
      final kml = DroneExport.kml(
        [_r(0, hlat: 10.0, hlon: 20.001), _r(10, lat: 10.001, hlat: 10.0, hlon: 20.001)],
        tags: {'SERIAL1': DroneTag.suspicious},
      );
      expect(kml, contains('<LineString><altitudeMode>clampToGround</altitudeMode>'));
      expect(kml, contains('SERIAL1 flight 1 pilot'));
      expect(kml, contains('SERIAL1 flight 1 detection location'));
      expect(kml, contains('#suspicious'));
      expect(kml, contains('range 1'));
    });

    test('a CSV cell with a comma is quoted', () {
      final r = DroneReport(ts: _t0, id: 'A,B', mac: 'M');
      expect(DroneExport.csv([r]), contains('"A,B"'));
    });
  });

  group('tags', () {
    test('a tag persists, replaces and clears', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(droneTagsProvider.notifier);
      await n.set('SERIAL1', DroneTag.friendly);
      await n.set('SERIAL1', DroneTag.hostile);
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(droneTagsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(droneTagsProvider), {'SERIAL1': DroneTag.hostile});
      await n.set('SERIAL1', null);
      expect(c.read(droneTagsProvider), isEmpty);
    });

    test('the marker color is the tag color, or the drone color when untagged', () {
      final d = Detection(
        id: 'x', sessionId: 's', nodeId: 'n', macAddress: '02:00:00:00:00:01',
        engine: Engine.skySpy, method: 'odid_ble', rssi: -60, channel: 0,
        deviceTimestampMs: 0, appTimestamp: _t0,
        odid: const OdidExtension(uavId: 'SERIAL1'),
      );
      expect(droneMarkerColor(d, {'SERIAL1': DroneTag.hostile}), DroneTag.hostile.color);
      expect(droneMarkerColor(d, const {}), droneColorForMac(d.macAddress));
      expect(DroneTag.values.map((t) => t.color).toSet().length, 4);
    });
  });

  group('kits', () {
    test('known controller and Remote ID module names are recognized', () {
      expect(kitSignature(wifiName: 'Spark-RC-1234')!.rule.role, KitRole.controller);
      expect(kitSignature(bleName: 'ArduRemoteID_ABCD')!.rule.role, KitRole.rid);
      expect(kitSignature(wifiName: 'anafi-123')!.rule.role, KitRole.dronewifi);
      expect(kitSignature(bleName: 'Osmo Pocket 3')!.rule.role, isNull);
      expect(kitSignature(bleName: 'Headphones'), isNull);
    });

    List<KitSighting> sightingsAt(Iterable<int> secs, {LatLng? at}) =>
        [for (final s in secs) KitSighting(ts: _t0.add(Duration(seconds: s)), point: at)];

    test('a device heard only around the flights is suggested, one heard all day is not', () {
      final flights = splitFlights([_r(0), _r(60), _r(2000), _r(2060)]);
      final out = kitSuggest(
        flights: flights,
        devices: [
          KitDevice(mac: 'AA:00:00:00:00:01', sightings: sightingsAt([10, 50, 2010, 2050], at: const LatLng(9.9991, 19.999))),
          KitDevice(mac: 'AA:00:00:00:00:02', sightings: sightingsAt([10, 50, 8000, 9000, 20000, 30000])),
          KitDevice(mac: 'AA:00:00:00:00:03', sightings: sightingsAt([10])),
        ],
      );
      expect(out.map((s) => s.device.mac), ['AA:00:00:00:00:01']);
      expect(out.first.reasons, contains('heard in 2 of its 2 flights'));
      expect(out.first.reasons.last, contains('of its pilot or take-off'));
    });

    test('a name signature suggests its role; a device already in a kit or a camera is skipped', () {
      final flights = splitFlights([_r(0), _r(60)]);
      final out = kitSuggest(
        flights: flights,
        devices: [
          KitDevice(mac: 'AA:00:00:00:00:04', wifiName: 'SkyController-9', sightings: sightingsAt([5000])),
          KitDevice(mac: 'AA:00:00:00:00:05', bleName: 'Osmo Action', sightings: sightingsAt([10, 20, 30, 40])),
          KitDevice(mac: 'AA:00:00:00:00:06', wifiName: 'Spark-RC-1', sightings: sightingsAt([5000])),
        ],
        skip: {'AA:00:00:00:00:06'},
      );
      expect(out.length, 1);
      expect(out.single.role, KitRole.controller);
      expect(out.single.reasons.single, contains('SkyController-9'));
    });

    test('a kit member belongs to one drone and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(droneKitsProvider.notifier);
      await n.add('A', const KitMember(mac: 'aa:bb', role: KitRole.goggles, label: 'Goggles'));
      await n.add('B', const KitMember(mac: 'AA:BB', role: KitRole.controller));
      expect(c.read(droneKitsProvider).keys, ['B']);
      expect(n.droneOf('aa:bb'), 'B');
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(droneKitsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(droneKitsProvider)['B']!.single.role, KitRole.controller);
      await n.remove('B', 'aa:bb');
      expect(c.read(droneKitsProvider), isEmpty);
    });
  });
}
