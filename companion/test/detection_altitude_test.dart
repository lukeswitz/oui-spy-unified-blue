import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/smoke_hook.dart';

void main() {
  test('board and phone detections carry the GPS altitude for the WiGLE AltitudeMeters column', () async {
    final ble = BleManager();
    ble.updateGps(latitude: 51.4, longitude: -0.1, altitude: 1612.5, accuracy: 4);
    final seen = <double?>[];
    final sub = ble.detections.listen((d) => seen.add(d.altitude));
    ble.injectDetectionFrame(smokeFrame(Engine.wardrive, '02:00:00:00:01:00', -60, 1, 0, List.filled(55, 0)));
    ble.addPhoneDetection('02:00:00:00:03:00', 'x', -60, const []);
    ble.addPhoneWifiDetection('02:00:00:00:01:01', 'MyNetwork', -60, 6, 3);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, [1612.5, 1612.5, 1612.5]);
  });
}
