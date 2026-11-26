// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_link.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_proto.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/core/meshtastic/pb.dart';
import 'package:shared_preferences/shared_preferences.dart';

PbWriter w(void Function(PbWriter w) f) {
  final x = PbWriter();
  f(x);
  return x;
}

Uint8List myInfo(int n) => (PbWriter()..message(3, w((m) => m.uint(1, n)))).toBytes();

Uint8List nodeInfo(int n, String name) =>
    (PbWriter()..message(4, w((m) => m..uint(1, n)..message(2, w((u) => u.string(2, name)))))).toBytes();

Uint8List channel(int index, int role, int pskLen, String name) => (PbWriter()
      ..message(
          10,
          w((c) => c
            ..uint(1, index)
            ..message(2, w((s) => s..bytes(2, List.filled(pskLen, 9))..string(3, name)))
            ..uint(3, role))))
    .toBytes();

Uint8List done(int id) => (PbWriter()..uint(7, id)).toBytes();

Uint8List packet({required int from, required int ch, int port = 1, String text = 'hello'}) => (PbWriter()
      ..message(
          2,
          w((p) => p
            ..fixed32(1, from)
            ..fixed32(2, 0xFFFFFFFF)
            ..uint(3, ch)
            ..message(4, w((d) => d..uint(1, port)..bytes(2, text.codeUnits)))
            ..fixed32(6, 5))))
    .toBytes();

class FakeLink implements MeshtasticLink {
  final writes = <Uint8List>[];
  final queue = <Uint8List>[];
  final _num = StreamController<void>.broadcast();
  final _closed = Completer<void>();
  bool answerSetup = true;
  List<Uint8List> setup = [];
  bool closedCalled = false;
  bool failWrites = false;

  @override
  Stream<void> get fromNum => _num.stream;

  void notify(List<Uint8List> frames) {
    queue.addAll(frames);
    _num.add(null);
  }

  @override
  Future<Uint8List> readFromRadio() async {
    await Future<void>.delayed(Duration.zero);
    return queue.isEmpty ? Uint8List(0) : queue.removeAt(0);
  }

  @override
  Future<void> writeToRadio(Uint8List bytes) async {
    if (failWrites) throw StateError('write failed');
    writes.add(bytes);
    final id = pbRead(bytes).where((f) => f.number == 3).firstOrNull?.value;
    if (id != null && answerSetup) {
      queue.addAll(setup);
      queue.add(done(id));
    }
  }

  @override
  Future<void> get closed => _closed.future;

  void drop() => _closed.complete();

  @override
  Future<void> close() async {
    closedCalled = true;
    if (!_closed.isCompleted) _closed.complete();
  }
}

class FakeBle implements MeshtasticBle {
  FakeBle(this.link);

  final FakeLink link;
  List<MtRadioFound> found = const [MtRadioFound(id: 'radio-1', name: 'Meshtastic_a1b2', rssi: -60)];
  Object? openError;
  int scans = 0;

  @override
  Future<List<MtRadioFound>> scan({Duration timeout = const Duration(seconds: 8)}) async {
    scans++;
    return found;
  }

  int opens = 0;

