// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

String _randMac(int i) {
  final b = [0x2a, (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff, 0x01];
  return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
}

Observation _obs(int i, int now) {
  final mac = _randMac(i);
  return Observation(
    key: 'ble:$mac',
    kind: RadioKind.ble,
    mac: mac,
    lastSeenMs: now,
    firstSeenMs: now,
    rssi: -50,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registry ingest scaling with real catalog', () async {
    final reg = DeviceRegistry();
    await reg.loadCatalog();
    print('catalog ready=${reg.ready}');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final n in const [250, 500, 1000, 2000]) {
      final r = DeviceRegistry();
      await r.loadCatalog();
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        r.ingest(_obs(i, now));
      }
      sw.stop();
      print('INGEST n=$n  ${sw.elapsedMilliseconds}ms '
          '(${(sw.elapsedMicroseconds / n).toStringAsFixed(1)}us/obs) count=${r.count}');
    }
    expect(reg.ready, isTrue);
  });
}
