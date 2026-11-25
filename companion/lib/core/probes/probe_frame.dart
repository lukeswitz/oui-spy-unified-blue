// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:oui_spy/core/probes/probe_intel.dart';

class ProbeSighting {
  const ProbeSighting({required this.mac, required this.ssid, required this.rssi, required this.freqMhz});
  final String mac;
  final String? ssid;
  final int rssi;
  final int freqMhz;
}

const int _recHeader = 16;
const int _radiotapFixed = 8;

const List<(int, int)> _radiotapFields = [
  (8, 8),
  (1, 1),
  (1, 1),
  (2, 4),
  (1, 2),
  (1, 1),
  (1, 1),
  (2, 2),
  (2, 2),
  (2, 2),
  (1, 1),
  (1, 1),
  (1, 1),
  (1, 1),
  (2, 2),
];

({int freq, int? rssi}) _radiotap(ByteData bd, int off, int len) {
  var present = bd.getUint32(off + 4, Endian.little);
  var pos = off + _radiotapFixed;
  var ext = present;
  while ((ext & 0x80000000) != 0 && pos + 4 <= off + len) {
    ext = bd.getUint32(pos, Endian.little);
    pos += 4;
  }
  var freq = 0;
  int? rssi;
  for (var bit = 0; bit < _radiotapFields.length; bit++) {
    if ((present & (1 << bit)) == 0) continue;
    final (align, size) = _radiotapFields[bit];
    final rel = pos - off;
    final pad = (align - (rel % align)) % align;
    pos += pad;
    if (pos + size > off + len) break;
    if (bit == 3) freq = bd.getUint16(pos, Endian.little);
    if (bit == 5) rssi = bd.getInt8(pos);
    pos += size;
  }
  return (freq: freq, rssi: rssi);
}

/// Parses one record from the board's PCAP stream (16-byte pcap record header, radiotap, 802.11 frame)
/// and returns the probe request in it, or null for any other frame.
ProbeSighting? parseProbeRecord(Uint8List rec) {
  if (rec.length < _recHeader + _radiotapFixed) return null;
  final bd = ByteData.sublistView(rec);
  final rtLen = bd.getUint16(_recHeader + 2, Endian.little);
  if (rtLen < _radiotapFixed || rec.length < _recHeader + rtLen + 24) return null;
  final f = _recHeader + rtLen;
  if ((rec[f] & 0xFC) != 0x40) return null;
  final rt = _radiotap(bd, _recHeader, rtLen);
  final rssi = rt.rssi ?? (rtLen == 18 ? bd.getInt8(_recHeader + 14) : 0);
  final mac = [for (var i = 0; i < 6; i++) rec[f + 10 + i].toRadixString(16).padLeft(2, '0')].join(':').toUpperCase();
  String? ssid;
  var i = f + 24;
  while (i + 2 <= rec.length) {
    final id = rec[i];
    final l = rec[i + 1];
    if (i + 2 + l > rec.length) break;
    if (id == 0) {
      ssid = cleanSsid(Uint8List.sublistView(rec, i + 2, i + 2 + l));
      break;
    }
    i += 2 + l;
  }
  return ProbeSighting(mac: mac, ssid: ssid, rssi: rssi, freqMhz: rt.freq);
}
