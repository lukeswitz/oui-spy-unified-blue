// Copyright (c) 2026 Luke Switzer
import 'dart:convert';
import 'dart:typed_data';

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// A KMZ is a zip holding doc.kml; this writes it stored (no compression).
Uint8List kmzFromKml(String kml) {
  final name = utf8.encode('doc.kml');
  final body = utf8.encode(kml);
  final crc = crc32(body);
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  u32(0x04034b50);
  u16(20);
  u16(0x0800);
  u16(0);
  u16(0);
  u16(0x21);
  u32(crc);
  u32(body.length);
  u32(body.length);
  u16(name.length);
  u16(0);
  out.add(name);
  out.add(body);

  final cdOffset = out.length;
  u32(0x02014b50);
  u16(20);
  u16(20);
  u16(0x0800);
  u16(0);
  u16(0);
  u16(0x21);
  u32(crc);
  u32(body.length);
  u32(body.length);
  u16(name.length);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  out.add(name);
  final cdSize = out.length - cdOffset;

  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(1);
  u16(1);
  u32(cdSize);
  u32(cdOffset);
  u16(0);
  return out.toBytes();
}
