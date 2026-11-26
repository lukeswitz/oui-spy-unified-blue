// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/fpv/fpv_state.dart' show fpvDetectionMethod;

final _t0 = DateTime(2026, 1, 1, 12);

DroneReport _r(int sec, {String id = 'SERIAL1', int? height, double? lat, double? lon, int? status, double? plat, double? plon, double? hlat, double? hlon, int? rssi, String mac = 'AA:BB:CC:DD:EE:FF', int? speed}) =>
    DroneReport(
      ts: _t0.add(Duration(seconds: sec)),
      id: id,
      mac: mac,
      height: height,
      lat: lat,
      lon: lon,
      status: status,
      pilotLat: plat,
      pilotLon: plon,
      hereLat: hlat,
      hereLon: hlon,
      rssi: rssi,
      speed: speed,
    );

void main() {
  test('reports more than 5 minutes apart on the ground are separate flights', () {
    final flights = splitFlights([_r(0), _r(200), _r(200 + 301)]);
    expect(flights.length, 2);
    expect(flights.first.reports.length, 2);
  });

  test('an airborne drone keeps one flight through a 20 minute gap', () {
    final flights = splitFlights([_r(0, height: 50), _r(1200, height: 40)]);
    expect(flights.length, 1);
    expect(splitFlights([_r(0, height: 50), _r(1501, height: 40)]).length, 2);
  });

  test('a gap after a low report uses the short limit', () {
    expect(splitFlights([_r(0, height: 50), _r(400, height: 5)]).length, 2);
  });

  test('a flight records its detection location from the first report with a phone position', () {
    final f = splitFlights([
      _r(0, lat: 10.001, lon: 20.0),
      _r(10, lat: 10.002, lon: 20.0, hlat: 10.0, hlon: 20.0),
      _r(20, lat: 10.003, lon: 20.0, hlat: 10.5, hlon: 20.5),
    ]).single;
    expect(f.detectionPoint!.latitude, 10.0);
    expect(f.detectionRange, closeTo(332.0, 1.0));
  });

  test('flight stats: heights, speed, distance flown and farthest from the pilot', () {
    final f = splitFlights([
      _r(0, height: 10, lat: 10.0, lon: 20.0, plat: 10.0, plon: 20.0, speed: 3),
      _r(10, height: 80, lat: 10.001, lon: 20.0, plat: 10.0, plon: 20.0, speed: 9),
      _r(20, height: 40, lat: 10.002, lon: 20.0, plat: 10.0, plon: 20.0, speed: 2),
    ]).single;
    expect(f.maxHeight, 80);
    expect(f.maxSpeed, 9);
    expect(f.duration, const Duration(seconds: 20));
    expect(f.flownMeters, closeTo(221.0, 1.0));
    expect(f.farthestFromPilot, closeTo(221.0, 1.0));
  });

  test('reports at 0,0 or out of range are not positions', () {
    expect(_r(0, lat: 0, lon: 0).dronePoint, isNull);
    expect(_r(0, lat: 91, lon: 0).dronePoint, isNull);
    expect(_r(0, lat: 10, lon: 20).dronePoint, isNotNull);
  });

  test('a report survives a JSON round trip', () {
    final r = _r(5, height: 12, lat: 10.5, lon: 20.5, status: 2, plat: 10.4, plon: 20.4, hlat: 10.3, hlon: 20.3, rssi: -70);
    final back = DroneReport.fromJson(r.toJson());
    expect(back.ts, r.ts);
    expect(back.id, 'SERIAL1');
    expect(back.height, 12);
    expect(back.status, 2);
    expect(back.herePoint!.latitude, 10.3);
    expect(back.rssi, -70);
  });

  test('an FPV detection becomes an FPV report that survives the log and is never counted with a pilot', () {
    final det = Detection(
      id: 'x',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:46:50:56:16:E9',
      engine: Engine.skySpy,
      method: fpvDetectionMethod,
      rssi: -68,
      channel: 1,
      deviceTimestampMs: 0,
      appTimestamp: _t0,
      odid: const OdidExtension(uavId: 'FPV A1 5865'),
    );
    final r = DroneReport.fromDetection(det);
    expect(r.fpv, isTrue);
    expect(r.id, 'FPV A1 5865');
    final back = DroneReport.fromJson(r.toJson());
    expect(back.fpv, isTrue);
    expect(_r(0).toJson().containsKey('fpv'), isFalse);
    expect(_r(0).fpv, isFalse);
    final withPilot = DroneReport(ts: _t0, id: 'FPV A1 5865', mac: 'm', pilotLat: 10.0, pilotLon: 20.0, fpv: true);
    final drones = summarizeDrones([withPilot, _r(0, id: 'RID', plat: 10.0, plon: 20.0)], _t0);
    expect(drones.firstWhere((d) => d.fpv).hasPilot, isFalse);
    expect(countDrones(drones).pilots, 1);
  });

  test('counts: live, airborne, pilots, top height and in window', () {
    final now = _t0.add(const Duration(minutes: 10));
    final drones = summarizeDrones([
      _r(600 - 5, id: 'A', status: 2, height: 90, plat: 10.0, plon: 20.0, lat: 10.1, lon: 20.1),
      _r(600 - 30, id: 'B', status: 1, height: 3),
      _r(0, id: 'C', status: 2, height: 120, mac: '11:22:33:44:55:66'),
    ], now);
    final c = countDrones(drones);
    expect(c.live, 2);
    expect(c.airborne, 1);
    expect(c.pilots, 1);
    expect(c.topHeight, 120);
    expect(c.inWindow, 3);
    expect(drones.first.id, 'A');
  });
}
