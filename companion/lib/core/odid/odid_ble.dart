import 'dart:convert';
import 'dart:typed_data';

import 'package:oui_spy/core/models/detection.dart';

const _msgSize = 25;
const _typeBasicId = 0;
const _typeLocation = 1;
const _typeSelfId = 3;
const _typeSystem = 4;
const _typeOperatorId = 5;
const _typePack = 0xF;
const _invAlt = -1000.0;
const _invSpeedH = 255.0;
const _invSpeedV = 63.0;
const _invDir = 361.0;
const _invTimestamp = 0xFFFF;

List<List<int>> odidMessagesFromAdv(List<int> adv) {
  final out = <List<int>>[];
  var i = 0;
  while (i + 1 < adv.length) {
    final len = adv[i];
    if (len == 0 || i + 1 + len > adv.length) break;
    final type = adv[i + 1];
    final data = adv.sublist(i + 2, i + 1 + len);
    i += 1 + len;
    if (type != 0x16 || data.length < 4 + _msgSize) continue;
    if (data[0] != 0xFA || data[1] != 0xFF || data[2] != 0x0D) continue;
    out.addAll(_messagesFromBody(data.sublist(4)));
  }
  return out;
}

List<List<int>> odidMessagesFromVendorIe(List<int> ie) {
  if (ie.length < 5 + _msgSize || ie[3] != 0x0D) return const [];
  final fa = ie[0] == 0xFA && ie[1] == 0x0B && ie[2] == 0xBC;
  final asd = ie[0] == 0x90 && ie[1] == 0x3A && ie[2] == 0xE6;
  if (!fa && !asd) return const [];
  return _messagesFromBody(ie.sublist(5));
}

List<List<int>> _messagesFromBody(List<int> body) {
  if (body.length < _msgSize) return const [];
  if (body[0] >> 4 != _typePack) return [body.sublist(0, _msgSize)];
  if (body.length < 3 || body[1] != _msgSize) return const [];
  final out = <List<int>>[];
  for (var m = 0; m < body[2]; m++) {
    final start = 3 + m * _msgSize;
    if (start + _msgSize > body.length) break;
    out.add(body.sublist(start, start + _msgSize));
  }
  return out;
}

String _str(List<int> b) {
  final end = b.indexOf(0);
  return latin1.decode(end < 0 ? b : b.sublist(0, end), allowInvalid: true).trim();
}

bool _printable(List<int> b) => b.any((c) => c >= 0x20 && c <= 0x7E);

double _alt(int enc) => enc * 0.5 - 1000;
int? _altOut(double v) => v == _invAlt ? null : v.round();

class _BasicId {
  _BasicId(this.idType, this.uaType, this.raw);
  final int idType;
  final int uaType;
  final List<int> raw;
  bool get plausible => idType != 0 && uaType != 0 && _printable(raw);
}

class OdidState {
  final List<_BasicId> _basic = [];
  OdidExtension ext = const OdidExtension();

  OdidExtension? get plausible {
    for (final b in _basic) {
      if (b.plausible) {
        return ext.copyWith(uavId: _str(b.raw), idType: b.idType, uaType: b.uaType);
      }
    }
    return null;
  }

  void apply(List<int> m) {
    final bd = ByteData.sublistView(Uint8List.fromList(m));
    switch (m[0] >> 4) {
      case _typeBasicId:
        final idType = m[1] >> 4;
        final b = _BasicId(idType, m[1] & 0x0F, m.sublist(2, 22));
        final slot = _basic.indexWhere((x) => x.idType == idType || x.idType == 0);
        if (slot >= 0) {
          _basic[slot] = b;
        } else if (_basic.length < 2) {
          _basic.add(b);
        }
      case _typeLocation:
        final flags = m[1];
        final speedMult = flags & 0x01;
        final ew = (flags >> 1) & 0x01;
        final dir = (ew == 1 ? m[2] + 180 : m[2]).toDouble();
        final speed = speedMult == 1 ? m[3] * 0.75 + 255 * 0.25 : m[3] * 0.25;
        final vspeed = bd.getInt8(4) * 0.5;
        final ts = bd.getUint16(21, Endian.little);
        ext = ext.copyWith(
          status: flags >> 4,
          heightType: (flags >> 2) & 0x01,
          droneHeading: dir == _invDir ? null : dir.round(),
          droneSpeed: speed == _invSpeedH ? null : speed.round(),
          vertSpeed: vspeed == _invSpeedV ? null : vspeed.round(),
          droneLat: bd.getInt32(5, Endian.little) * 1e-7,
          droneLon: bd.getInt32(9, Endian.little) * 1e-7,
          altitudeBaro: _altOut(_alt(bd.getUint16(13, Endian.little))),
          altitudeMsl: _altOut(_alt(bd.getUint16(15, Endian.little))),
          heightAgl: _altOut(_alt(bd.getUint16(17, Endian.little))),
          horizAcc: m[19] & 0x0F,
          vertAcc: m[19] >> 4,
          speedAcc: m[20] & 0x0F,
          baroAcc: m[20] >> 4,
          locTimestamp: ts == _invTimestamp || ts > 36000 ? null : ts,
        );
      case _typeSelfId:
        ext = ext.copyWith(selfIdType: m[1], selfId: _str(m.sublist(2, 25)));
      case _typeSystem:
        final flags = m[1];
        final lat = bd.getInt32(2, Endian.little) * 1e-7;
        final lon = bd.getInt32(6, Endian.little) * 1e-7;
        ext = ext.copyWith(
          opLocationType: flags & 0x03,
          classification: (flags >> 2) & 0x07,
          pilotLat: lat == 0 && lon == 0 ? null : lat,
          pilotLon: lat == 0 && lon == 0 ? null : lon,
          areaCount: bd.getUint16(10, Endian.little),
          areaRadius: m[12] * 10,
          areaCeiling: _altOut(_alt(bd.getUint16(13, Endian.little))),
          areaFloor: _altOut(_alt(bd.getUint16(15, Endian.little))),
          classEu: m[17] & 0x0F,
          categoryEu: m[17] >> 4,
          operatorAlt: _altOut(_alt(bd.getUint16(18, Endian.little))),
        );
      case _typeOperatorId:
        ext = ext.copyWith(opIdType: m[1], operatorId: _str(m.sublist(2, 22)));
    }
  }
}

class OdidBleDecoder {
  final Map<String, OdidState> _byMac = {};

  OdidExtension? feed(String mac, List<int> adv) => feedMessages(mac, odidMessagesFromAdv(adv));

  OdidExtension? feedMessages(String mac, List<List<int>> msgs) {
    if (msgs.isEmpty) return null;
    final s = _byMac.putIfAbsent(mac, OdidState.new);
    for (final m in msgs) {
      s.apply(m);
    }
    if (_byMac.length > 256) _byMac.remove(_byMac.keys.first);
    return s.plausible;
  }
}
