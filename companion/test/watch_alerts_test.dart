import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/watch_alerts.dart';

const _min = 60000;

void main() {
  group('CarFollow', () {
    test('a tire sensor heard over 2 km and 10 min warns', () {
      final c = CarFollow();
      String? r;
      for (var m = 0; m <= 12; m++) {
        r = c.onTire('ABC|1', m * _min, 1.0 + m * 0.002, 1.0) ?? r;
      }
      expect(r, startsWith('A car may be following you'));
    });

    test('a parked car heard for 15 min in one place is quiet', () {
      final c = CarFollow();
      for (var m = 0; m <= 15; m++) {
        expect(c.onTire('ABC|2', m * _min, 1.0, 1.0), isNull);
      }
    });

    test('a sensor heard at the start of two scans is learned as your car', () {
      final c = CarFollow();
      c.scanStarted(0);
      c.onTire('MINE|1', 10000, 1.0, 1.0);
      c.scanStarted(100 * _min);
      c.onTire('MINE|1', 100 * _min + 5000, 1.0, 1.0);
      expect(c.ownCars, contains('MINE|1'));
      for (var m = 0; m <= 12; m++) {
        expect(c.onTire('MINE|1', (101 + m) * _min, 1.0 + m * 0.002, 1.0), isNull);
      }
    });
  });

  group('AircraftCircle', () {
    test('two full turns near you warn', () {
      final a = AircraftCircle();
      String? r;
      for (var i = 0; i <= 40; i++) {
        r = a.onAircraft('ABC123', 'N123', i * 20000, 1.0 + 0.01 * (i % 4), 1.0, (i * 20.0) % 360, 1.0, 1.0) ?? r;
      }
      expect(r, startsWith('Aircraft circling near you: N123'));
    });

    test('a straight pass with jitter is quiet', () {
      final a = AircraftCircle();
      for (var i = 0; i <= 60; i++) {
        expect(a.onAircraft('ABC124', 'N124', i * 15000, 1.0 + i * 0.001, 1.0, 90.0 + (i.isEven ? 2 : -2), 1.0, 1.0),
            isNull);
      }
    });

    test('circling far from you is quiet', () {
      final a = AircraftCircle();
      for (var i = 0; i <= 40; i++) {
        expect(a.onAircraft('ABC125', 'N125', i * 20000, 2.0, 1.0, (i * 20.0) % 360, 1.0, 1.0), isNull);
      }
    });
  });

  group('DroneLoiter', () {
    test('a drone hovering within 300 m for 5 min warns', () {
      final d = DroneLoiter();
      String? r;
      for (var s = 0; s <= 6 * 60; s += 20) {
        r = d.onDrone('UAV1', s * 1000, 1.001, 1.0, null, null, 1.0, 1.0) ?? r;
      }
      expect(r, startsWith('Drone loitering near you'));
    });

    test('a pilot closing 200 m to within 500 m warns', () {
      final d = DroneLoiter();
      expect(d.onDrone('UAV2', 0, 1.01, 1.0, 1.006, 1.0, 1.0, 1.0), isNull);
      expect(d.onDrone('UAV2', 60000, 1.01, 1.0, 1.003, 1.0, 1.0, 1.0), startsWith('Drone pilot moving toward you'));
    });

    test('a drone passing by is quiet', () {
      final d = DroneLoiter();
      for (var s = 0; s <= 6 * 60; s += 20) {
        expect(d.onDrone('UAV3', s * 1000, 1.0 + s * 0.0001, 1.0, null, null, 1.0, 1.0), isNull);
      }
    });
  });

  group('MeshCrossing', () {
    test('a device handed from node A to node B warns once confirmed', () {
      final m = MeshCrossing();
      expect(m.onSighting('K1', 'A', 0), isNull);
      expect(m.onSighting('K1', 'A', 10000), isNull);
      expect(m.onSighting('K1', 'B', 60000), isNull);
      expect(m.onSighting('K1', 'B', 130000), 'Moving through your mesh: node A to node B');
    });

    test('a device in the overlap of two nodes is quiet', () {
      final m = MeshCrossing();
      for (var t = 0; t < 600000; t += 40000) {
        expect(m.onSighting('K2', t % 80000 == 0 ? 'A' : 'B', t), isNull);
      }
    });
  });
}
