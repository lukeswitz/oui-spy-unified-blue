// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/probes/probe_frame.dart';
import 'package:oui_spy/core/probes/probe_intel.dart';
import 'package:oui_spy/core/probes/probe_ranks.dart';
import 'package:oui_spy/core/probes/probe_store.dart';

Uint8List record({
  int fc0 = 0x40,
  String sa = 'AA:BB:CC:DD:EE:FF',
  List<int> ssid = const [],
  int freq = 2437,
  int rssi = -60,
  bool declaredRssi = false,
}) {
  final rt = Uint8List(18);
  rt[2] = 18;
  if (declaredRssi) {
    rt[4] = 0x2A;
  } else {
    rt[4] = 0x0A;
  }
  rt[10] = freq & 0xFF;
  rt[11] = freq >> 8;
  rt[14] = rssi & 0xFF;
  final fr = <int>[fc0, 0, 0, 0, ...List.filled(6, 0xFF), ...sa.split(':').map((h) => int.parse(h, radix: 16)), ...List.filled(6, 0xFF), 0, 0];
  fr.addAll([0, ssid.length, ...ssid, 1, 2, 0x82, 0x84]);
  final body = [...rt, ...fr];
  final hdr = Uint8List(16);
  ByteData.sublistView(hdr).setUint32(8, body.length, Endian.little);
  return Uint8List.fromList([...hdr, ...body]);
}

