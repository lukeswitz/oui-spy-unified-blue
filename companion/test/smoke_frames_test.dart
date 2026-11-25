import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/odid/odid_ble.dart';
import 'package:oui_spy/smoke_hook.dart';

void main() {
  test('smoke drone frame decodes to the full Remote ID the board sends', () {
    final f = smokeFrame(Engine.skySpy, '02:00:00:00:06:00', -62, 6, 0, smokeOdidExt(
      uavId: 'SMOKEUAV0001',
      opId: 'SMOKEOP0001',
      lat: 51.402,
      lon: -0.102,
      pilotLat: 51.401,
      pilotLon: -0.101,
      alt: 1700,
      agl: 60,
      speed: 5,
      heading: 90,
      selfId: 'Smoke full drone',
    ));
    expect(f.length, 155);
    final d = BleProtocol.decodeDetection(f, sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026));
    expect(d.engine, Engine.skySpy);
    expect(d.macAddress.toUpperCase(), '02:00:00:00:06:00');
    expect(d.sourceNodeId, 'SMOKE');
    final o = d.odid!;
    expect(o.uavId, 'SMOKEUAV0001');
    expect(o.operatorId, 'SMOKEOP0001');
    expect(o.droneLat, 51.402);
    expect(o.pilotLon, -0.101);
    expect(o.selfId, 'Smoke full drone');
    expect(o.uaType, 2);
    expect(o.opLocationType, 1);
    expect(o.selfIdType, 1);
    expect(o.status, 2);
  });

  test('the smoke phone Remote ID advertisement decodes', () {
    final o = OdidBleDecoder().feed('02:00:00:00:06:02', smokePhoneOdidAdv(51.4, -0.1, 1))!;
    expect(o.uavId, 'DEMO5K6L7M8N9P');
    expect(o.operatorId, 'GBR-OP-DEMO0002');
    expect(o.altitudeMsl, 120);
    expect(o.heightAgl, 30);
    expect(o.droneSpeed, 5);
    expect(o.droneHeading, 45);
    expect(o.droneLat, closeTo(51.4, 1e-6));
  });

  test('Remote ID "unknown" values decode as missing, real values stay', () {
    final ext = smokeOdidExt(
      uavId: 'SMOKEUAV0003',
      opId: '',
      lat: 51.4,
      lon: -0.1,
      pilotLat: null,
      pilotLon: null,
      alt: -1000,
      agl: -1000,
      speed: 255,
      heading: 361,
      selfId: '',
    );
    final b = ByteData.sublistView(Uint8List.fromList(ext));
    b.setInt16(106, -1000, Endian.little);
    b.setInt16(108, 63, Endian.little);
    b.setUint16(120, 0xFFFF, Endian.little);
    final f = smokeFrame(Engine.skySpy, '02:00:00:00:06:02', -60, 6, 0, b.buffer.asUint8List());
    final o = BleProtocol.decodeDetection(f, sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026)).odid!;
    expect(o.altitudeMsl, isNull);
    expect(o.heightAgl, isNull);
    expect(o.altitudeBaro, isNull);
    expect(o.droneSpeed, isNull);
    expect(o.droneHeading, isNull);
    expect(o.vertSpeed, isNull);
    expect(o.locTimestamp, isNull);
    expect(o.uavId, 'SMOKEUAV0003');

    b.setInt16(58, 0, Endian.little);
    b.setInt16(62, 254, Endian.little);
    b.setInt16(64, 0, Endian.little);
    b.setInt16(108, -62, Endian.little);
    b.setUint16(120, 36000, Endian.little);
    final ok = BleProtocol.decodeDetection(
            smokeFrame(Engine.skySpy, '02:00:00:00:06:02', -60, 6, 0, b.buffer.asUint8List()),
            sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026))
        .odid!;
    expect(ok.altitudeMsl, 0);
    expect(ok.droneSpeed, 254);
    expect(ok.droneHeading, 0);
    expect(ok.vertSpeed, -62);
    expect(ok.locTimestamp, 36000);
  });
}
