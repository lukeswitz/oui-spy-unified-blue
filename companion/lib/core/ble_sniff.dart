// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
//
// BLE Sniff: decodes the LE LL pcap records the BLE Sniff engine streams, and writes them back out as a
// Wireshark .pcap. Advert summary fields and the manufacturer table follow colonelpanichacks/unified-blue
// raw/blesniff.cpp (MIT), with the company IDs corrected to the Bluetooth SIG registry.
import 'dart:typed_data';

import 'package:oui_spy/core/classify/bt_sig_registry.dart';

const _recMagic = 0xCAFEBABE;
const _recEnd = 0xDEADBEEF;
const _phdrLen = 10;
const _aaLen = 4;
const _crcLen = 3;

const sniffFtAdvInd = 0x01;
const sniffFtAdvDirect = 0x02;
const sniffFtAdvNonconn = 0x04;
const sniffFtScanRsp = 0x08;
const sniffFtAdvScanInd = 0x10;
const sniffFtAddrPublic = 0x20;
const sniffFtAddrRandom = 0x40;
const sniffFtDefault = 0x7F;

/// Engine config op for BLE Sniff: [0x01][filter mask].
const sniffCfgFilter = 0x01;

class SniffAdvert {
  const SniffAdvert({
    required this.time,
    required this.channel,
    required this.rssi,
    required this.llType,
    required this.addrRandom,
    required this.addr,
    required this.advData,
    required this.name,
    required this.services,
    required this.mfrId,
    required this.connectable,
  });

  final DateTime time;
  final int channel;
  final int rssi;
  final int llType;
  final bool addrRandom;

  /// Advertiser address, most significant byte first.
  final List<int> addr;
  final Uint8List advData;
  final String name;
  final List<int> services;
  final int? mfrId;
  final bool connectable;

  String get macStr =>
      addr.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');

  String get llName => switch (llType) {
        0 => 'ADV_IND',
        1 => 'ADV_DIRECT',
        2 => 'ADV_NONCONN',
        3 => 'SCAN_REQ',
        4 => 'SCAN_RSP',
        5 => 'CONNECT_REQ',
        6 => 'ADV_SCAN',
        _ => 'ADV_?',
      };

  String get addrClass {
    if (!addrRandom) return 'pub';
    return switch ((addr[0] >> 6) & 3) {
      0 => 'rnd-nrp',
      1 => 'rnd-rpa',
      _ => 'rnd-s',
    };
  }

  String get mfrLabel => mfrId == null
      ? ''
      : '${mfrId!.toRadixString(16).padLeft(4, '0').toUpperCase()} (${sniffMfrName(mfrId!)})';

  String get servicesLabel =>
      services.map((u) => '0x${u.toRadixString(16).padLeft(4, '0').toUpperCase()}').join(',');
}

/// One record of the stream: device timestamp (microseconds since boot, 32-bit) and the LL frame.
class SniffRecord {
  const SniffRecord(this.deviceUs, this.frame);
  final int deviceUs;
  final Uint8List frame;
}

const _mfrNames = <int, String>{
  0x004C: 'Apple',
  0x0006: 'Microsoft',
  0x00E0: 'Google',
  0x0075: 'Samsung',
  0x0171: 'Amazon',
  0x038F: 'Xiaomi',
  0x0087: 'Garmin',
  0x05A7: 'Sonos',
  0x009E: 'Bose',
  0x02F2: 'GoPro',
  0x0059: 'Nordic',
  0x0131: 'Cypress',
  0x02E5: 'Espressif',
  0x000F: 'Broadcom',
  0x0001: 'Nokia',
  0x0157: 'Anhui Huami',
  0x0499: 'Ruuvi',
  0x034D: 'Axon/TASER',
  0x0D53: 'Luxottica (Meta/Ray-Ban)',
  0x08AA: 'DJI',
};

String sniffMfrName(int id) => _mfrNames[id] ?? BtSigRegistry.companies[id] ?? '?';

/// Splits the byte stream into records. Bytes before a magic, or a record with a bad end mark, are skipped.
class SniffRecordSplitter {
  Uint8List _buf = Uint8List(0);

