// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:oui_spy/core/meshtastic/pb.dart';

/// The Meshtastic messages this app needs, written against the official definitions in
/// github.com/meshtastic/protobufs (meshtastic/mesh.proto, channel.proto, portnums.proto).
/// Field numbers used:
///   ToRadio:    packet = 1, want_config_id = 3
///   FromRadio:  id = 1, packet = 2, my_info = 3, node_info = 4, config_complete_id = 7, channel = 10
///   MeshPacket: from = 1 (fixed32), to = 2 (fixed32), channel = 3, decoded = 4, id = 6 (fixed32),
///               rx_time = 7 (fixed32), rx_snr = 8 (float), hop_limit = 9, want_ack = 10, rx_rssi = 12
///   Data:       portnum = 1, payload = 2
///   MyNodeInfo: my_node_num = 1
///   NodeInfo:   num = 1, user = 2, snr = 4 (float), last_heard = 5 (fixed32)
///   User:       id = 1, long_name = 2, short_name = 3
///   Position:   latitude_i = 1 (sfixed32), longitude_i = 2 (sfixed32), altitude = 3, time = 4 (fixed32)
///   Channel:    index = 1, settings = 2, role = 3 (0 disabled, 1 primary, 2 secondary)
///   ChannelSettings: psk = 2, name = 3
///   PortNum:    TEXT_MESSAGE_APP = 1, POSITION_APP = 3
class MeshtasticProto {
  const MeshtasticProto._();

  static const portText = 1;
  static const portPosition = 3;
  static const broadcast = 0xFFFFFFFF;
  static const maxTextBytes = 200;
  static const hopLimit = 3;

  /// Asks the radio to send everything it knows; it ends with a `config_complete_id` equal to [id].
  static Uint8List encodeWantConfig(int id) => (PbWriter()..uint(3, id)).toBytes();

  static Uint8List encodePacket({
    required int portnum,
    required List<int> payload,
    required int channel,
    required int id,
    int to = broadcast,
  }) {
    final data = PbWriter()
      ..uint(1, portnum)
      ..bytes(2, payload);
    final packet = PbWriter()..fixed32(2, to);
    if (channel != 0) packet.uint(3, channel);
    packet
      ..message(4, data)
      ..fixed32(6, id)
      ..uint(9, hopLimit);
    return (PbWriter()..message(1, packet)).toBytes();
  }

  static Uint8List encodeText(String text, {required int channel, required int id, int to = broadcast}) =>
      encodePacket(portnum: portText, payload: utf8.encode(text), channel: channel, id: id, to: to);

  static Uint8List encodePosition(double lat, double lon, {int? altitude, required DateTime time, required int channel, required int id}) {
    final p = PbWriter()
      ..sfixed32(1, (lat * 1e7).round())
      ..sfixed32(2, (lon * 1e7).round());
    if (altitude != null) p.uint(3, altitude);
    p.fixed32(4, time.millisecondsSinceEpoch ~/ 1000);
    return encodePacket(portnum: portPosition, payload: p.toBytes(), channel: channel, id: id);
  }

  static FromRadio decodeFromRadio(Uint8List b) {
    for (final f in pbRead(b)) {
      switch (f.number) {
        case 2 when f.wire == 2:
          return FromPacket(_packet(f.data));
        case 3 when f.wire == 2:
          for (final m in pbRead(f.data)) {
            if (m.number == 1) return FromMyInfo(m.value);
          }
          return const FromOther();
        case 4 when f.wire == 2:
          return FromNodeInfo(_node(f.data));
        case 7 when f.wire == 0:
          return FromConfigComplete(f.value);
        case 10 when f.wire == 2:
          return FromChannel(_channel(f.data));
      }
    }
    return const FromOther();
  }

