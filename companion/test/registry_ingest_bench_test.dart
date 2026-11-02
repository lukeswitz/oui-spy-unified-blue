// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';

String _mac(int i) =>
    '02:00:${(i >> 16) & 0xff}:${(i >> 8) & 0xff}:${i & 0xff}:${(i ~/ 251) & 0xff}'
        .toUpperCase();

// Real matchable BLE signatures from the catalog, so engine.match actually hits.
Observation _classifiable(int i, int now) {
  final mac = _mac(i);
  Observation base(String name, List<String> uuids, List<MfgRecord> mfg) => Observation(
        key: 'BLE:$mac', kind: RadioKind.ble, mac: mac, name: name,
        serviceUuids: uuids, mfgRecords: mfg,
        rssi: -45 - (i % 50), firstSeenMs: now, lastSeenMs: now,
      );
  switch (i % 10) {
    case 0: return base('', const [], [MfgRecord(76, '12${i & 0xff}')]); // AirTag
    case 1: return base('', const [], [MfgRecord(76, '07${i & 0xff}')]); // Apple audio
    case 2: return base('', const [], [MfgRecord(76, '10${i & 0xff}')]); // Apple device
    case 3: return base('', const ['00001523-1212-EFDE-1523-785FEABCD123'], const []); // adult toy
    case 4: return base('TPMS$i', const [], const []); // TPMS name
    case 5: return base('', const ['FBB0'], const []); // TPMS svc
    case 6: return base('Arlo$i', const [], const []); // Arlo
    case 7: return base('', const ['FE24'], const []); // August
    case 8: return base('Axon$i', const [], const []); // Axon
    default: return base('', const ['FCBF'], const []); // Seos
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registry ingest scaling with CLASSIFIABLE devices', () async {
    for (final n in const [500, 1000, 2000]) {
      final r = DeviceRegistry();
      await r.loadCatalog();
      final now = DateTime.now().millisecondsSinceEpoch;
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        r.ingest(_classifiable(i, now));
      }
      sw.stop();
      final classified = r.devices.where((d) => d.signatures.isNotEmpty).length;
      print('CLASSIFIABLE n=$n  ${sw.elapsedMilliseconds}ms '
          '(${(sw.elapsedMicroseconds / n).toStringAsFixed(1)}us/obs) '
          'classified=$classified/${r.count}');
    }
  });
}
