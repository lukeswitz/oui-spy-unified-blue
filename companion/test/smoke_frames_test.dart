import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/smoke_hook.dart';

void main() {
  test('smoke drone frame decodes to the full Remote ID the board sends', () {
    final f = smokeFrame(Engine.skySpy, '02:00:00:00:06:00', -62, 6, 0, smokeOdidExt(
      uavId: 'SMOKEUAV0001',
      opId: 'SMOKEOP0001',
      lat: 40.002,
      lon: -105.002,
      pilotLat: 40.001,
      pilotLon: -105.001,
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
    expect(o.droneLat, 40.002);
    expect(o.pilotLon, -105.001);
    expect(o.selfId, 'Smoke full drone');
    expect(o.uaType, 2);
    expect(o.opLocationType, 1);
    expect(o.selfIdType, 1);
    expect(o.status, 2);
  });
}
