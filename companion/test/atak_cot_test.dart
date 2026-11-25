// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/atak/atak_connector.dart';
import 'package:oui_spy/core/atak/cot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

Detection _det({
  Engine engine = Engine.detector,
  String method = 'glasses',
  double? lat = 10.5,
  double? lon = 20.25,
  OdidExtension? odid,
}) =>
    Detection(
      id: '1',
      sessionId: 's',
      nodeId: 'n',
      macAddress: 'aa:bb:cc:dd:ee:ff',
      engine: engine,
      method: method,
      rssi: -61,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
      deviceName: 'Cam <"A&B">',
      latitude: lat,
      longitude: lon,
      odid: odid,
    );

void main() {
  test('a catch is one unknown-ground marker at the phone position, escaped', () {
    final ev = cotEventsFor(_det());
    expect(ev, hasLength(1));
    final xml = ev.single.toXml();
    expect(xml, contains('uid="ouispy-catch-AABBCCDDEEFF"'));
    expect(xml, contains('type="a-u-G"'));
    expect(xml, contains('how="h-e"'));
    expect(xml, contains('lat="10.5000000" lon="20.2500000"'));
    expect(xml, contains('time="2026-01-02T03:04:05.000Z"'));
    expect(xml, contains('stale="2026-01-02T03:09:05.000Z"'));
    expect(xml, isNot(contains('<"A&B">')));
  });

  test('a Remote ID drone sends the drone and a linked pilot', () {
    final ev = cotEventsFor(_det(
      engine: Engine.skySpy,
      method: 'odid_ble',
      odid: const OdidExtension(uavId: 'SERIAL1', droneLat: 10.0, droneLon: 20.0, pilotLat: 10.01, pilotLon: 20.01),
    ));
    expect(ev.map((e) => e.type), ['a-u-A-M-H-Q', 'a-u-G']);
    expect(ev.first.callsign, 'UAS SERIAL1');
    expect(ev.last.toXml(), contains('<link uid="ouispy-drone-AABBCCDDEEFF" relation="p-p"'));
  });

  test('wardrive rows and catches without a position send nothing', () {
    expect(cotEventsFor(_det(engine: Engine.wardrive, method: 'wifi_ap')), isEmpty);
    expect(cotEventsFor(_det(lat: null, lon: null)), isEmpty);
    expect(cotEventsFor(_det(lat: 0, lon: 0)), isEmpty);
  });

  test('the connector sends one UDP datagram per event and rate-limits repeats', () async {
    SharedPreferences.setMockInitialValues({});
    final rx = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = <String>[];
    rx.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = rx.receive();
        if (d != null) got.add(utf8.decode(d.data));
      }
    });
    final c = AtakConnector();
    await c.update(const AtakSettings(enabled: true).copyWith(port: rx.port));
    expect(await c.send(_det()), 1);
    expect(await c.send(_det()), 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(got, hasLength(1));
    expect(got.single, contains('uid="ouispy-catch-AABBCCDDEEFF"'));
    await c.update(c.state.copyWith(enabled: false));
    expect(await c.send(_det()), 0);
    c.dispose();
    rx.close();
  });

  test('control characters are dropped from XML text', () {
    expect(CotEvent.esc('a\x01b\x1Fc'), 'abc');
    expect(CotEvent.esc("O'Neil"), 'O&apos;Neil');
  });
}
