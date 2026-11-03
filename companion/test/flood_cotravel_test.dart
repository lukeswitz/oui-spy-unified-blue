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

Observation _ap(int n, String name, {int rssi = -34, int channel = 6}) {
  String b(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
  final mac = '02:${b(n >> 24)}:${b(n >> 16)}:${b(n >> 8)}:${b(n)}:01';
  return Observation(
    key: 'WIFI:$mac',
    kind: RadioKind.wifi,
    mac: mac,
    name: name,
    rssi: rssi,
    channel: channel,
    hiddenSsid: name.isEmpty,
  );
}

int _at(int step) => 1000000 + step * 30000;
Observation _anchor() => _ap(1, 'FrontDesk', rssi: -50, channel: 11);
List<Observation> _spam({int start = 100, int count = 15}) => [
  for (var i = 0; i < count; i++) _ap(start + i, 'Spam${start + i}'),
];

void _settle(PairingFlood f, int at) {
  f.consider(_ble(250), at);
  f.tick(at);
}

void main() {
  group('PairingFlood', () {
    test('nine popups stay quiet', () {
      final f = PairingFlood();
      for (var i = 0; i < 9; i++) {
        f.consider(_prox(i), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
    });

    test('ten clustered popups open the dialog', () {
      final f = PairingFlood();
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      final n = f.notice!;
      expect(n.showDialog, isTrue);
      expect(n.title(), 'Pairing flood');
      expect(n.popupCount, 10);
      expect(n.families, ['Apple proximity pairing']);
      expect(n.medianRssi, -48);
      expect(n.line(), 'Pairing flood · 10 new addresses · about -48 dBm');
      f.consider(_prox(10), 1000);
      _settle(f, PairingFlood.confirmMs + 1000);
      expect(f.notice!.popupCount, 11);
    });

    test('mixed popup families share one counter', () {
      final f = PairingFlood();
      f.consider(_prox(0), 0);
      f.consider(_prox(1), 0);
      f.consider(_ble(2, mfg: const [MfgRecord(0x004C, '0F0100')]), 0);
      f.consider(_ble(3, mfg: const [MfgRecord(0x004C, '0F0100')]), 0);
      f.consider(_ble(4, sd: const [ServiceDataRecord('FE2C', '000006')]), 0);
      for (var i = 0; i < 4; i++) {
        f.consider(_prox(10 + i), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice, isNull);
      f.consider(_ble(5, mfg: const [MfgRecord(0x0006, '0109')]), 0);
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice!.popupCount, 10);
      expect(f.notice!.families, ['Apple proximity pairing', 'Apple Nearby Action', 'Fast Pair', 'Swift Pair']);
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
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 0);
      }
      _settle(f, PairingFlood.confirmMs + PairingFlood.windowMs);
      expect(f.notice, isNotNull);
      _settle(f, PairingFlood.confirmMs + PairingFlood.windowMs + 1);
      expect(f.notice, isNull);
    });

    test('name flood needs randomized named addresses', () {
      final f = PairingFlood();
      for (var i = 0; i < 15; i++) {
        f.consider(_ble(i, name: 'Radio $i', rssi: -55), 0);
      }
      _settle(f, PairingFlood.confirmMs);
      expect(f.notice!.title(), 'Name flood');
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
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 0);
      }
      expect(f.notice, isNull);
      f.consider(_ble(200), PairingFlood.confirmMs);
      f.tick(PairingFlood.confirmMs - 1);
      expect(f.notice, isNull);
      f.tick(PairingFlood.confirmMs);
      expect(f.notice!.popupCount, 10);
      f.tick(PairingFlood.confirmMs + PairingFlood.windowMs + 1);
      expect(f.notice, isNull);
    });

    test('listening stopped before confirm never flags', () {
      final f = PairingFlood();
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 0);
      }
      f.consider(_ble(200), PairingFlood.confirmMs - 1);
      f.tick(PairingFlood.confirmMs + 5000);
      expect(f.notice, isNull);
    });

    test('node addresses that return are a crowd, not a flood', () {
      final f = PairingFlood();
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 0);
      }
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 10000);
      }
      f.tick(PairingFlood.confirmMs);
      expect(f.notice, isNull);
    });

    test('re-heard inside the rotation time still counts as spam', () {
      final f = PairingFlood();
      for (var i = 0; i < 10; i++) {
        f.consider(_prox(i), 0);
        f.consider(_prox(i), PairingFlood.persistMs - 1);
      }
      f.consider(_ble(200), PairingFlood.confirmMs);
      f.tick(PairingFlood.confirmMs);
      expect(f.notice!.popupCount, 10);
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
      for (var i = 0; i < 12; i++) {
        reg.ingest(at(_prox(i), 0), source: 'esp32');
      }
      for (var i = 0; i < 12; i++) {
        reg.ingest(at(_prox(i), 10000), source: 'esp32');
      }
      reg.pairingFlood.tick(PairingFlood.confirmMs);
      expect(reg.pairingFlood.notice, isNull);
    });

    test('node one-shot addresses flag after confirm', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < 12; i++) {
        reg.ingest(at(_prox(i), 0), source: 'esp32');
      }
      expect(reg.pairingFlood.notice, isNull);
      reg.ingest(at(_ble(200), PairingFlood.confirmMs), source: 'esp32');
      reg.pairingFlood.tick(PairingFlood.confirmMs);
      expect(reg.pairingFlood.notice!.popupCount, 12);
    });

    test('node disconnect leaves pending addresses unconfirmed', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < 12; i++) {
        reg.ingest(at(_prox(i), 0), source: 'esp32');
      }
      reg.pairingFlood.tick(PairingFlood.confirmMs + 1000);
      expect(reg.pairingFlood.notice, isNull);
    });

    test('phone crowd re-heard on its 5 s ingest cadence never flags', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < 12; i++) {
        reg.ingest(at(_prox(i), 0), source: 'phone');
      }
      for (final t in [PhoneBleSource.ingestEvery.inMilliseconds, 2 * PhoneBleSource.ingestEvery.inMilliseconds]) {
        for (var i = 0; i < 12; i++) {
          reg.ingest(at(_prox(i), t), source: 'phone');
        }
      }
      reg.ingest(at(_ble(200), PairingFlood.confirmMs), source: 'phone');
      reg.pairingFlood.tick(PairingFlood.confirmMs);
      expect(reg.pairingFlood.notice, isNull);
    });

    test('crowd larger than the registry cap never flags', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      const n = DeviceRegistry.maxDevices + 1000;
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
      expect(reg.count, DeviceRegistry.maxDevices);
      expect(missedQuiet, isEmpty);
    });

    test('phone one-shot spam flags after confirm', () {
      final reg = DeviceRegistry(engine: SignatureEngine(const []));
      for (var i = 0; i < 12; i++) {
        reg.ingest(at(_prox(i), i * 100), source: 'phone');
      }
      reg.ingest(at(_ble(200), PairingFlood.confirmMs + 1200), source: 'phone');
      reg.pairingFlood.tick(PairingFlood.confirmMs + 1200);
      expect(reg.pairingFlood.notice!.popupCount, 12);
    });
  });

  group('WifiBeaconFlood', () {
    test('first scan stays quiet when crowd leaves', () {
      final f = WifiBeaconFlood();
      f.scan([_anchor(), ..._spam(count: 20)], _at(0));
      f.scan([_anchor()], _at(1));
      expect(f.notice, isNull);
    });

    test('burst that vanishes next scan is a flood', () {
      final f = WifiBeaconFlood();
      f.scan([_anchor()], _at(0));
      f.scan([_anchor(), ..._spam()], _at(1));
      expect(f.notice, isNull);
      f.scan([_anchor()], _at(2));
      expect(f.notice!.wifi, isTrue);
      expect(f.notice!.popupCount, 15);
      expect(f.notice!.line(), 'Wi-Fi beacon flood · 15 new names · about -34 dBm');
    });

    test('mesh, guest suffix, hidden stay out', () {
      final mesh = WifiBeaconFlood()
        ..scan([_anchor()], _at(0))
        ..scan([_anchor(), for (var i = 0; i < 20; i++) _ap(300 + i, 'BuildingMesh')], _at(1))
        ..scan([_anchor()], _at(2));
      expect(mesh.notice, isNull);
      final hidden = WifiBeaconFlood()
        ..scan([_anchor()], _at(0))
        ..scan([_anchor(), for (var i = 0; i < 20; i++) _ap(400 + i, '')], _at(1))
        ..scan([_anchor()], _at(2));
      expect(hidden.notice, isNull);
      final known = [
        for (var i = 1; i <= 15; i++) _ap(10 + i, 'Net${i.toString().padLeft(2, '0')}', rssi: -60, channel: 1),
      ];
      const suffixes = [
        'Guest',
        '5G',
        'ext',
        '2.4',
        '5GHz',
        'extender',
        'guests',
        '6G',
        '2.4GHz',
        '6GHz',
        'guest',
        '5g',
        'EXT',
        '2.4g',
        'Guests',
      ];
      final guests = [
        for (var i = 0; i < 15; i++) _ap(200 + i, 'Net${(i + 1).toString().padLeft(2, '0')}-${suffixes[i]}'),
      ];
      final g = WifiBeaconFlood()
        ..scan([_anchor(), ...known], _at(0))
        ..scan([_anchor(), ...guests], _at(1))
        ..scan([_anchor()], _at(2));
      expect(g.notice, isNull);
    });

    test('cluster that stays is not a flood', () {
      final batch = [_anchor(), ..._spam()];
      final f = WifiBeaconFlood()
        ..scan([_anchor()], _at(0))
        ..scan(batch, _at(1))
        ..scan(batch, _at(2))
        ..scan(batch, _at(3));
      expect(f.notice, isNull);
    });

    test('short list stays out', () {
      final f = WifiBeaconFlood()
        ..scan([_anchor()], _at(0))
        ..scan([_anchor(), ..._spam(count: 14)], _at(1))
        ..scan([_anchor()], _at(2));
      expect(f.notice, isNull);
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
