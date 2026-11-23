import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/link/sdr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starting the SDR starts GPS so hits carry a position without a wardrive session', () async {
    var gpsStarts = 0;
    final c = SdrController(
      gps: () => null,
      startGps: () async {
        gpsStarts++;
        return true;
      },
    );
    await c.start('dev', SdrMode.values.first, 433920000, 250000);
    expect(gpsStarts, 1);
    c.dispose();
  });
}
