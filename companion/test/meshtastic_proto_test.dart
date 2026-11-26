// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_proto.dart';
import 'package:oui_spy/core/meshtastic/pb.dart';

Uint8List _fromRadio(void Function(PbWriter w) f) {
  final w = PbWriter();
  f(w);
  return w.toBytes();
}

PbWriter _w(void Function(PbWriter w) f) {
  final w = PbWriter();
  f(w);
  return w;
}

void main() {
  group('wire format', () {
    test('varints, including a negative one, and fixed fields round trip', () {
      final w = PbWriter()
        ..uint(1, 300)
        ..uint(2, -1)
        ..fixed32(3, 0xDEADBEEF)
        ..sfixed32(4, -5)
        ..string(5, 'héllo')
        ..boolean(6, true);
      final f = pbRead(w.toBytes()).toList();
      expect(f.map((e) => e.number), [1, 2, 3, 4, 5, 6]);
      expect(f[0].value, 300);
      expect(f[1].int32, -1);
      expect(f[2].value, 0xDEADBEEF);
      expect(f[3].int32, -5);
      expect(f[4].text, 'héllo');
      expect(f[5].value, 1);
    });

    test('a field that runs past the end stops the read and keeps what came before', () {
      final good = (PbWriter()..uint(1, 7)).toBytes();
      final cut = Uint8List.fromList([...good, 0x12, 0x09, 1, 2]);
      expect(pbRead(cut).map((e) => e.number), [1]);
    });
  });

  group('encoding, against the byte layout of the official definitions', () {
    test('want_config_id is ToRadio field 3', () {
      expect(MeshtasticProto.encodeWantConfig(1), [0x18, 0x01]);
      expect(MeshtasticProto.encodeWantConfig(300), [0x18, 0xAC, 0x02]);
    });

    test('a text message is ToRadio.packet{to, channel, decoded{portnum 1, payload}, id, hop_limit}', () {
      final b = MeshtasticProto.encodeText('hi', channel: 1, id: 0x01020304);
      expect(b, [
        0x0A, 0x16, // ToRadio.packet, 22 bytes
        0x15, 0xFF, 0xFF, 0xFF, 0xFF, // to = broadcast (fixed32 field 2)
        0x18, 0x01, // channel = 1
        0x22, 0x06, 0x08, 0x01, 0x12, 0x02, 0x68, 0x69, // decoded: portnum 1, payload "hi"
        0x35, 0x04, 0x03, 0x02, 0x01, // id (fixed32 field 6)
        0x48, 0x03, // hop_limit = 3
      ]);
    });

    test('a direct text carries the node number in the to field', () {
      final b = MeshtasticProto.encodeText('hi', channel: 1, id: 1, to: 0x0A1B2C3D);
      final packet = pbRead(pbRead(b).single.data).toList();
      expect(packet.firstWhere((f) => f.number == 2).value, 0x0A1B2C3D);
    });

    test('channel 0 is left out, as proto3 does for a default value', () {
      final b = MeshtasticProto.encodeText('hi', channel: 0, id: 1);
      expect(pbRead(b).single.number, 1);
      final packet = pbRead(pbRead(b).single.data).toList();
      expect(packet.map((f) => f.number), [2, 4, 6, 9]);
    });

    test('a position is POSITION_APP data with 1e-7 degree integers', () {
      final b = MeshtasticProto.encodePosition(10.5, -20.25,
          altitude: 120, time: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true), channel: 2, id: 9);
      final packet = pbRead(pbRead(b).single.data).toList();
      final data = packet.firstWhere((f) => f.number == 4);
      final d = pbRead(data.data).toList();
      expect(d.firstWhere((f) => f.number == 1).value, 3);
      final pos = pbRead(d.firstWhere((f) => f.number == 2).data).toList();
      expect(pos.firstWhere((f) => f.number == 1).int32, 105000000);
      expect(pos.firstWhere((f) => f.number == 2).int32, -202500000);
      expect(pos.firstWhere((f) => f.number == 3).value, 120);
      expect(pos.firstWhere((f) => f.number == 4).value, 1700000000);
    });
  });

  group('decoding FromRadio', () {
    test('config_complete_id', () {
      final m = MeshtasticProto.decodeFromRadio(Uint8List.fromList([0x38, 0x2A]));
      expect(m, isA<FromConfigComplete>().having((e) => e.id, 'id', 42));
    });

    test('my_info and node_info', () {
      final my = MeshtasticProto.decodeFromRadio(_fromRadio((w) => w.message(3, _w((m) => m.uint(1, 0xA1B2C3D4)))));
      expect((my as FromMyInfo).nodeNum, 0xA1B2C3D4);
      final n = MeshtasticProto.decodeFromRadio(_fromRadio((w) => w.message(
          4,
          _w((m) => m
            ..uint(1, 0x01020304)
            ..message(2, _w((u) => u..string(2, 'North Gate')..string(3, 'NG')))
            ..fixed32(5, 1700000000)))));
      final node = (n as FromNodeInfo).node;
      expect((node.nodeNum, node.longName, node.shortName, node.lastHeard), (0x01020304, 'North Gate', 'NG', 1700000000));
      expect(node.id, '!01020304');
      expect(node.label, 'North Gate');
      expect(const MtNode(nodeNum: 255).label, '!000000ff');
    });

    test('channels: only a key of 16 bytes or more makes a channel private', () {
      MtChannel ch(int role, List<int> psk, String name) =>
          (MeshtasticProto.decodeFromRadio(_fromRadio((w) => w.message(
              10,
              _w((c) => c
                ..uint(1, 3)
                ..message(2, _w((s) => s..bytes(2, psk)..string(3, name)))
                ..uint(3, role))))) as FromChannel)
              .channel;
      expect(ch(1, [1], '').isPrivate, isFalse);
      expect(ch(1, [], 'Open').isPrivate, isFalse);
      expect(ch(0, List.filled(32, 7), 'Off').isPrivate, isFalse);
      expect(ch(2, List.filled(16, 7), 'Team').isPrivate, isTrue);
      expect(ch(2, List.filled(32, 7), 'Team').label, 'Team');
      expect(ch(1, [1], '').label, 'Channel 3');
    });

    test('a text packet, with signal', () {
      final snr = ByteData(4)..setFloat32(0, -7.5, Endian.little);
      final b = _fromRadio((w) => w.message(
          2,
          _w((p) => p
            ..fixed32(1, 0x01020304)
            ..fixed32(2, 0xFFFFFFFF)
            ..uint(3, 2)
            ..message(4, _w((d) => d..uint(1, 1)..bytes(2, [0x68, 0x69])))
            ..fixed32(6, 77)
            ..fixed32(7, 1700000000)
            ..fixed32(8, snr.getUint32(0, Endian.little))
            ..uint(12, -90))));
      final p = (MeshtasticProto.decodeFromRadio(b) as FromPacket).packet;
      expect((p.from, p.to, p.channel, p.id, p.portnum, p.rxTime), (0x01020304, 0xFFFFFFFF, 2, 77, 1, 1700000000));
      expect(String.fromCharCodes(p.payload), 'hi');
      expect(p.snr, -7.5);
      expect(p.rssi, -90);
    });

    test('anything else is ignored, and garbage does not throw', () {
      expect(MeshtasticProto.decodeFromRadio(_fromRadio((w) => w.message(5, _w((c) => c.uint(1, 1))))), isA<FromOther>());
      expect(MeshtasticProto.decodeFromRadio(Uint8List.fromList([0xFF, 0xFF, 0xFF])), isA<FromOther>());
      expect(MeshtasticProto.decodeFromRadio(Uint8List(0)), isA<FromOther>());
    });
  });
}
