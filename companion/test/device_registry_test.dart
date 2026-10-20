import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

void main() {
  final engine = SignatureEngine(
    Signature.parseCatalog(File('assets/fieldwatch-signatures-v2.json').readAsStringSync()),
  );

  Detection det({required String mac, required String method, int channel = 6, String ssid = '', double? lat}) =>
      Detection(
        id: 'x',
        sessionId: 's',
        nodeId: 'n',
        macAddress: mac,
        engine: Engine.wardrive,
        method: method,
        rssi: -60,
        channel: channel,
        deviceTimestampMs: 0,
        appTimestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ssid: ssid,
        latitude: lat,
        longitude: lat == null ? null : 0.0,
      );

  test('wifi detection maps to wifi observation with channel and gps', () {
    final o = observationFromDetection(det(mac: 'e0:0a:f6:11:22:33', method: 'wifi_ap', ssid: 'Cam', lat: 1.0));
    expect(o.kind, RadioKind.wifi);
    expect(o.key, 'WIFI:E0:0A:F6:11:22:33');
    expect(o.channel, 6);
    expect(o.name, 'Cam');
    expect(o.gpsTrail.single.lat, 1.0);
  });

  test('ble detection maps to ble observation', () {
    final o = observationFromDetection(det(mac: '7A:00:00:00:00:01', method: 'ble_adv', channel: 0));
    expect(o.kind, RadioKind.ble);
    expect(o.channel, 0);
  });

  test('detector hit carries board evidence; evidence moves as one on merge', () {
    final cam = Detection(
      id: 'c',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:01',
      engine: Engine.detector,
      method: 'camera',
      rssi: -90,
      channel: 6,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      sourceNodeId: 'n2',
      detector: const DetectorExtension(filterDescription: 'Ring'),
    );
    final o = observationFromDetection(cam);
    expect(o.kind, RadioKind.wifi);
    expect((o.detectorMethod, o.detectorDesc, o.detectorNode), ('camera', 'Ring', 'n2'));
    final w = observationFromDetection(det(mac: '02:00:00:00:00:01', method: 'wifi_ap'));
    expect(w.detectorMethod, isNull);
    final m = w.merge(o).merge(w);
    expect((m.detectorMethod, m.detectorDesc, m.detectorNode), ('camera', 'Ring', 'n2'));
    final axon = observationFromDetection(cam.copyWith(method: 'axon', detector: null, sourceNodeId: ''));
    final a = m.merge(axon);
    expect((a.detectorMethod, a.detectorDesc, a.detectorNode), ('axon', null, null));
  });

  test('board hit on a device the phone already saw re-runs classification once', () {
    final reg = DeviceRegistry(engine: engine);
    var fired = 0;
    reg.onClassified = (_) => fired++;
    reg.ingest(observationFromDetection(det(mac: '02:00:00:00:00:02', method: 'ble_adv', channel: 0)), source: 'phone');
    expect(fired, 1);
    final hit = Detection(
      id: 't',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:02',
      engine: Engine.detector,
      method: 'tracker',
      rssi: -70,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    reg.ingest(observationFromDetection(hit), source: 'esp32');
    expect(reg.count, 1);
    expect(fired, 2);
    expect(reg.devices.single.obs.detectorMethod, 'tracker');
    reg.ingest(observationFromDetection(hit), source: 'esp32');
    expect(fired, 2);
    reg.dispose();
  });

  test('registry merges by key and classifies', () {
    final reg = DeviceRegistry(engine: engine);
    reg.ingest(observationFromDetection(det(mac: 'E0:0A:F6:11:22:33', method: 'wifi_ap')), source: 'esp32');
    reg.ingest(observationFromDetection(det(mac: 'E0:0A:F6:11:22:33', method: 'wifi_ap', ssid: 'X')), source: 'phone');
    expect(reg.count, 1);
    final d = reg.devices.single;
    expect(d.sources, {'esp32', 'phone'});
    expect(d.obs.name, 'X');
    expect(d.signatures.map((s) => s.id), contains('fleet-liteon-camera-radio'));
    reg.dispose();
  });

  test('AD structures parse into mfg, service data, uuids, name', () {
    final raw = <int>[
      0x02, 0x01, 0x06,
      0x03, 0x03, 0x2C, 0xFE,
      0x06, 0x16, 0x2C, 0xFE, 0x00, 0x00, 0x06,
      0x0C, 0xFF, 0x4C, 0x00, 0x07, 0x07, 0x01, 0x0F, 0x20, 0x51, 0x98, 0x11, 0x00,
      0x05, 0x09, 0x42, 0x75, 0x64, 0x73,
    ];
    final p = parseAdvStructures(raw);
    expect(p.serviceUuids, ['FE2C']);
    expect(p.serviceData.single.uuid, 'FE2C');
    expect(p.serviceData.single.dataHex, '000006');
    expect(p.mfg.single.companyId, 0x004C);
    expect(p.mfg.single.dataHex, '0707010F2051981100');
    expect(p.name, 'Buds');
  });

  test('truncated AD structure stops cleanly', () {
    final p = parseAdvStructures([0x05, 0xFF, 0x4C]);
    expect(p.mfg, isEmpty);
  });

  test('wardrive ble packet with adv tail decodes to classified observation', () {
    final adv = [0x0C, 0xFF, 0x4C, 0x00, 0x07, 0x07, 0x01, 0x0F, 0x20, 0x51, 0x98, 0x11, 0x00];
    final pkt = <int>[
      Engine.wardrive.index, 0x7A, 0x01, 0x02, 0x03, 0x04, 0x05, 0xC4, 0, 1, 0, 0, 0, 1,
      0, 0, 0, 0, 0,
      ...List.filled(33, 0), 0, ...List.filled(21, 0),
      adv.length, ...adv,
    ];
    final d = BleProtocol.decodeDetection(pkt, sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026));
    expect(d.method, 'ble_adv');
    expect(wardriveAdvRaw[d.wardrive!], adv);
    final o = observationFromDetection(d);
    expect(o.kind, RadioKind.ble);
    expect(o.mfgRecords.single.companyId, 0x004C);
    final legacy = BleProtocol.decodeDetection(pkt.sublist(0, 74), sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026));
    expect(wardriveAdvRaw[legacy.wardrive!], isNull);
  });

  test('trail dedupes near points and caps spread', () {
    var t = <GpsSample>[];
    t = DeviceRegistry.appendTrail(t, const GpsSample(0, 0.0, 0.0), 48);
    t = DeviceRegistry.appendTrail(t, const GpsSample(1000, 0.00001, 0.0), 48);
    expect(t.length, 1);
    for (var i = 1; i < 100; i++) {
      t = DeviceRegistry.appendTrail(t, GpsSample(i * 60000, i * 0.001, 0.0), 48);
    }
    expect(t.length, lessThanOrEqualTo(49));
    expect(t.first.atMs, 0);
    expect(t.last.atMs, 99 * 60000);
  });
}
