import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';

List<int> _status(List<List<int>> entries, {List<int>? boards}) {
  final out = <int>[1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, entries.length];
  for (final e in entries) {
    out.addAll(e);
  }
  if (boards != null) out.addAll(boards);
  return out;
}

List<int> _entry(String id, int role) =>
    [...id.codeUnits, 0, role, 0x05, 0x01, 0x06, 0x00, 0x00];

void main() {
  test('old manager payload decodes with empty board', () {
    final s = BleProtocol.decodeMeshStatus(_status([_entry('AB12', 0)]));
    expect(s.liveNodes.single.id, 'AB12');
    expect(s.liveNodes.single.board, '');
    expect(s.liveNodes.single.fwVersion, 0x000601);
  });

  test('trailing board codes map per node in order', () {
    final s = BleProtocol.decodeMeshStatus(_status(
      [_entry('AB12', 0), _entry('CD34', 0), _entry('EF56', 1)],
      boards: [5, 7, 1],
    ));
    expect(s.liveNodes.map((n) => n.board).toList(),
        ['tdongle_c5', 'stickc_plus', 'xiao_s3']);
  });

  test('unknown board code decodes as empty', () {
    final s = BleProtocol.decodeMeshStatus(
        _status([_entry('AB12', 0)], boards: [200]));
    expect(s.liveNodes.single.board, '');
  });
}
