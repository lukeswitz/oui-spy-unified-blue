// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/mesh_node_info.dart';

List<int> _base() => [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

List<int> _tlv({int current = 1, int state = 0, int target = 0, int epoch = 0, List<List<int>> rows = const []}) {
  final body = [current, state, target, epoch, rows.length, for (final r in rows) ...r];
  return [BleProtocol.meshTlvChannel, body.length, ...body];
}

String _label(String id) => 'NODE-$id';

void main() {
  test('set channel command carries the channel and the force flag', () {
    expect(BleProtocol.encodeSetMeshChannel(6), [0x24, 0x00, 6, 0]);
    expect(BleProtocol.encodeSetMeshChannel(11, force: true), [0x24, 0x00, 11, 1]);
    expect(() => BleProtocol.encodeSetMeshChannel(0), throwsArgumentError);
    expect(() => BleProtocol.encodeSetMeshChannel(12), throwsArgumentError);
  });

  test('idle channel block decodes the current channel', () {
    final s = BleProtocol.decodeMeshStatus([..._base(), ..._tlv(current: 6)]);
    final c = s.channel!;
    expect(c.current, 6);
    expect(channelState(c), MeshChannelState.idle);
    expect(c.rows, isEmpty);
    expect(channelChangeSummary(c, _label), isNull);
    expect(channelChangeRunning(c), isFalse);
  });

  test('a change in progress lists each node with its confirm and follow flags', () {
    final s = BleProtocol.decodeMeshStatus([
      ..._base(),
      ..._tlv(current: 1, state: 1, target: 6, epoch: 9, rows: [
        [0xAB, 0x12, 0x01],
        [0xCD, 0x34, 0x00],
      ]),
    ]);
    final c = s.channel!;
    expect(c.target, 6);
    expect(c.epoch, 9);
    expect(channelChangeRunning(c), isTrue);
    expect(c.rows.map((r) => (r.id, r.confirmed, r.followed)).toList(), [('AB12', true, false), ('CD34', false, false)]);
    expect(channelChangeSummary(c, _label), 'Asking the nodes to move to channel 6: 1 of 2 confirmed');
    expect(nodeChannelText(c, 'AB12'), 'channel 6: confirmed');
    expect(nodeChannelText(c, 'CD34'), 'channel 6: waiting');
    expect(nodeChannelText(c, 'EF56'), isNull);
  });

  test('after the switch a node that has not followed is called out', () {
    final s = BleProtocol.decodeMeshStatus([
      ..._base(),
      ..._tlv(current: 6, state: 3, target: 6, epoch: 9, rows: [
        [0xAB, 0x12, 0x03],
        [0xCD, 0x34, 0x01],
      ]),
    ]);
    final c = s.channel!;
    expect(channelChangeSummary(c, _label),
        'Moved to channel 6: 1 of 2 nodes follow; NODE-CD34 will find the fleet again on its own');
    expect(nodeChannelText(c, 'AB12'), 'on channel 6');
    expect(nodeChannelText(c, 'CD34'), 'not on channel 6 yet');
    expect(channelChangeUnanswered(c), isEmpty);
  });

  test('all nodes following reads as done', () {
    final c = BleProtocol.decodeMeshStatus([
      ..._base(),
      ..._tlv(current: 6, state: 3, target: 6, epoch: 1, rows: [
        [0xAB, 0x12, 0x03],
      ]),
    ]).channel!;
    expect(channelChangeSummary(c, _label), 'Moved to channel 6: all 1 node follows');
  });

  test('a failed change names the nodes that did not answer', () {
    final c = BleProtocol.decodeMeshStatus([
      ..._base(),
      ..._tlv(current: 1, state: 4, target: 6, epoch: 2, rows: [
        [0xAB, 0x12, 0x01],
        [0xCD, 0x34, 0x00],
      ]),
    ]).channel!;
    expect(channelChangeSummary(c, _label), 'Stayed on channel 1: NODE-CD34 did not answer');
    expect(channelChangeUnanswered(c), ['CD34']);
    expect(nodeChannelText(c, 'CD34'), 'did not answer the channel move');
    expect(nodeChannelText(c, 'AB12'), 'channel move canceled');
  });

  test('payload from older firmware has no channel block', () {
    expect(BleProtocol.decodeMeshStatus(_base()).channel, isNull);
  });

  test('a channel block cut short by the link MTU is ignored', () {
    final t = _tlv(current: 6, rows: [
      [0xAB, 0x12, 0x01],
    ]);
    expect(BleProtocol.decodeMeshStatus([..._base(), ...t.take(t.length - 2)]).channel, isNull);
  });

  test('an unknown state byte falls back to idle', () {
    final c = BleProtocol.decodeMeshStatus([..._base(), ..._tlv(state: 77)]).channel!;
    expect(channelState(c), MeshChannelState.idle);
  });
}
