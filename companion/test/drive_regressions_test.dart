import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/wardrive_state.dart';

GpsPosition _fix(double lat, int atMs) => GpsPosition(
      latitude: lat,
      longitude: -100,
      altitude: 0,
      speed: 30,
      heading: 0,
      accuracy: 5,
      satelliteCount: 8,
      timestamp: DateTime.fromMillisecondsSinceEpoch(atMs),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GPS step', () {
    test('a 2 km gap after 60 s at highway speed is real travel', () {
      expect(WardriveController.isImpossibleGpsStep(_fix(40, 0), _fix(40.018, 60000)), isFalse);
    });

    test('a 2 km jump within one second is a glitch', () {
      expect(WardriveController.isImpossibleGpsStep(_fix(40, 0), _fix(40.018, 1000)), isTrue);
    });

    test('a rejected glitch cannot latch: the same point is accepted once time has passed', () {
      expect(WardriveController.isImpossibleGpsStep(_fix(40, 0), _fix(40.1, 1000)), isTrue);
      expect(WardriveController.isImpossibleGpsStep(_fix(40, 0), _fix(40.1, 600000)), isFalse);
    });
  });

  group('track placement', () {
    final track = [_fix(40.0, 10000), _fix(40.1, 20000), _fix(40.2, 30000)];

    test('a row takes the fix nearest its capture time, not the latest', () {
      expect(WardriveController.trackFixAt(track, 19000)!.latitude, 40.1);
      expect(WardriveController.trackFixAt(track, 11000)!.latitude, 40.0);
    });

    test('a row with no fix near its capture time stays unplaced', () {
      expect(WardriveController.trackFixAt([_fix(40.0, 10000), _fix(40.2, 30000)], 20000), isNull);
      expect(WardriveController.trackFixAt(track, 60000), isNull);
      expect(WardriveController.trackFixAt(const [], 15000), isNull);
    });
  });

  group('flock probe confidence', () {
    const ext = FlockExtension(signals: FlockSignal.oui);

    test('a plain wildcard probe from a listed OUI is not high confidence', () {
      expect(ext.confidence('wildcard_probe'), FlockConfidence.suspected);
    });

    test('the Flock IE signature stays high confidence', () {
      expect(ext.confidence('wildcard_probe_ie_sig'), FlockConfidence.high);
    });
  });

  group('catalog', () {
    late SignatureEngine engine;

    setUpAll(() async {
      engine = SignatureEngine(
        Signature.parseCatalog(await rootBundle.loadString('assets/fieldwatch-signatures-v2.json')),
      );
    });

    Iterable<String> hits(Observation o) => engine.match(o).map((s) => s.id);

    Observation ble(String name, {List<MfgRecord> mfg = const []}) => Observation(
        key: 'BLE:00:11:22:33:44:55', kind: RadioKind.ble, mac: '00:11:22:33:44:55', name: name, mfgRecords: mfg);

    test('penguin matches only BLE names starting penguin-', () {
      expect(hits(ble('Penguin-1234567890')), contains('fleet-penguin'));
      expect(hits(ble('penguin-abc')), contains('fleet-penguin'));
      expect(hits(ble('Emperor Penguin Speaker')), isNot(contains('fleet-penguin')));
      expect(hits(ble('Penguin')), isNot(contains('fleet-penguin')));
      expect(
        hits(const Observation(key: 'WIFI:00:11:22:33:44:55', kind: RadioKind.wifi, mac: '00:11:22:33:44:55', name: 'penguin-guest')),
        isNot(contains('fleet-penguin')),
      );
    });

    test('ordinary names and SSIDs that contain a Flock word are not Flock', () {
      const flockIds = {'fleet-flock-cameras', 'fleet-fs-ext-battery', 'fleet-pigvision', 'fleet-penguin', 'fleet-raven'};
      Observation ap(String name) =>
          Observation(key: 'WIFI:00:11:22:33:44:55', kind: RadioKind.wifi, mac: '00:11:22:33:44:55', name: name);
      for (final o in [
        ble('Flock of Seagulls'),
        ble('Falcon Headphones'),
        ble('FS_Scale'),
        ble('Ravens Speaker'),
        ap('flock-guest'),
        ap('FALCON-5G'),
        ap('Pigvision'),
        ap('Ravens Nest'),
      ]) {
        expect(hits(o).toSet().intersection(flockIds), isEmpty, reason: o.name);
      }
      expect(hits(ble('Flock-123456')), contains('fleet-flock-cameras'));
      expect(hits(ble('FS Ext Battery')), contains('fleet-fs-ext-battery'));
      expect(hits(ble('Pigvision')), contains('fleet-pigvision'));
    });

    test('Magic Switch reads as an Apple Watch, Handoff as an Apple device', () {
      expect(hits(ble('', mfg: const [MfgRecord(0x004C, '0B03C4B53F')])), contains('fleet-apple-watch'));
      expect(hits(ble('', mfg: const [MfgRecord(0x004C, '0C0E00')])), isNot(contains('fleet-apple-watch')));
    });

    test('Cradlepoint is a router, not public safety', () {
      final sig = engine.signatures.firstWhere((s) => s.id == 'fleet-cradlepoint');
      expect(sig.kind, SignatureClass.isp);
    });
  });
}
