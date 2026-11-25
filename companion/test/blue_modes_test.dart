// Copyright (c) 2026 Luke Switzer
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble_sniff.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';

Uint8List _frame({
  int ll = 0,
  bool random = false,
  List<int> advA = const [0x01, 0x02, 0x03, 0x04, 0x05, 0x06],
  List<int> target = const [],
  List<int> adv = const [],
  int rssi = -60,
}) {
  final payloadLen = 6 + target.length + adv.length;
  return Uint8List.fromList([
    37, rssi & 0xFF, 0x80, 0,
    0xD6, 0xBE, 0x89, 0x8E, 0x13, 0x0C,
    0xD6, 0xBE, 0x89, 0x8E,
    (ll & 0x0F) | (random ? 0x40 : 0), payloadLen,
    ...advA, ...target, ...adv,
    0, 0, 0,
  ]);
}

Uint8List _record(int us, Uint8List frame) {
  final bd = ByteData(24 + frame.length + 4);
  bd.setUint32(0, 0xCAFEBABE, Endian.little);
  bd.setUint32(4, 16 + frame.length, Endian.little);
  bd.setUint32(8, us ~/ 1000000, Endian.little);
  bd.setUint32(12, us % 1000000, Endian.little);
  bd.setUint32(16, frame.length, Endian.little);
  bd.setUint32(20, frame.length, Endian.little);
  final out = bd.buffer.asUint8List();
  out.setRange(24, 24 + frame.length, frame);
  bd.setUint32(24 + frame.length, 0xDEADBEEF, Endian.little);
  return out;
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  group('BLE Sniff frame decode', () {
    test('advert summary: name, services, manufacturer', () {
      final adv = [
        0x02, 0x01, 0x06,
        0x05, 0x09, 0x54, 0x65, 0x73, 0x74,
        0x05, 0x03, 0x81, 0xFC, 0x6B, 0xFE,
        0x05, 0xFF, 0x4D, 0x03, 0x01, 0x02,
      ];
      final a = decodeSniffFrame(_frame(adv: adv), t0)!;
      expect(a.macStr, '06:05:04:03:02:01');
      expect(a.llName, 'ADV_IND');
      expect(a.addrClass, 'pub');
      expect(a.rssi, -60);
      expect(a.name, 'Test');
      expect(a.services, [0xFC81, 0xFE6B]);
      expect(a.servicesLabel, '0xFC81,0xFE6B');
      expect(a.mfrId, 0x034D);
      expect(a.mfrLabel, '034D (Axon/TASER)');
      expect(a.connectable, isTrue);
    });

    test('random address classes follow the top two bits of the MSB', () {
      expect(decodeSniffFrame(_frame(random: true, advA: [1, 2, 3, 4, 5, 0x00]), t0)!.addrClass, 'rnd-nrp');
      expect(decodeSniffFrame(_frame(random: true, advA: [1, 2, 3, 4, 5, 0x7F]), t0)!.addrClass, 'rnd-rpa');
      expect(decodeSniffFrame(_frame(random: true, advA: [1, 2, 3, 4, 5, 0xC0]), t0)!.addrClass, 'rnd-s');
    });

    test('direct advert skips the target address; scan response type is named', () {
      final d = decodeSniffFrame(_frame(ll: 1, target: [9, 9, 9, 9, 9, 9], adv: [0x02, 0x01, 0x06]), t0)!;
      expect(d.llName, 'ADV_DIRECT');
      expect(d.advData, [0x02, 0x01, 0x06]);
      expect(decodeSniffFrame(_frame(ll: 4), t0)!.llName, 'SCAN_RSP');
      expect(decodeSniffFrame(_frame(ll: 4), t0)!.connectable, isFalse);
    });

    test('truncated or foreign frames are rejected', () {
      expect(decodeSniffFrame(Uint8List(10), t0), isNull);
      final f = _frame(adv: [0x02, 0x01, 0x06]);
      expect(decodeSniffFrame(Uint8List.sublistView(f, 0, f.length - 4), t0), isNull);
    });

    test('overlong AD length stops the walk without throwing', () {
      final a = decodeSniffFrame(_frame(adv: [0x09, 0xFF, 0x4D, 0x03]), t0)!;
      expect(a.mfrId, isNull);
    });

    test('filter config op carries the mask the firmware parses', () {
      expect(sniffCfgFilter, 0x01);
      expect(sniffFtDefault, sniffFtAdvInd | sniffFtAdvDirect | sniffFtAdvNonconn | sniffFtScanRsp |
          sniffFtAdvScanInd | sniffFtAddrPublic | sniffFtAddrRandom);
    });
  });

  group('BLE Sniff record stream and pcap file', () {
    test('records split across chunks and after junk are recovered in order', () {
      final r1 = _record(1000000, _frame(adv: [0x02, 0x01, 0x06]));
      final r2 = _record(1500000, _frame(ll: 4));
      final all = Uint8List.fromList([0x11, 0x22, ...r1, ...r2]);
      final s = SniffRecordSplitter();
      final got = <SniffRecord>[
        ...s.add(Uint8List.sublistView(all, 0, 20)),
        ...s.add(Uint8List.sublistView(all, 20, 41)),
        ...s.add(Uint8List.sublistView(all, 41)),
      ];
      expect(got.length, 2);
      expect(got[0].deviceUs, 1000000);
      expect(got[1].deviceUs, 1500000);
      expect(decodeSniffFrame(got[1].frame, t0)!.llName, 'SCAN_RSP');
    });

    test('a record with a bad end mark is dropped', () {
      final bad = _record(5, _frame());
      bad[bad.length - 1] = 0;
      final good = _record(6, _frame());
      final got = SniffRecordSplitter().add(Uint8List.fromList([...bad, ...good]));
      expect(got.length, 1);
      expect(got[0].deviceUs, 6);
    });

    test('pcap header is LINKTYPE 256 and records carry phone time', () {
      final w = SniffPcapWriter(startEpochUs: 1800000000 * 1000000);
      final h = ByteData.sublistView(w.header());
      expect(h.getUint32(0, Endian.little), 0xa1b2c3d4);
      expect(h.getUint32(20, Endian.little), 256);
      final f = _frame(adv: [0x02, 0x01, 0x06]);
      final a = ByteData.sublistView(w.record(SniffRecord(4000000, f)));
      final b = ByteData.sublistView(w.record(SniffRecord(4250000, f)));
      expect(a.getUint32(0, Endian.little), 1800000000);
      expect(a.getUint32(4, Endian.little), 0);
      expect(b.getUint32(0, Endian.little), 1800000000);
      expect(b.getUint32(4, Endian.little), 250000);
      expect(a.getUint32(8, Endian.little), f.length);
    });

    test('device clock wrap keeps time moving forward', () {
      final w = SniffPcapWriter(startEpochUs: 0);
      final f = _frame();
      w.record(SniffRecord(0xFFFFFF00, f));
      final b = ByteData.sublistView(w.record(SniffRecord(0x100, f)));
      expect(b.getUint32(4, Endian.little), 0x200);
    });
  });

  group('engine wire format', () {
    test('engines 8 and 9 are AXEOFF and BLE Sniff, app-only SDR follows', () {
      expect(Engine.axeoff.index, 8);
      expect(Engine.bleSniff.index, 9);
      expect(Engine.sdr.index, 10);
      expect(Engine.firmwareCount, 10);
      final masks = Engine.values.map((e) => e.bitmask).toList();
      expect(masks.toSet().length, masks.length);
    });

    test('engine status with ext bytes folds engines 8+ into the mask', () {
      final frame = <int>[0xFF, 0x41, 2, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0x03, 0x03];
      final s = BleProtocol.decodeEngineStatus(frame);
      expect(s.states.length, 10);
      expect(s.active, 0x341);
      expect(s.available, 0x3FF);
      expect(s.states[8].name, 'scanning');
    });

    test('engine status from firmware without ext bytes still decodes', () {
      final s = BleProtocol.decodeEngineStatus([0xFF, 0x40, 0, 0, 0, 0, 0, 0, 2, 0]);
      expect(s.active, 0x40);
      expect(s.states.length, 8);
    });

    test('enable commands carry the firmware ids', () {
      expect(BleProtocol.encodeEngineControl(engine: Engine.axeoff, enable: true), [0x01, 8]);
      expect(BleProtocol.encodeEngineControl(engine: Engine.bleSniff, enable: false), [0x00, 9]);
    });

    test('mesh status engine-ext block sets the high bits for that node only', () {
      final base = <int>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2];
      for (final id in ['AB12', 'AB13']) {
        base.addAll([...id.codeUnits, 0, 0, 0x05, 0x01, 0x07, 0x00, 0x00]);
      }
      base.addAll([1, 1, 30, 30, 0, 0, 0, 0]);
      final s = BleProtocol.decodeMeshStatus([...base, BleProtocol.meshTlvEngineExt, 3, 0xAB, 0x13, 0x01]);
      expect(s.liveNodes[0].activeEngines, 0x05);
      expect(s.liveNodes[1].activeEngines, 0x105);
    });

    test('PCAP stats carry the BLE Sniff source flag', () {
      final raw = List<int>.filled(86, 0)
        ..[0] = 1
        ..[1] = 1
        ..[3] = 1;
      final st = PcapStats.decode(raw)!;
      expect(st.isBleSniff, isTrue);
      raw[3] = 0;
      expect(PcapStats.decode(raw)!.isBleSniff, isFalse);
    });
  });
}
