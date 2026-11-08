import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/co_travel.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/flood.dart';
import 'package:oui_spy/core/classify/observation.dart';

String _bleMac(int n) => '02:00:00:00:00:${n.toRadixString(16).padLeft(2, '0').toUpperCase()}';

Observation _ble(
  int n, {
  int rssi = -48,
  String name = '',
  List<MfgRecord> mfg = const [],
  List<ServiceDataRecord> sd = const [],
}) => Observation(
  key: 'BLE:${_bleMac(n)}',
  kind: RadioKind.ble,
  mac: _bleMac(n),
  name: name,
  rssi: rssi,
  mfgRecords: mfg,
  serviceData: sd,
);

Observation _prox(int n, {int rssi = -48}) => _ble(n, rssi: rssi, mfg: const [MfgRecord(0x004C, '070100')]);

void _settle(PairingFlood f, int at) {
  f.consider(_ble(250), at);
  f.tick(at);
}

void main() {
  group('PairingFlood', () {
    test('one under the minimum stays quiet', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin - 1; i++) {
        f.consider(_prox(i), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
    });

    test('crowd of one-shot addresses at spread signal levels never flags', () {
      final f = PairingFlood();
      for (var i = 0; i < 180; i++) {
        f.consider(_prox(i, rssi: -60 - (i % 35)), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
    });

    test('clustered popups at the minimum open the dialog', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      final n = f.notice!;
      expect(n.showDialog, isTrue);
      expect(n.title(), 'Pairing flood');
      expect(n.popupCount, PairingFlood.popupMin);
      expect(n.families, ['Apple proximity pairing']);
      expect(n.medianRssi, -48);
      expect(n.line(), 'Pairing flood · ${PairingFlood.popupMin} new addresses · about -48 dBm');
      f.consider(_prox(PairingFlood.popupMin), 1000);
      _settle(f, PairingFlood.confirmMs + 1000);
      expect(f.notice!.popupCount, PairingFlood.popupMin + 1);
    });

    test('mixed popup families share one counter', () {
      final f = PairingFlood();
      f.consider(_prox(0), 0);
      f.consider(_prox(1), 0);
      f.consider(_ble(2, mfg: const [MfgRecord(0x004C, '0F0100')]), 0);
      f.consider(_ble(3, mfg: const [MfgRecord(0x004C, '0F0100')]), 0);
      f.consider(_ble(4, sd: const [ServiceDataRecord('FE2C', '000006')]), 0);
      for (var i = 0; i < PairingFlood.popupMin - 6; i++) {
        f.consider(_prox(10 + i), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
      f.consider(_ble(5, mfg: const [MfgRecord(0x0006, '030080')]), 0);
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice!.popupCount, PairingFlood.popupMin);
      expect(f.notice!.families, ['Apple proximity pairing', 'Apple Nearby Action', 'Fast Pair', 'Swift Pair']);
    });

    test('Windows CDP beacons and Find My payloads are not popups', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_ble(i, mfg: const [MfgRecord(0x0006, '0109200200')]), 0);
        f.consider(_ble(100 + i, mfg: const [MfgRecord(0x004C, '1202000007020000')]), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
    });

    test('same address counted once', () {
      final f = PairingFlood();
      for (var i = 0; i < 8; i++) {
        f.consider(_prox(1), i * 100);
      }
      _settle(f, PairingFlood.confirmMs + 800);
      expect(f.notice, isNull);
    });

    test('window expires', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 0);
      }
      _settle(f, PairingFlood.confirmMs + PairingFlood.windowMs);
      expect(f.notice, isNotNull);
      _settle(f, PairingFlood.confirmMs + PairingFlood.windowMs + 1);
      expect(f.notice, isNull);
    });

    test('named devices are never a flood', () {
      final f = PairingFlood();
      for (var i = 0; i < 200; i++) {
        f.consider(_ble(i, name: 'Radio $i', rssi: -55), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
      final g = PairingFlood();
      for (var i = 0; i < 20; i++) {
        g.consider(
          Observation(
            key: 'k$i',
            kind: RadioKind.ble,
            mac: '00:11:22:33:44:${i.toRadixString(16).padLeft(2, '0')}',
            name: 'X$i',
          ),
          0,
        );
      }
      _settle(g, PairingFlood.confirmMs);
      expect(g.notice, isNull);
    });

    test('node addresses that never return flag after confirm', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 0);
      }
      expect(f.notice, isNull);
      f.consider(_ble(200), PairingFlood.confirmMs);
      f.tick(PairingFlood.confirmMs - 1);
      expect(f.notice, isNull);
      f.tick(PairingFlood.confirmMs);
      expect(f.notice!.popupCount, PairingFlood.popupMin);
      f.tick(PairingFlood.confirmMs + PairingFlood.windowMs + 1);
      expect(f.notice, isNull);
    });

    test('listening stopped before confirm never flags', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 0);
      }
      f.consider(_ble(200), PairingFlood.confirmMs - 1);
      f.tick(PairingFlood.confirmMs + 5000);
      expect(f.notice, isNull);
    });

    test('node addresses that return are a crowd, not a flood', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 0);
      }
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 10000);
      }
      f.tick(PairingFlood.confirmMs);
      expect(f.notice, isNull);
    });

    test('re-heard inside the rotation time still counts as spam', () {
      final f = PairingFlood();
      for (var i = 0; i < PairingFlood.popupMin; i++) {
        f.consider(_prox(i), 0);
        f.consider(_prox(i), PairingFlood.persistMs - 1);
      }
      f.consider(_ble(200), PairingFlood.confirmMs);
      f.tick(PairingFlood.confirmMs);
      expect(f.notice!.popupCount, PairingFlood.popupMin);
    });

    test('sustained spam at 100 per second stays flagged without gaps', () {
      final f = PairingFlood();
      String hx(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      var n = 0;
      final missed = <int>[];
      for (var ms = 0; ms <= 60000; ms += 10) {
        final mac = '02:00:00:${hx(n >> 16)}:${hx(n >> 8)}:${hx(n)}';
        n++;
        f.consider(
          Observation(key: 'BLE:$mac', kind: RadioKind.ble, mac: mac, rssi: -52, mfgRecords: const [MfgRecord(0x004C, '070100')]),
          ms,
        );
        if (ms % 1000 == 0) {
          f.tick(ms);
          if (ms > PairingFlood.confirmMs && f.notice == null) missed.add(ms);
        }
      }
      expect(missed, isEmpty);
    });

    test('sustained spam at 300 per second stays flagged and counts every address', () {
      final f = PairingFlood();
      String hx(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      var n = 0;
      final missed = <int>[];
      var steady = 0;
      for (var ms = 0; ms <= 60000; ms += 10) {
        for (var k = 0; k < 3; k++) {
          final mac = '02:00:00:${hx(n >> 16)}:${hx(n >> 8)}:${hx(n)}';
          n++;
          f.consider(Observation(key: 'BLE:$mac', kind: RadioKind.ble, mac: mac, rssi: -52, mfgRecords: const [MfgRecord(0x004C, '070100')]), ms);
        }
        if (ms % 1000 == 0) {
          f.tick(ms);
          if (ms > PairingFlood.confirmMs + 1000 && f.notice == null) missed.add(ms);
          if (ms == 50000) steady = f.notice!.popupCount;
        }
      }
      expect(missed, isEmpty);
      expect(steady, greaterThanOrEqualTo(3000));
    });

    test('a full window keeps its oldest hits so a fast spammer still confirms', () {
      final f = PairingFlood();
      String hx(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      for (var i = 0; i < 600; i++) {
        final mac = '02:00:00:00:${hx(i >> 8)}:${hx(i)}';
        f.consider(
          Observation(key: 'BLE:$mac', kind: RadioKind.ble, mac: mac, rssi: -48, mfgRecords: const [MfgRecord(0x004C, '070100')]),
          i * 20,
        );
      }
      f.consider(_ble(200), PairingFlood.confirmMs + 600 * 20);
      f.tick(PairingFlood.confirmMs + 600 * 20);
      expect(f.notice, isNotNull);
    });
  });

  group('registry flood wiring', () {
    Observation at(Observation o, int ms) => Observation(
          key: o.key, kind: o.kind, mac: o.mac, rssi: o.rssi, mfgRecords: o.mfgRecords, lastSeenMs: ms, firstSeenMs: ms);

    test('node crowd re-reported on rediscover never flags', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
        reg.ingest(at(_prox(i), 0), source: 'esp32');
      }
      for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
        reg.ingest(at(_prox(i), 10000), source: 'esp32');
      }
      reg.pairingFlood.tick(PairingFlood.confirmMs);
      expect(reg.pairingFlood.notice, isNull);
    });

    test('node one-shot addresses flag after confirm', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
        reg.ingest(at(_prox(i), 0), source: 'esp32');
      }
      expect(reg.pairingFlood.notice, isNull);
      reg.ingest(at(_ble(200), PairingFlood.confirmMs), source: 'esp32');
      reg.pairingFlood.tick(PairingFlood.confirmMs);
      expect(reg.pairingFlood.notice!.popupCount, PairingFlood.popupMin + 2);
    });

    test('node disconnect leaves pending addresses unconfirmed', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
        reg.ingest(at(_prox(i), 0), source: 'esp32');
      }
      reg.pairingFlood.tick(PairingFlood.confirmMs + 1000);
      expect(reg.pairingFlood.notice, isNull);
    });

    test('phone crowd re-heard on its 5 s ingest cadence never flags', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
        reg.ingest(at(_prox(i), 0), source: 'phone');
      }
      for (final t in [PhoneBleSource.ingestEvery.inMilliseconds, 2 * PhoneBleSource.ingestEvery.inMilliseconds]) {
        for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
          reg.ingest(at(_prox(i), t), source: 'phone');
        }
      }
      reg.ingest(at(_ble(200), PairingFlood.confirmMs), source: 'phone');
      reg.pairingFlood.tick(PairingFlood.confirmMs);
      expect(reg.pairingFlood.notice, isNull);
    });

    test('crowd above the old 10k cap is all kept and never flags', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      const n = 11000;
      String hx(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
      Observation dev(int i, int ms) {
        final mac = '6E:00:00:00:${hx(i >> 8)}:${hx(i)}';
        return Observation(key: 'BLE:$mac', kind: RadioKind.ble, mac: mac, rssi: -60,
            mfgRecords: const [MfgRecord(0x004C, '070100')], lastSeenMs: ms, firstSeenMs: ms);
      }
      final missedQuiet = <int>[];
      for (var round = 0; round < 6; round++) {
        final t = round * 10000;
        for (var i = 0; i < n; i++) {
          reg.ingest(dev(i, t + i * 3), source: 'esp32');
        }
        reg.pairingFlood.tick(t + 9000);
        if (reg.pairingFlood.notice != null) missedQuiet.add(t);
      }
      expect(reg.count, n);
      expect(missedQuiet, isEmpty);
    });

    test('phone one-shot spam flags after confirm', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < PairingFlood.popupMin + 2; i++) {
        reg.ingest(at(_prox(i), i * 10), source: 'phone');
      }
      reg.ingest(at(_ble(200), PairingFlood.confirmMs + 1200), source: 'phone');
      reg.pairingFlood.tick(PairingFlood.confirmMs + 1200);
      expect(reg.pairingFlood.notice!.popupCount, PairingFlood.popupMin + 2);
    });
  });

  group('CoTravel', () {
    List<GpsSample> walk(int n, {int rssi = -60}) => [
      for (var i = 0; i < n; i++) GpsSample(i * 10000, i * 0.0002, 0.0, rssi),
    ];

    test('loud tag along a moving path is with you', () {
      final path = walk(6);
      final tag = Observation(
        key: 'BLE:t',
        kind: RadioKind.ble,
        mac: '7A:00:00:00:00:01',
        rssi: -60,
        lastSeenMs: 50000,
        gpsTrail: walk(6),
      );
      expect(CoTravel.withYou(tag, CoTravelCtx.of(path), 50000), isTrue);
    });

    test('wifi, quiet, or stationary is not with you', () {
      final ctx = CoTravelCtx.of(walk(6));
      final wifi = Observation(
        key: 'W',
        kind: RadioKind.wifi,
        mac: '00:11:22:33:44:55',
        rssi: -50,
        lastSeenMs: 50000,
        gpsTrail: walk(6),
      );
      expect(CoTravel.withYou(wifi, ctx, 50000), isFalse);
      final quiet = Observation(
        key: 'Q',
        kind: RadioKind.ble,
        mac: '7A:00:00:00:00:02',
        rssi: -60,
        lastSeenMs: 50000,
        gpsTrail: walk(6, rssi: -90),
      );
      expect(CoTravel.withYou(quiet, ctx, 50000), isFalse);
      final still = Observation(
        key: 'S',
        kind: RadioKind.ble,
        mac: '7A:00:00:00:00:03',
        rssi: -60,
        lastSeenMs: 50000,
        gpsTrail: [walk(1).first, walk(1).first],
      );
      expect(CoTravel.withYou(still, ctx, 50000), isFalse);
      expect(CoTravel.withYou(still, CoTravelCtx.none, 50000), isFalse);
    });

    test('find my payload is a finder', () {
      const o = Observation(
        key: 'f',
        kind: RadioKind.ble,
        mac: '7A:00:00:00:00:04',
        mfgRecords: [MfgRecord(0x004C, '1219')],
      );
      expect(TrackerMatch.kind(o, const []), TrackerKind.finder);
      expect(TrackerMatch.kind(_ble(5, rssi: -90), const ['Minew']), TrackerKind.beacon);
    });
  });
}
