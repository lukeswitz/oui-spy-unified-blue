import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/stops_report.dart';

const _min = 60000;
const _home = (1.0, 1.0);
const _work = (1.02, 1.0);

List<TrackPoint> _stay((double, double) at, int startMin, int minutes) => [
      for (var m = 0; m <= minutes; m++) TrackPoint((startMin + m) * _min, at.$1, at.$2),
    ];

List<TrackPoint> _drive(int startMin) => [
      for (var m = 0; m < 10; m++) TrackPoint((startMin + m) * _min, 1.0 + m * 0.002, 1.0),
    ];

CellSighting _heard(String mac, (double, double) at, int min, {bool ble = true}) =>
    CellSighting(mac, '', ble, at.$1, at.$2, min * _min);

void main() {
  final track = [..._stay(_home, 0, 30), ..._drive(31), ..._stay(_work, 45, 30)];

  test('two stays far apart are two stops; the drive is not a stop', () {
    final s = StopsReport.stops(track);
    expect(s.length, 2);
  });

  test('a radio heard at both stops is reported', () {
    final hits = StopsReport.build(track, [
      _heard('02:00:00:00:00:01', _home, 10),
      _heard('02:00:00:00:00:01', _work, 60),
      _heard('02:00:00:00:00:02', _home, 12),
    ]);
    expect(hits.map((h) => h.mac), ['02:00:00:00:00:01']);
    expect(hits.single.stops, 2);
    expect(hits.single.lastMs, 60 * _min);
  });

  test('stops under 500 m apart count as one', () {
    final near = (1.003, 1.0);
    final t = [..._stay(_home, 0, 30), ..._stay(near, 40, 30)];
    expect(StopsReport.stops(t).length, 1);
    final hits = StopsReport.build(t, [
      _heard('02:00:00:00:00:01', _home, 10),
      _heard('02:00:00:00:00:01', near, 60),
    ]);
    expect(hits, isEmpty);
  });

  test('a short pause is not a stop', () {
    final t = [..._stay(_home, 0, 30), ..._stay(_work, 40, 3)];
    expect(StopsReport.stops(t).length, 1);
  });

  test('heard only between stops is not counted', () {
    final hits = StopsReport.build(track, [
      _heard('02:00:00:00:00:03', _home, 10),
      _heard('02:00:00:00:00:03', (1.01, 1.0), 35),
    ]);
    expect(hits, isEmpty);
  });
}
