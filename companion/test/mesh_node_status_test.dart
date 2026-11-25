// Copyright (c) 2026 Luke Switzer
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/mesh_node_info.dart';

List<int> _base(int nodes) {
  final out = <int>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, nodes];
  for (var i = 0; i < nodes; i++) {
    out.addAll([...'AB1${i + 2}'.codeUnits, 0, 0, 0x05, 0x01, 0x07, 0x00, 0x00]);
  }
  out.addAll(List.filled(nodes, 1));
  out.addAll(List.filled(nodes, 30));
  out.addAll([0, 0, 0, 0]);
  return out;
}

List<int> _detail(int idHi, int idLo,
        {int fw = 0x000702, int board = 1, int up = 3700, int macs = 5, int uuids = 2, int peers = 3, int age10 = 1}) =>
    [
      idHi, idLo,
      fw & 0xFF, (fw >> 8) & 0xFF, (fw >> 16) & 0xFF, (fw >> 24) & 0xFF,
      board,
      up & 0xFF, (up >> 8) & 0xFF, (up >> 16) & 0xFF, (up >> 24) & 0xFF,
      macs, uuids, peers, age10,
    ];

void main() {
  test('node detail block decodes after the key failure count', () {
    final d = _detail(0xAB, 0x12);
    final s = BleProtocol.decodeMeshStatus([..._base(1), BleProtocol.meshTlvNodeDetail, d.length, ...d]);
    final one = s.details.single;
    expect(one.id, 'AB12');
    expect(one.fwVersion, 0x000702);
    expect(one.board, 'xiao_s3');
    expect(one.uptimeS, 3700);
    expect(one.filterMacs, 5);
    expect(one.filterUuids, 2);
    expect(one.peerCount, 3);
    expect(one.ageS, 10);
  });

  test('two nodes decode in order', () {
    final d = [..._detail(0xAB, 0x12), ..._detail(0xCD, 0x34, macs: 9)];
    final s = BleProtocol.decodeMeshStatus([..._base(2), BleProtocol.meshTlvNodeDetail, d.length, ...d]);
    expect(s.details.map((e) => e.id).toList(), ['AB12', 'CD34']);
    expect(s.details.last.filterMacs, 9);
  });

  test('payload from older firmware has no details', () {
    expect(BleProtocol.decodeMeshStatus(_base(1)).details, isEmpty);
  });

  test('a block cut short by the link MTU is ignored', () {
    final d = _detail(0xAB, 0x12);
    final cut = [..._base(1), BleProtocol.meshTlvNodeDetail, d.length, ...d.take(8)];
    expect(BleProtocol.decodeMeshStatus(cut).details, isEmpty);
  });

  test('unknown blocks are skipped', () {
    final d = _detail(0xAB, 0x12);
    final s = BleProtocol.decodeMeshStatus([
      ..._base(1),
      0x7E, 2, 9, 9,
      BleProtocol.meshTlvNodeDetail, d.length, ...d,
    ]);
    expect(s.details.single.id, 'AB12');
  });

  test('status request encodes with and without a target', () {
    expect(BleProtocol.encodeNodeStatusRequest(null), [0x23, 0x00]);
    expect(BleProtocol.encodeNodeStatusRequest('AB12'), [0x23, 0x00, 0xFE, ...'AB12'.codeUnits, 0x00]);
  });

  List<int> push({int seq = 7, int macs = 6, int uuids = 1, int expected = 4, List<List<int>> results = const []}) {
    final body = [seq, macs, uuids, expected, results.length, for (final r in results) ...r];
    return [BleProtocol.meshTlvFilterPush, body.length, ...body];
  }

  test('filter push block decodes with per-node results', () {
    final s = BleProtocol.decodeMeshStatus([
      ..._base(1),
      ...push(results: [
        [0xAB, 0x12, 0, 6, 1],
        [0xCD, 0x34, 3, 5, 0],
      ]),
    ]);
    final p = s.filterPush!;
    expect(p.seq, 7);
    expect(p.macs, 6);
    expect(p.uuids, 1);
    expect(p.expected, 4);
    expect(p.results.map((r) => (r.id, r.status, r.filterMacs, r.filterUuids)).toList(),
        [('AB12', 0, 6, 1), ('CD34', 3, 5, 0)]);
  });

  test('filter push and node detail blocks decode together', () {
    final d = _detail(0xAB, 0x12);
    final s = BleProtocol.decodeMeshStatus([
      ..._base(1),
      ...push(results: [
        [0xAB, 0x12, 0, 6, 1]
      ]),
      BleProtocol.meshTlvNodeDetail, d.length, ...d,
    ]);
    expect(s.filterPush!.results.single.id, 'AB12');
    expect(s.details.single.id, 'AB12');
  });

  test('no filter push block means null', () {
    expect(BleProtocol.decodeMeshStatus(_base(1)).filterPush, isNull);
  });

  test('summary names refusals and silent nodes', () {
    String label(String id) => 'NODE-$id';
    final all = (seq: 1, macs: 2, uuids: 0, expected: 3, results: <MeshFilterResult>[
      (id: 'AB12', status: 0, filterMacs: 2, filterUuids: 0),
      (id: 'CD34', status: 0, filterMacs: 2, filterUuids: 0),
      (id: 'EF56', status: 0, filterMacs: 2, filterUuids: 0),
    ]);
    expect(filterPushSummary(all, label), 'On 3 of 3 nodes');
    final mixed = (seq: 1, macs: 2, uuids: 0, expected: 4, results: <MeshFilterResult>[
      (id: 'AB12', status: 0, filterMacs: 2, filterUuids: 0),
      (id: 'CD34', status: 3, filterMacs: 1, filterUuids: 0),
      (id: 'EF56', status: 0, filterMacs: 2, filterUuids: 0),
    ]);
    expect(filterPushSummary(mixed, label),
        'On 2 of 4 nodes; NODE-CD34 refused (list too long for it); 1 did not answer');
    final one = (seq: 1, macs: 2, uuids: 0, expected: 1, results: <MeshFilterResult>[
      (id: 'AB12', status: 1, filterMacs: 0, filterUuids: 0),
    ]);
    expect(filterPushSummary(one, label), 'On 0 of 1 node; NODE-AB12 refused (detector not on this build)');
    expect(filterPushSummary((seq: 1, macs: 0, uuids: 0, expected: 0, results: <MeshFilterResult>[]), label), isNull);
  });

  test('node result text', () {
    expect(nodeFilterResultText((id: 'AB12', status: 0, filterMacs: 5, filterUuids: 1)), 'watchlist: 6 filters');
    expect(nodeFilterResultText((id: 'AB12', status: 2, filterMacs: 5, filterUuids: 1)),
        'watchlist refused: detector turned off for it');
  });

  List<int> neighbors(List<(List<int>, List<(List<int>, int)>)> rows) {
    final body = <int>[];
    for (final (id, hears) in rows) {
      body.addAll([...id, hears.length]);
      for (final (pid, r) in hears) {
        body.addAll([...pid, r & 0xFF]);
      }
    }
    return [BleProtocol.meshTlvNeighbors, body.length, ...body];
  }

  test('neighbor block decodes rows, negative dBm and unknown strength', () {
    final s = BleProtocol.decodeMeshStatus([
      ..._base(1),
      ...neighbors([
        ([0xAB, 0x12], [([0xCD, 0x34], -60), ([0xEF, 0x56], -84)]),
        ([0xCD, 0x34], [([0xAB, 0x12], -128)]),
      ]),
    ]);
    expect(s.signal.map((r) => r.id).toList(), ['AB12', 'CD34']);
    expect(s.signal[0].hears.map((h) => (h.id, h.rssi)).toList(), [('CD34', -60), ('EF56', -84)]);
    expect(s.signal[1].hears.single.rssi, isNull);
  });

  test('neighbor block cut short drops the incomplete row', () {
    final full = neighbors([
      ([0xAB, 0x12], [([0xCD, 0x34], -60)]),
      ([0xCD, 0x34], [([0xAB, 0x12], -70), ([0xEF, 0x56], -72)]),
    ]);
    final cut = [..._base(1), ...full.sublist(0, full.length - 3)];
    cut[_base(1).length + 1] = full[1] - 3;
    final s = BleProtocol.decodeMeshStatus(cut);
    expect(s.signal.map((r) => r.id).toList(), ['AB12']);
  });

  test('older firmware has no signal rows', () {
    expect(BleProtocol.decodeMeshStatus(_base(1)).signal, isEmpty);
  });

  test('signal levels use the strong, good, weak, poor bands', () {
    expect(signalLevel(-45), SignalLevel.strong);
    expect(signalLevel(-60), SignalLevel.strong);
    expect(signalLevel(-61), SignalLevel.good);
    expect(signalLevel(-70), SignalLevel.good);
    expect(signalLevel(-71), SignalLevel.weak);
    expect(signalLevel(-80), SignalLevel.weak);
    expect(signalLevel(-81), SignalLevel.poor);
    expect(signalLevel(null), SignalLevel.heard);
  });

  test('grid axes list reporters first, then peers that only get heard; cells are asymmetric', () {
    final rows = <MeshSignalRow>[
      (id: 'AB12', hears: [(id: 'CD34', rssi: -55), (id: 'EF56', rssi: -90)]),
      (id: 'CD34', hears: [(id: 'AB12', rssi: -75)]),
    ];
    expect(signalGridIds(rows), ['AB12', 'CD34', 'EF56']);
    expect(signalCell(rows, 'AB12', 'CD34')!.rssi, -55);
    expect(signalCell(rows, 'CD34', 'AB12')!.rssi, -75);
    expect(signalCell(rows, 'CD34', 'EF56'), isNull);
    expect(signalCell(rows, 'EF56', 'AB12'), isNull);
  });

  test('formatters', () {
    expect(formatFwVersion(0x000702), '0.7.2');
    expect(formatUptime(45), '45s');
    expect(formatUptime(3700), '1h 1m');
    expect(formatUptime(200000), '2d 7h');
    expect(formatAge(4), 'just now');
    expect(formatAge(125), '2m ago');
    final d = (
      id: 'AB12',
      fwVersion: 0x000702,
      board: 'xiao_s3',
      uptimeS: 3700,
      filterMacs: 5,
      filterUuids: 1,
      peerCount: 1,
      ageS: 0,
    );
    expect(nodeDetailSummary(d), '6 filters  ·  up 1h 1m');
    expect(nodeDetailLines(d, 30)[3], 'Hears 1 peer');
  });
}
