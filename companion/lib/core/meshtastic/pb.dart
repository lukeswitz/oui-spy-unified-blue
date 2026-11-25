// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

/// Protocol Buffers wire format, just enough for the Meshtastic messages in meshtastic_proto.dart.
/// Wire types: 0 varint, 1 fixed64, 2 length-delimited, 5 fixed32.
class PbWriter {
  final _out = BytesBuilder(copy: false);

  Uint8List toBytes() => _out.toBytes();

  void _varint(int v) {
    var n = v;
    while (n < 0 || n > 0x7F) {
      _out.addByte((n & 0x7F) | 0x80);
      n = n >>> 7;
    }
    _out.addByte(n);
  }

  void _key(int field, int wire) => _varint((field << 3) | wire);

  void uint(int field, int v) {
    _key(field, 0);
    _varint(v);
  }

  void boolean(int field, bool v) => uint(field, v ? 1 : 0);

  void fixed32(int field, int v) {
    _key(field, 5);
    final b = ByteData(4)..setUint32(0, v & 0xFFFFFFFF, Endian.little);
    _out.add(b.buffer.asUint8List());
  }

  void sfixed32(int field, int v) {
    _key(field, 5);
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    _out.add(b.buffer.asUint8List());
  }

  void bytes(int field, List<int> v) {
    _key(field, 2);
    _varint(v.length);
    _out.add(v);
  }

  void string(int field, String v) => bytes(field, utf8.encode(v));

  void message(int field, PbWriter m) => bytes(field, m.toBytes());
}

class PbField {
  const PbField(this.number, this.wire, this.value, this.data);

  final int number;
  final int wire;

  /// The number for varint and fixed fields (fixed32 as unsigned).
  final int value;

  /// The payload of a length-delimited field.
  final Uint8List data;

  int get int32 => value.toSigned(32);

  String get text => utf8.decode(data, allowMalformed: true);

  double get float32 => (ByteData(4)..setUint32(0, value, Endian.little)).getFloat32(0, Endian.little);
}

/// Reads every field of one message. Unknown fields are returned like any other; a field that runs past the end
/// stops the read and what came before it is kept.
Iterable<PbField> pbRead(Uint8List b) sync* {
  var i = 0;
  int? varint() {
    var shift = 0, v = 0;
    while (i < b.length && shift < 64) {
      final c = b[i++];
      v |= (c & 0x7F) << shift;
      if (c & 0x80 == 0) return v;
      shift += 7;
    }
    return null;
  }

  final empty = Uint8List(0);
  while (i < b.length) {
    final key = varint();
    if (key == null) return;
    final number = key >> 3, wire = key & 7;
    switch (wire) {
      case 0:
        final v = varint();
        if (v == null) return;
        yield PbField(number, wire, v, empty);
      case 1:
        if (i + 8 > b.length) return;
        final v = ByteData.sublistView(b, i, i + 8).getUint64(0, Endian.little);
        i += 8;
        yield PbField(number, wire, v, empty);
      case 2:
        final n = varint();
        if (n == null || n < 0 || i + n > b.length) return;
        yield PbField(number, wire, 0, Uint8List.sublistView(b, i, i + n));
        i += n;
      case 5:
        if (i + 4 > b.length) return;
        final v = ByteData.sublistView(b, i, i + 4).getUint32(0, Endian.little);
        i += 4;
        yield PbField(number, wire, v, empty);
      default:
        return;
    }
  }
}
