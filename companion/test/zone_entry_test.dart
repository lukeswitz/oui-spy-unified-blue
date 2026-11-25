// Copyright (c) 2026 Luke Switzer
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/watch_alerts.dart';

void main() {
  List<({String id, String name})> zonesAt(double lat, double lon) =>
      lat > 10 && lat < 11 ? const [(id: 'z1', name: 'Yard')] : const [];

  test('alerts on entry only, again after leaving or 10 minutes unheard', () {
    final z = ZoneEntry();
    expect(z.onPosition('D1', 'Drone D1', 9.0, 20.0, 0, zonesAt), isNull);
    expect(z.onPosition('D1', 'Drone D1', 10.5, 20.0, 1000, zonesAt), 'Drone D1 is inside Yard');
    expect(z.onPosition('D1', 'Drone D1', 10.6, 20.0, 2000, zonesAt), isNull);
    expect(z.onPosition('D1', 'Drone D1', 12.0, 20.0, 3000, zonesAt), isNull);
    expect(z.onPosition('D1', 'Drone D1', 10.5, 20.0, 4000, zonesAt), 'Drone D1 is inside Yard');
    expect(z.onPosition('D1', 'Drone D1', 10.5, 20.0, 4000 + ZoneEntry.forgetMs + 1, zonesAt), 'Drone D1 is inside Yard');
  });

  test('each device is tracked on its own; no position means no alert', () {
    final z = ZoneEntry();
    expect(z.onPosition('A', 'Cam A', 10.5, 20.0, 0, zonesAt), 'Cam A is inside Yard');
    expect(z.onPosition('B', 'Cam B', 10.5, 20.0, 0, zonesAt), 'Cam B is inside Yard');
    expect(z.onPosition('C', 'Cam C', null, 20.0, 0, zonesAt), isNull);
    expect(z.onPosition('C', 'Cam C', 0, 0, 0, zonesAt), isNull);
  });
}
