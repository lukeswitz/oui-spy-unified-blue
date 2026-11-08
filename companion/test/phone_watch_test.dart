import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/phone_watch.dart';

const _lte = CellReading('LTE', '001-01', 100, 1001);
const _gsm = CellReading('GSM', '001-01', 7, 501);

GpsPosition _fix(double lat, int sec, {double speed = 0, double acc = 5}) => GpsPosition(
      latitude: lat,
      longitude: 1.0,
      altitude: 0,
      speed: speed,
      heading: 0,
      accuracy: acc,
      satelliteCount: -1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(sec * 1000),
    );

void main() {
  group('CellWatch', () {
    test('a drop to 2G right after 4G warns once', () {
      final w = CellWatch();
      expect(w.check(_lte, 1.0, 1.0, 0), isNull);
      expect(w.check(_gsm, 1.0, 1.0, 30000), 'This phone dropped to 2G');
      expect(w.check(_gsm, 1.0, 1.0, 60000), isNull);
    });

    test('2G with no recent 4G at a new place is quiet', () {
      final w = CellWatch();
      expect(w.check(_gsm, 1.0, 1.0, 0), isNull);
    });

    test('3G warns only where this phone usually has 4G', () {
      final w = CellWatch();
      w.check(_lte, 1.0, 1.0, 0);
      expect(w.check(const CellReading('WCDMA', '001-01', 7, 9), 1.0, 1.0, CellWatch.recentMs + 1), startsWith('This phone dropped to 3G'));
      expect(w.check(const CellReading('WCDMA', '001-01', 7, 9), 2.0, 1.0, CellWatch.recentMs * 3), isNull);
    });

    test('a new tower at a learned place warns after learning, then is learned', () {
      final w = CellWatch();
      w.check(_lte, 1.0, 1.0, 0);
      const other = CellReading('LTE', '001-01', 100, 2002);
      expect(w.check(other, 1.0, 1.0, 1000), isNull);
      const third = CellReading('LTE', '001-01', 100, 3003);
      expect(w.check(third, 1.0, 1.0, CellWatch.learnMs + 1), 'New 4G cell at a known place');
      expect(w.check(third, 1.0, 1.0, CellWatch.learnMs + CellWatch.cooldownMs + 2), isNull);
    });

    test('reading map rejects missing or max cell ids', () {
      expect(CellReading.fromMap({'rat': 'LTE', 'cid': 2147483647}), isNull);
      expect(CellReading.fromMap({'rat': 'LTE'}), isNull);
      expect(CellReading.fromMap({'rat': 'NR', 'plmn': '001-01', 'area': 5, 'cid': 123})!.label, '5G');
    });

    test('places round-trip through JSON', () {
      final p = CellPlace(1.0, 2.0, 3, {'LTE:x'}, 4);
      final q = CellPlace.fromJson(p.toJson());
      expect((q.lat, q.lon, q.firstMs, q.bestRank), (1.0, 2.0, 3, 4));
      expect(q.cells, {'LTE:x'});
    });
  });

  group('GpsWatch', () {
    test('a mock location warns', () {
      final w = GpsWatch();
      expect(w.onFix(_fix(1.0, 0), true, 0), 'An app on this phone is setting the GPS location');
    });

    test('a jump faster than 300 m/s warns; normal driving does not', () {
      final w = GpsWatch();
      w.onFix(_fix(1.0, 0), false, 0);
      expect(w.onFix(_fix(1.0003, 1), false, 1000), isNull);
      expect(w.onFix(_fix(1.05, 2), false, 2000), startsWith('GPS position jumped'));
    });

    test('identical satellite signals for 10 s warn', () {
      final w = GpsWatch();
      const flat = [45.0, 45.2, 45.1, 44.9, 45.0, 45.1, 45.0];
      String? r;
      for (var s = 0; s <= 10; s++) {
        r = w.onSatellites(flat, s * 1000);
      }
      expect(r, startsWith('Satellite signals look identical'));
      final real = GpsWatch();
      for (var s = 0; s <= 10; s++) {
        expect(real.onSatellites(const [22.0, 30.0, 41.0, 35.0, 28.0, 44.0, 19.0], s * 1000), isNull);
      }
    });

    test('a sudden signal loss while driving warns; while walking it does not', () {
      final w = GpsWatch();
      w.onFix(_fix(1.0, 0, speed: 15), false, 0);
      for (var s = 0; s < 5; s++) {
        w.onSatellites(const [40.0, 35.0, 30.0, 38.0, 33.0, 36.0], s * 1000);
      }
      expect(w.onSatellites(const [12.0, 14.0], 5000), startsWith('GPS signal dropped suddenly'));
      final walk = GpsWatch();
      walk.onFix(_fix(1.0, 0, speed: 1), false, 0);
      for (var s = 0; s < 5; s++) {
        walk.onSatellites(const [40.0, 35.0, 30.0, 38.0, 33.0, 36.0], s * 1000);
      }
      expect(walk.onSatellites(const [12.0, 14.0], 5000), isNull);
    });
  });
}
