import 'dart:typed_data';

const linkProtocolVersion = 1;
const linkMaxPayload = 1024;
const _sync0 = 0xA5;
const _sync1 = 0x5A;
const _header = 7;

class LinkFrameType {
  const LinkFrameType._();

  static const hello = 0x01;
  static const write = 0x02;
  static const writeNoAck = 0x03;
  static const read = 0x04;
  static const subscribe = 0x05;
  static const ping = 0x06;
  static const helloAck = 0x81;
  static const writeAck = 0x82;
  static const readRsp = 0x84;
  static const subscribeAck = 0x85;
  static const pong = 0x86;
  static const notify = 0x90;
}

class LinkFrame {
  const LinkFrame(this.type, this.id, this.payload);

  final int type;
  final int id;
  final Uint8List payload;
}

int linkCrc16(List<int> d, int start, int end) {
  var crc = 0xFFFF;
  for (var i = start; i < end; i++) {
    crc ^= (d[i] & 0xFF) << 8;
    for (var b = 0; b < 8; b++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

Uint8List encodeLinkFrame(int type, int id, List<int> payload) {
  if (payload.length > linkMaxPayload) {
    throw ArgumentError('link payload ${payload.length} > $linkMaxPayload');
  }
  final n = payload.length;
  final out = Uint8List(_header + n + 2);
  out[0] = _sync0;
  out[1] = _sync1;
  out[2] = type;
  out[3] = id & 0xFF;
  out[4] = (id >> 8) & 0xFF;
  out[5] = n & 0xFF;
  out[6] = (n >> 8) & 0xFF;
  out.setRange(_header, _header + n, payload);
  final crc = linkCrc16(out, 2, _header + n);
  out[_header + n] = crc & 0xFF;
  out[_header + n + 1] = crc >> 8;
  return out;
}

const _deviceTypes = {
  LinkFrameType.helloAck,
  LinkFrameType.writeAck,
  LinkFrameType.readRsp,
  LinkFrameType.subscribeAck,
  LinkFrameType.pong,
  LinkFrameType.notify,
};

class LinkFrameParser {
  final List<int> _buf = [];
  int crcErrors = 0;

  List<LinkFrame> add(List<int> bytes) {
    _buf.addAll(bytes);
    final out = <LinkFrame>[];
    var i = 0;
    while (true) {
      final start = _buf.indexOf(_sync0, i);
      if (start < 0) {
        _buf.clear();
        return out;
      }
      if (start + 1 >= _buf.length) {
        _buf.removeRange(0, start);
        return out;
      }
      if (_buf[start + 1] != _sync1) {
        i = start + 1;
        continue;
      }
      if (start + _header > _buf.length) {
        _buf.removeRange(0, start);
        return out;
      }
      if (!_deviceTypes.contains(_buf[start + 2])) {
        i = start + 1;
        continue;
      }
      final n = _buf[start + 5] | (_buf[start + 6] << 8);
      if (n > linkMaxPayload) {
        i = start + 1;
        continue;
      }
      final end = start + _header + n + 2;
      if (end > _buf.length) {
        _buf.removeRange(0, start);
        return out;
      }
      final want = _buf[end - 2] | (_buf[end - 1] << 8);
      if (linkCrc16(_buf, start + 2, start + _header + n) != want) {
        crcErrors++;
        i = start + 1;
        continue;
      }
      out.add(LinkFrame(
        _buf[start + 2],
        _buf[start + 3] | (_buf[start + 4] << 8),
        Uint8List.fromList(_buf.sublist(start + _header, start + _header + n)),
      ));
      i = end;
    }
  }
}