  @override
  Future<MeshtasticLink> open(String id) async {
    opens++;
    if (openError != null) throw openError!;
    return link;
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late FakeLink link;
  late FakeBle ble;

  MeshtasticNotifier make({Duration timeout = const Duration(seconds: 2)}) =>
      MeshtasticNotifier(ble: ble, random: Random(1), setupTimeout: timeout, clock: () => DateTime.utc(2026, 1, 1));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    link = FakeLink()
      ..setup = [
        myInfo(0x0A0B0C0D),
        nodeInfo(0x01020304, 'North Gate'),
        nodeInfo(0x0A0B0C0D, 'Me'),
        channel(0, 1, 1, ''),
        channel(1, 2, 32, 'Team'),
        channel(2, 2, 0, 'Open'),
        channel(3, 0, 32, 'Off'),
      ];
    ble = FakeBle(link);
  });

  Future<MeshtasticNotifier> ready() async {
    final n = make();
    await settle();
    await n.connect(radio: ble.found.first);
    return n;
  }

  test('scanning lists radios and sends nothing', () async {
    final n = make();
    await n.scan();
    expect(n.state.found.single.name, 'Meshtastic_a1b2');
    expect(n.state.link, MtLinkState.off);
    expect(link.writes, isEmpty);
    n.dispose();
  });

  test('connecting asks for the radio setup and nothing else, then reads what it sends', () async {
    final n = await ready();
    expect(n.state.link, MtLinkState.ready);
    expect(link.writes, hasLength(1));
    expect(pbRead(link.writes.single).single.number, 3);
    expect(n.state.myNum, 0x0A0B0C0D);
    expect(n.state.nodes.keys, containsAll([0x01020304, 0x0A0B0C0D]));
    expect(n.state.channels.map((c) => c.index), [0, 1, 2, 3]);
    expect(n.state.privateChannels.map((c) => c.label), ['Team']);
    expect(n.state.radioId, 'radio-1');
    n.dispose();
  });

  test('only a private channel can be chosen, and the choice is kept', () async {
    final n = await ready();
    expect(await n.selectChannel(0), contains('no key of its own'));
    expect(await n.selectChannel(2), contains('no key of its own'));
    expect(await n.selectChannel(3), contains('no key of its own'));
    expect(await n.selectChannel(9), contains('no key of its own'));
    expect(n.state.channel, isNull);
    expect(await n.selectChannel(1), isNull);
    expect(n.state.channel!.label, 'Team');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('mt_channel'), 1);
    n.dispose();
  });

  test('a text goes out only after a private channel is chosen, on that channel', () async {
    final n = await ready();
    expect(await n.sendText('hi'), 'Pick a private channel first');
    expect(link.writes, hasLength(1));
    await n.selectChannel(1);
    expect(await n.sendText('hi'), isNull);
    expect(link.writes, hasLength(2));
    final packet = pbRead(pbRead(link.writes.last).single.data).toList();
    expect(packet.firstWhere((f) => f.number == 3).value, 1);
    expect(packet.firstWhere((f) => f.number == 2).value, MeshtasticProto.broadcast);
    expect((n.state.sent, n.state.lastSent), (1, DateTime.utc(2026, 1, 1)));
    n.dispose();
  });

  test('an alert goes to the channel, or as one direct packet to each node, and only on a private channel', () async {
    final n = await ready();
    expect(await n.sendAlert('a'), 'Pick a private channel first');
    await n.selectChannel(1);
    expect(await n.sendAlert('to all'), isNull);
    var packet = pbRead(pbRead(link.writes.last).single.data).toList();
    expect(packet.firstWhere((f) => f.number == 2).value, MeshtasticProto.broadcast);
    expect(await n.sendAlert('to two', to: [0x0A1B2C3D, 0x01020304]), isNull);
    expect(link.writes, hasLength(4));
    packet = pbRead(pbRead(link.writes[2]).single.data).toList();
    expect(packet.firstWhere((f) => f.number == 2).value, 0x0A1B2C3D);
    expect(packet.firstWhere((f) => f.number == 3).value, 1);
    packet = pbRead(pbRead(link.writes[3]).single.data).toList();
    expect(packet.firstWhere((f) => f.number == 2).value, 0x01020304);
    expect(n.state.sent, 3);
    expect(await n.sendAlert('a' * 201), 'Messages are up to 200 characters');
    link.failWrites = true;
    expect(await n.sendAlert('x', to: [5]), startsWith("Not sent: the radio didn't take it"));
    await n.disconnect();
    expect(await n.sendAlert('x'), 'The radio is not connected');
    n.dispose();
  });

  test('empty, over-long and disconnected sends are refused', () async {
    final n = await ready();
    await n.selectChannel(1);
    expect(await n.sendText('   '), 'Type a message first');
    expect(await n.sendText('a' * 201), 'Messages are up to 200 characters');
    expect(await n.sendText('é' * 101), 'Messages are up to 200 characters');
    expect(await n.sendText('a' * 200), isNull);
    link.failWrites = true;
    expect(await n.sendText('x'), startsWith("Not sent: the radio didn't take it"));
    expect(n.state.sent, 1);
    await n.disconnect();
    expect(await n.sendText('x'), 'The radio is not connected');
    n.dispose();
  });

  test('a position needs a valid fix and the same private channel', () async {
    final n = await ready();
    expect(await n.sendPosition(10, 20), 'Pick a private channel first');
    await n.selectChannel(1);
    expect(await n.sendPosition(0, 0), 'No valid position yet');
    expect(await n.sendPosition(91, 0), 'No valid position yet');
    expect(await n.sendPosition(10, 20, altitude: 5), isNull);
    final packet = pbRead(pbRead(link.writes.last).single.data).toList();
    final data = pbRead(packet.firstWhere((f) => f.number == 4).data).toList();
    expect(data.firstWhere((f) => f.number == 1).value, MeshtasticProto.portPosition);
    n.dispose();
  });

  test('the inbox keeps texts from private channels only, and a notification starts a read', () async {
    final n = await ready();
    link.notify([
      packet(from: 0x01020304, ch: 1, text: 'on the team channel'),
      packet(from: 0x01020304, ch: 0, text: 'on the public channel'),
      packet(from: 0x01020304, ch: 2, text: 'on a channel with no key'),
      packet(from: 0x01020304, ch: 1, port: 3, text: 'a position, not text'),
      packet(from: 0x0A0B0C0D, ch: 1, text: 'my own echo'),
    ]);
    await settle();
    expect(n.state.inbox.map((m) => m.text), ['on the team channel']);
    expect(n.state.heard, 1);
    n.dispose();
  });

  test('a radio that never finishes its setup is an error with the pairing hint, and is disconnected', () async {
    link.answerSetup = false;
    final n = make(timeout: const Duration(milliseconds: 150));
    await settle();
    await n.connect(radio: ble.found.first);
    expect(n.state.link, MtLinkState.error);
    expect(n.state.error, contains('never finished sending its setup'));
    expect(n.state.error, contains('123456'));
    expect(link.closedCalled, isTrue);
    n.dispose();
  });

  test('a radio that cannot be reached says so', () async {
    ble.openError = StateError('timeout');
    final n = make();
    await settle();
    await n.connect(radio: ble.found.first);
    expect(n.state.link, MtLinkState.error);
    expect(n.state.error, contains('out of range, or held by another phone'));
    n.dispose();
  });

  test('losing the radio shows an error', () async {
    final n = await ready();
    link.drop();
    await settle();
    expect(n.state.link, MtLinkState.error);
    expect(n.state.error, 'the radio disconnected');
    n.dispose();
  });

  test('the radio and channel survive a restart, and forget clears them and disconnects', () async {
    var n = await ready();
    await n.selectChannel(1);
    n.dispose();
    link = FakeLink()..setup = link.setup;
    ble = FakeBle(link);
    n = make();
    await settle();
    expect((n.state.radioId, n.state.radioName, n.state.channelIndex), ('radio-1', 'Meshtastic_a1b2', 1));
    expect(n.state.link, MtLinkState.off);
    expect(link.writes, isEmpty);
    await n.connect();
    expect(n.state.link, MtLinkState.ready);
    expect(n.state.channel!.label, 'Team');
    await n.forget();
    expect(link.closedCalled, isTrue);
    expect(n.state.hasRadio, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('mt_')), isEmpty);
    n.dispose();
  });

  test('auto-connect opens the saved radio at start and retries after a failure until disconnect', () async {
    SharedPreferences.setMockInitialValues({'mt_radio_id': 'radio-1', 'mt_radio_name': 'Meshtastic_a1b2'});
    ble.openError = Exception('out of range');
    final n = MeshtasticNotifier(
        ble: ble,
        random: Random(1),
        clock: () => DateTime.utc(2026, 1, 1),
        autoConnect: true,
        retryAfter: const Duration(milliseconds: 30));
    await settle();
    expect(ble.opens, greaterThanOrEqualTo(1));
    final before = ble.opens;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(ble.opens, greaterThan(before));
    await n.disconnect();
    final stopped = ble.opens;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(ble.opens, stopped);
    n.dispose();
  });

  test('without auto-connect a saved radio is not opened at start', () async {
    SharedPreferences.setMockInitialValues({'mt_radio_id': 'radio-1'});
    final n = make();
    await settle();
    expect(ble.opens, 0);
    n.dispose();
  });
}