  List<SniffRecord> add(Uint8List chunk) {
    final merged = Uint8List(_buf.length + chunk.length)
      ..setRange(0, _buf.length, _buf)
      ..setRange(_buf.length, _buf.length + chunk.length, chunk);
    final out = <SniffRecord>[];
    final bd = ByteData.sublistView(merged);
    var i = 0;
    while (i + 8 <= merged.length) {
      if (bd.getUint32(i, Endian.little) != _recMagic) {
        i++;
        continue;
      }
      final recLen = bd.getUint32(i + 4, Endian.little);
      if (recLen < 16 || recLen > 2500) {
        i++;
        continue;
      }
      final total = 8 + recLen + 4;
      if (i + total > merged.length) break;
      if (bd.getUint32(i + 8 + recLen, Endian.little) != _recEnd) {
        i++;
        continue;
      }
      final tsSec = bd.getUint32(i + 8, Endian.little);
      final tsUsec = bd.getUint32(i + 12, Endian.little);
      final incl = bd.getUint32(i + 16, Endian.little);
      if (incl > recLen - 16) {
        i++;
        continue;
      }
      out.add(SniffRecord(
        (tsSec * 1000000 + tsUsec) & 0xFFFFFFFF,
        Uint8List.fromList(merged.sublist(i + 24, i + 24 + incl)),
      ));
      i += total;
    }
    _buf = Uint8List.fromList(merged.sublist(i));
    if (_buf.length > 8192) _buf = Uint8List(0);
    return out;
  }
}

/// Decodes an LE LL frame with the 10-byte pseudo-header (LINKTYPE 256). Null when it is not an advertising frame.
SniffAdvert? decodeSniffFrame(Uint8List f, DateTime time) {
  const hdr = _phdrLen + _aaLen;
  if (f.length < hdr + 2 + 6 + _crcLen) return null;
  final h0 = f[hdr];
  final llType = h0 & 0x0F;
  final len = f[hdr + 1] & 0x3F;
  final end = hdr + 2 + len;
  if (len < 6 || end + _crcLen > f.length) return null;
  final advA = f.sublist(hdr + 2, hdr + 8);
  var dataStart = hdr + 8;
  if (llType == 1 && dataStart + 6 <= end) dataStart += 6;
  final adv = Uint8List.fromList(f.sublist(dataStart, end));

  var name = '';
  final services = <int>[];
  int? mfr;
  var i = 0;
  while (i < adv.length) {
    final l = adv[i];
    if (l == 0) {
      i++;
      continue;
    }
    if (i + 1 + l > adv.length) break;
    final type = adv[i + 1];
    final d = adv.sublist(i + 2, i + 1 + l);
    if ((type == 0x08 || type == 0x09) && name.isEmpty) {
      name = String.fromCharCodes([for (final c in d) c >= 0x20 && c < 0x7F ? c : 0x2E]);
    } else if (type == 0x02 || type == 0x03) {
      for (var k = 0; k + 1 < d.length; k += 2) {
        services.add(d[k] | (d[k + 1] << 8));
      }
    } else if (type == 0xFF && d.length >= 2 && mfr == null) {
      mfr = d[0] | (d[1] << 8);
    }
    i += 1 + l;
  }

  return SniffAdvert(
    time: time,
    channel: f[0],
    rssi: f[1] >= 128 ? f[1] - 256 : f[1],
    llType: llType,
    addrRandom: h0 & 0x40 != 0,
    addr: advA.reversed.toList(),
    advData: adv,
    name: name,
    services: services,
    mfrId: mfr,
    connectable: llType == 0 || llType == 1,
  );
}

/// Builds the Wireshark file: a classic pcap header plus records, with device timestamps mapped to phone time.
class SniffPcapWriter {
  SniffPcapWriter({required int startEpochUs}) : _startUs = startEpochUs;

  static const snaplen = 512;
  static const linkType = 256;

  final int _startUs;
  int? _firstDev;
  int _lastDev = 0;
  int _elapsed = 0;

  Uint8List header() {
    final bd = ByteData(24);
    bd.setUint32(0, 0xa1b2c3d4, Endian.little);
    bd.setUint16(4, 2, Endian.little);
    bd.setUint16(6, 4, Endian.little);
    bd.setUint32(16, snaplen, Endian.little);
    bd.setUint32(20, linkType, Endian.little);
    return bd.buffer.asUint8List();
  }

  Uint8List record(SniffRecord r) {
    if (_firstDev == null) {
      _firstDev = r.deviceUs;
      _lastDev = r.deviceUs;
    }
    _elapsed += (r.deviceUs - _lastDev) & 0xFFFFFFFF;
    _lastDev = r.deviceUs;
    final us = _startUs + _elapsed;
    final bd = ByteData(16 + r.frame.length);
    bd.setUint32(0, us ~/ 1000000, Endian.little);
    bd.setUint32(4, us % 1000000, Endian.little);
    bd.setUint32(8, r.frame.length, Endian.little);
    bd.setUint32(12, r.frame.length, Endian.little);
    final out = bd.buffer.asUint8List();
    out.setRange(16, 16 + r.frame.length, r.frame);
    return out;
  }
}