  static MtPacket _packet(Uint8List b) {
    var from = 0, to = 0, channel = 0, id = 0, port = 0, rxTime = 0, hop = 0;
    double? snr;
    int? rssi;
    var payload = Uint8List(0);
    for (final f in pbRead(b)) {
      switch (f.number) {
        case 1:
          from = f.value;
        case 2:
          to = f.value;
        case 3:
          channel = f.value;
        case 4 when f.wire == 2:
          for (final d in pbRead(f.data)) {
            if (d.number == 1) port = d.value;
            if (d.number == 2 && d.wire == 2) payload = d.data;
          }
        case 6:
          id = f.value;
        case 7:
          rxTime = f.value;
        case 8 when f.wire == 5:
          snr = f.float32;
        case 9:
          hop = f.value;
        case 12:
          rssi = f.value.toSigned(32);
      }
    }
    return MtPacket(
        from: from, to: to, channel: channel, id: id, portnum: port, payload: payload, rxTime: rxTime, snr: snr, rssi: rssi, hopLimit: hop);
  }

  static MtNode _node(Uint8List b) {
    var nodeNum = 0, lastHeard = 0;
    var longName = '', shortName = '';
    double? snr;
    for (final f in pbRead(b)) {
      switch (f.number) {
        case 1:
          nodeNum = f.value;
        case 2 when f.wire == 2:
          for (final u in pbRead(f.data)) {
            if (u.number == 2 && u.wire == 2) longName = u.text;
            if (u.number == 3 && u.wire == 2) shortName = u.text;
          }
        case 4 when f.wire == 5:
          snr = f.float32;
        case 5:
          lastHeard = f.value;
      }
    }
    return MtNode(nodeNum: nodeNum, longName: longName, shortName: shortName, lastHeard: lastHeard, snr: snr);
  }

  static MtChannel _channel(Uint8List b) {
    var index = 0, role = 0, pskLength = 0;
    var name = '';
    for (final f in pbRead(b)) {
      switch (f.number) {
        case 1:
          index = f.value;
        case 2 when f.wire == 2:
          for (final s in pbRead(f.data)) {
            if (s.number == 2 && s.wire == 2) pskLength = s.data.length;
            if (s.number == 3 && s.wire == 2) name = s.text;
          }
        case 3:
          role = f.value;
      }
    }
    return MtChannel(index: index, role: role, name: name, pskLength: pskLength);
  }
}

sealed class FromRadio {
  const FromRadio();
}

class FromMyInfo extends FromRadio {
  const FromMyInfo(this.nodeNum);

  final int nodeNum;
}

class FromNodeInfo extends FromRadio {
  const FromNodeInfo(this.node);

  final MtNode node;
}

class FromChannel extends FromRadio {
  const FromChannel(this.channel);

  final MtChannel channel;
}

class FromConfigComplete extends FromRadio {
  const FromConfigComplete(this.id);

  final int id;
}

class FromPacket extends FromRadio {
  const FromPacket(this.packet);

  final MtPacket packet;
}

class FromOther extends FromRadio {
  const FromOther();
}

class MtPacket {
  const MtPacket({
    required this.from,
    required this.to,
    required this.channel,
    required this.id,
    required this.portnum,
    required this.payload,
    required this.rxTime,
    this.snr,
    this.rssi,
    this.hopLimit = 0,
  });

  final int from, to, channel, id, portnum, rxTime, hopLimit;
  final Uint8List payload;
  final double? snr;
  final int? rssi;
}

String meshtasticNodeId(int nodeNum) => '!${nodeNum.toRadixString(16).padLeft(8, '0')}';

class MtNode {
  const MtNode({required this.nodeNum, this.longName = '', this.shortName = '', this.lastHeard = 0, this.snr});

  final int nodeNum;
  final String longName, shortName;
  final int lastHeard;
  final double? snr;

  String get id => meshtasticNodeId(nodeNum);

  String get label => longName.isNotEmpty ? longName : (shortName.isNotEmpty ? shortName : id);
}

class MtChannel {
  const MtChannel({required this.index, required this.role, required this.name, required this.pskLength});

  final int index, role, pskLength;
  final String name;

  bool get active => role == 1 || role == 2;

  /// A channel with its own key (16 or 32 bytes). A channel with no key or the one-byte default key is the
  /// public one that any Meshtastic radio in range can read, so the app never sends on it.
  bool get isPrivate => active && pskLength >= 16;

  String get label => name.isNotEmpty ? name : (index == 0 ? 'LongFast' : 'Channel $index');
}

class MtText {
  const MtText({required this.from, required this.channel, required this.text, required this.at, this.snr, this.rssi});

  final int from, channel;
  final String text;
  final DateTime at;
  final double? snr;
  final int? rssi;
}
