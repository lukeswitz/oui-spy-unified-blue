// Copyright (c) 2026 Luke Switzer
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/node_positions.dart';
import 'package:oui_spy/core/triangulation.dart';
import 'package:oui_spy/core/triangulation_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dist = Distance(roundResult: false);
const _a = LatLng(10.0, 20.0);
const _b = LatLng(10.0008, 20.0002);
const _c = LatLng(10.0002, 20.0009);
const _target = LatLng(10.0004, 20.0004);

TriRange _exact(String id, LatLng node, LatLng target) =>
    TriRange(id, node, _dist.as(LengthUnit.Meter, node, target));

void main() {
  test('rssi to distance follows the log-distance model', () {
    expect(rssiToDistanceM(-59), closeTo(1.0, 1e-9));
    expect(rssiToDistanceM(-86), closeTo(10.0, 1e-9));
    expect(rssiToDistanceM(-79, p0: -49, n: 3.0), closeTo(10.0, 1e-9));
    expect(rssiToDistanceM(-70), greaterThan(rssiToDistanceM(-60)));
  });

  test('three nodes with exact distances recover the target within 1 m', () {
    final fix = solveTriangulation([_exact('A', _a, _target), _exact('B', _b, _target), _exact('C', _c, _target)]);
    expect(fix, isNotNull);
    expect(_dist.as(LengthUnit.Meter, fix!.at, _target), lessThan(1.0));
    expect(fix.errM, lessThan(1.0));
    expect(fix.ranges, hasLength(3));
  });

  test('distances built from rssi through the model recover the target within 1 m', () {
    const p0 = -59.0;
    const n = 2.7;
    TriRange viaRssi(String id, LatLng node) {
      final d = _dist.as(LengthUnit.Meter, node, _target);
      final rssi = p0 - 10 * n * (_log10(d));
      return TriRange(id, node, rssiToDistanceM(rssi, p0: p0, n: n));
    }

    final fix = solveTriangulation([viaRssi('A', _a), viaRssi('B', _b), viaRssi('C', _c)]);
    expect(_dist.as(LengthUnit.Meter, fix!.at, _target), lessThan(1.0));
  });

  test('four nodes with noisy distances give a fix near the target and a nonzero error', () {
    const d = LatLng(10.0007, 20.0010);
    final noise = [6.0, 6.0, 5.0, 7.0];
    final nodes = [_a, _b, _c, d];
    final ranges = [
      for (var i = 0; i < nodes.length; i++)
        TriRange('N$i', nodes[i], _dist.as(LengthUnit.Meter, nodes[i], _target) + noise[i]),
    ];
    final fix = solveTriangulation(ranges)!;
    expect(_dist.as(LengthUnit.Meter, fix.at, _target), lessThan(10));
    expect(fix.errM, greaterThan(1));
    expect(fix.errM, lessThan(8));
  });

  test('fewer than three nodes returns null', () {
    expect(solveTriangulation(const []), isNull);
    expect(solveTriangulation([_exact('A', _a, _target)]), isNull);
    expect(solveTriangulation([_exact('A', _a, _target), _exact('B', _b, _target)]), isNull);
    expect(
        solveTriangulation([
          _exact('A', _a, _target),
          _exact('B', _b, _target),
          const TriRange('C', _c, double.nan),
        ]),
        isNull);
  });

  group('engine', () {
    final placed = {'AAAA': _a, 'BBBB': _b, 'CCCC': _c};
    final t0 = DateTime(2026, 1, 1, 12);

    int rssiAt(LatLng node) => (-59 - 27 * _log10(_dist.as(LengthUnit.Meter, node, _target))).round();

    test('a device heard by three placed nodes inside the window is fixed', () {
      final e = TriangulationEngine();
      e.add('aa:bb:cc:00:00:01', 'AAAA', rssiAt(_a), t0);
      e.add('AA:BB:CC:00:00:01', 'BBBB', rssiAt(_b), t0.add(const Duration(seconds: 5)));
      e.add('AA:BB:CC:00:00:01', 'CCCC', rssiAt(_c), t0.add(const Duration(seconds: 10)));
      final fixes = e.compute(t0.add(const Duration(seconds: 20)), placed);
      expect(fixes, hasLength(1));
      expect(fixes.single.mac, 'AA:BB:CC:00:00:01');
      expect(fixes.single.heardAt, t0.add(const Duration(seconds: 10)));
      expect(_dist.as(LengthUnit.Meter, fixes.single.fix.at, _target), lessThan(15));
    });

    test('a node last heard more than 60 s ago drops out, leaving two', () {
      final e = TriangulationEngine();
      e.add('AA:BB:CC:00:00:01', 'AAAA', rssiAt(_a), t0);
      e.add('AA:BB:CC:00:00:01', 'BBBB', rssiAt(_b), t0.add(const Duration(seconds: 50)));
      e.add('AA:BB:CC:00:00:01', 'CCCC', rssiAt(_c), t0.add(const Duration(seconds: 55)));
      expect(e.compute(t0.add(const Duration(seconds: 59)), placed), hasLength(1));
      expect(e.compute(t0.add(const Duration(seconds: 61)), placed), isEmpty);
    });

    test('a node that is not placed does not count', () {
      final e = TriangulationEngine();
      e.add('AA:BB:CC:00:00:01', 'AAAA', rssiAt(_a), t0);
      e.add('AA:BB:CC:00:00:01', 'BBBB', rssiAt(_b), t0);
      e.add('AA:BB:CC:00:00:01', 'DDDD', -70, t0);
      expect(e.compute(t0, placed), isEmpty);
    });

    test('samples per node are averaged and pruned', () {
      final e = TriangulationEngine(maxSamples: 3);
      for (var i = 0; i < 10; i++) {
        e.add('AA:BB:CC:00:00:01', 'AAAA', -60, t0.add(Duration(seconds: i)));
      }
      expect(e.deviceCount, 1);
      e.prune(t0.add(const Duration(minutes: 5)));
      expect(e.deviceCount, 0);
    });
  });

  group('controller', () {
    Detection det(String node, int rssi, {String mac = '02:00:00:00:00:09'}) => Detection(
          id: 'x$node$rssi',
          sessionId: 's',
          nodeId: 'n',
          macAddress: mac,
          engine: Engine.flockBle,
          method: 'oui',
          rssi: rssi,
          channel: 0,
          deviceTimestampMs: 0,
          appTimestamp: DateTime.now(),
          sourceNodeId: node,
        );

    TriangulationController make(Map<String, LatLng> placed, {bool enabled = true}) => TriangulationController(
          placed: () => placed,
          settings: () => TriSettings(enabled: enabled),
          selfNode: () => 'CCCC',
          minInterval: Duration.zero,
        );

    int rssiAt(LatLng node) => (-59 - 27 * _log10(_dist.as(LengthUnit.Meter, node, _target))).round();

    test('node detections and the connected board own detections reach a fix', () {
      final c = make({'AAAA': _a, 'BBBB': _b, 'CCCC': _c});
      var notified = 0;
      c.addListener(() => notified++);
      c.onDetection(det('AAAA', rssiAt(_a)));
      c.onDetection(det('OUISPY-BBBB', rssiAt(_b)));
      expect(c.fixes, isEmpty);
      c.onDetection(det('', rssiAt(_c)));
      expect(c.fixes, hasLength(1));
      expect(c.fixes.single.mac, '02:00:00:00:00:09');
      expect(notified, 1);
    });

    testWidgets('detections inside the throttle window still give a fix once it ends', (tester) async {
      final c = TriangulationController(
        placed: () => {'AAAA': _a, 'BBBB': _b, 'CCCC': _c},
        settings: () => const TriSettings(),
        selfNode: () => '',
        minInterval: const Duration(seconds: 1),
      );
      c.onDetection(det('AAAA', rssiAt(_a)));
      c.onDetection(det('BBBB', rssiAt(_b)));
      c.onDetection(det('CCCC', rssiAt(_c)));
      expect(c.fixes, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(c.fixes, hasLength(1));
      c.dispose();
    });

    test('fewer than three placed nodes records nothing', () {
      final c = make({'AAAA': _a, 'BBBB': _b});
      c.onDetection(det('AAAA', -60));
      c.onDetection(det('BBBB', -60));
      c.onDetection(det('CCCC', -60));
      expect(c.fixes, isEmpty);
    });

    test('turned off, it records nothing', () {
      final c = make({'AAAA': _a, 'BBBB': _b, 'CCCC': _c}, enabled: false);
      c.onDetection(det('AAAA', rssiAt(_a)));
      c.onDetection(det('BBBB', rssiAt(_b)));
      c.onDetection(det('CCCC', rssiAt(_c)));
      expect(c.fixes, isEmpty);
    });
  });

  group('node positions', () {
    test('place and clear are saved and survive a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final n = NodePositionsNotifier();
      await n.place('AAAA', const LatLng(10, 20));
      await n.place('BBBB', const LatLng(11, 21));
      await n.clear('AAAA');
      expect(n.state.keys, ['BBBB']);
      final p = await SharedPreferences.getInstance();
      expect((jsonDecode(p.getString('node_positions')!) as Map).keys, ['BBBB']);
      final again = NodePositionsNotifier();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(again.state['BBBB'], const LatLng(11, 21));
    });

    test('a load that finishes after a change does not overwrite it', () async {
      SharedPreferences.setMockInitialValues({
        'node_positions': jsonEncode({'ZZZZ': {'lat': 1.0, 'lon': 2.0}}),
      });
      final n = NodePositionsNotifier();
      await n.place('AAAA', const LatLng(10, 20));
      await Future<void>.delayed(Duration.zero);
      expect(n.state.keys, ['AAAA']);
    });
  });
}

double _log10(double x) => math.log(x) / math.ln10;