void main() {
  group('parseProbeRecord', () {
    test('reads a directed probe', () {
      final s = parseProbeRecord(record(ssid: 'MyNetwork'.codeUnits))!;
      expect(s.mac, 'AA:BB:CC:DD:EE:FF');
      expect(s.ssid, 'MyNetwork');
      expect(s.rssi, -60);
      expect(s.freqMhz, 2437);
    });

    test('wildcard probe has no name', () {
      expect(parseProbeRecord(record())!.ssid, isNull);
    });

    test('other frames are skipped', () {
      expect(parseProbeRecord(record(fc0: 0x80, ssid: 'x'.codeUnits)), isNull);
      expect(parseProbeRecord(Uint8List(10)), isNull);
    });

    test('declared rssi comes from the radiotap fields', () {
      final r = record(ssid: 'a'.codeUnits, declaredRssi: true);
      final s = parseProbeRecord(r)!;
      expect(s.freqMhz, 2437);
      expect(s.rssi, -60);
    });

    test('zeroed and control-character names are dropped', () {
      expect(cleanSsid([0, 0, 0]), isNull);
      expect(cleanSsid('a\u0001b'.codeUnits), 'ab');
    });
  });

  group('intel helpers', () {
    test('random and band detection', () {
      expect(isRandomMac('02:11:22:33:44:55'), isTrue);
      expect(isRandomMac('00:11:22:33:44:55'), isFalse);
      expect(bandOfChannel(6), probeBand24);
      expect(bandOfChannel(36), probeBand5);
      expect(bandOfFreq(5180), probeBand5);
      expect(bandsLabel(3), '2.4 + 5 GHz');
    });

    test('maker names', () {
      expect(makerOf('02:00:00:00:00:01', (_) => 'Acme'), randomMakerLabel);
      expect(makerOf('00:00:00:00:00:01', (_) => null), unregisteredMakerLabel);
      expect(shortMaker('Acme Devices Co., Ltd.'), 'Acme Devices');
      expect(shortMaker('Example Corp'), 'Example');
    });

    test('twins need two shared networks', () {
      ProbeDev dev(String mac, List<String> names) =>
          ProbeDev(mac: mac, first: 1, last: 1, ssids: {for (final n in names) n: 1});
      final a = dev('AA:00:00:00:00:01', ['Home', 'Cafe']);
      final b = dev('AA:00:00:00:00:02', ['Cafe', 'Home']);
      final c = dev('AA:00:00:00:00:03', ['Home']);
      final d = dev('AA:00:00:00:00:04', ['Home']);
      final tw = ProbeTwins([a, b, c, d]);
      expect(tw.count(a), 1);
      expect(tw.count(b), 1);
      expect(tw.count(c), 0);
    });
  });

  group('ProbeStore', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('probes');
      file = File('${dir.path}/probes.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('counts per device and per name', () async {
      var now = 1000;
      final s = ProbeStore(file: () async => file, clock: () => now);
      s.add(mac: 'aa:bb:cc:dd:ee:01', ssid: 'Home', rssi: -50, channel: 6);
      now = 2000;
      s.add(mac: 'AA:BB:CC:DD:EE:01', ssid: 'Home', rssi: -40, freqMhz: 5180);
      s.add(mac: 'AA:BB:CC:DD:EE:01');
      final d = s.deviceFor('AA:BB:CC:DD:EE:01')!;
      expect(d.count, 3);
      expect(d.ssids, {'Home': 2});
      expect(d.first, 1000);
      expect(d.last, 2000);
      expect(d.rssi, -40);
      expect(d.bands, 3);
      expect(s.deviceCount, 1);
      s.dispose();
    });

    test('saves, reloads and clears', () async {
      final s = ProbeStore(file: () async => file, clock: () => 5);
      s.add(mac: 'AA:BB:CC:DD:EE:01', ssid: 'Home');
      await s.flush();
      expect(file.existsSync(), isTrue);
      final r = ProbeStore(file: () async => file, clock: () => 9);
      await r.load();
      expect(r.deviceFor('AA:BB:CC:DD:EE:01')!.ssids, {'Home': 1});
      await r.clear();
      final again = ProbeStore(file: () async => file);
      await again.load();
      expect(again.deviceCount, 0);
      s.dispose();
      r.dispose();
      again.dispose();
    });

    test('keeps the newest devices when full', () {
      var now = 0;
      final s = ProbeStore(file: () async => file, clock: () => now);
      for (var i = 0; i <= ProbeStore.maxDevices; i++) {
        now = i + 1;
        s.add(mac: '02:00:00:00:${(i >> 8).toRadixString(16).padLeft(2, '0')}:${(i & 255).toRadixString(16).padLeft(2, '0')}');
      }
      expect(s.deviceCount, ProbeStore.maxDevices);
      expect(s.deviceFor('02:00:00:00:00:00'), isNull);
      s.dispose();
    });
  });

  group('ranks', () {
    final devs = [
      ProbeDev(mac: '00:00:00:00:00:01', first: 10, last: 100, count: 5, rssi: -70, ssids: {'Home': 3, 'Cafe': 2}, ssidLast: {'Home': 100, 'Cafe': 50}),
      ProbeDev(mac: '00:00:00:00:00:02', first: 20, last: 200, count: 9, rssi: -40, ssids: {'Home': 9}, ssidLast: {'Home': 200}),
      ProbeDev(mac: '00:00:00:00:00:03', first: 30, last: 300, count: 2, rssi: -80),
    ];
    String maker(String mac) => mac.endsWith('1') ? 'Alpha' : 'Beta';

    test('device sorts', () {
      List<String> macs(DevSort s, {String q = '', int? since, bool named = false}) => [
            for (final d in rankDevices(devs, sort: s, maker: maker, query: q, sinceMs: since, namedOnly: named)) d.mac.substring(15),
          ];
      expect(macs(DevSort.recent), ['03', '02', '01']);
      expect(macs(DevSort.networks), ['01', '02', '03']);
      expect(macs(DevSort.signal), ['02', '01', '03']);
      expect(macs(DevSort.probes), ['02', '01', '03']);
      expect(macs(DevSort.maker), ['01', '03', '02']);
      expect(macs(DevSort.recent, named: true), ['02', '01']);
      expect(macs(DevSort.recent, q: 'cafe'), ['01']);
      expect(macs(DevSort.recent, q: 'beta'), ['03', '02']);
      expect(macs(DevSort.recent, since: 150), ['03', '02']);
    });

    test('network ranking and askers', () {
      final nets = rankNetworks(devs, sort: NetSort.devices);
      expect([for (final n in nets) n.name], ['Home', 'Cafe']);
      expect(nets.first.devices, 2);
      expect(nets.first.asked, 12);
      expect(nets.first.last, 200);
      expect([for (final n in rankNetworks(devs, sort: NetSort.name)) n.name], ['Cafe', 'Home']);
      expect([for (final d in askersOf('Home', devs)) d.mac.substring(15)], ['02', '01']);
      expect(namesOf(devs.first), [('Home', 3), ('Cafe', 2)]);
      expect(summarizeNetwork(askersOf('Home', devs), maker).makers, [('Alpha', 1), ('Beta', 1)]);
    });
  });
}
