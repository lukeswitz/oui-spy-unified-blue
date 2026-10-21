import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/link/link_frame.dart';
import 'package:oui_spy/core/link/link_session.dart';

class _FakeBoard implements LinkTransport {
  final _out = StreamController<Uint8List>.broadcast();
  final _parser = _HostFrameParser();
  final Map<int, List<int>> values = {0x01: [0x30, 0x00, 0x41, 0x00]};
  final writes = <int, List<int>>{};
  final subscribed = <int>{};
  bool closed = false;
  bool silent = false;

  @override
  Stream<Uint8List> get input => _out.stream;

  void notify(int id, List<int> data) {
    if (subscribed.contains(id)) _emit(LinkFrameType.notify, id, data);
  }

  void _emit(int type, int id, List<int> data) {
    scheduleMicrotask(() => _out.add(encodeLinkFrame(type, id, data)));
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (silent) return;
    for (final f in _parser.add(bytes)) {
      switch (f.type) {
        case LinkFrameType.hello:
          _emit(LinkFrameType.helloAck, 0, [1, 0x00, 0x04, 3, 0x01, 0x00, 0x02, 0x00, 0x10, 0x00]);
        case LinkFrameType.write:
          writes[f.id] = f.payload;
          _emit(LinkFrameType.writeAck, f.id, [values.containsKey(f.id) || f.id == 0x02 ? 0 : 1]);
        case LinkFrameType.read:
          final v = values[f.id];
          _emit(LinkFrameType.readRsp, f.id, v == null ? [1] : [0, ...v]);
        case LinkFrameType.subscribe:
          if (f.payload.first == 1) {
            subscribed.add(f.id);
          } else {
            subscribed.remove(f.id);
          }
          _emit(LinkFrameType.subscribeAck, f.id, [0]);
        case LinkFrameType.ping:
          _emit(LinkFrameType.pong, 0, const []);
      }
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    await _out.close();
  }
}

class _HostFrameParser {
  final _buf = <int>[];

  List<LinkFrame> add(List<int> bytes) {
    _buf.addAll(bytes);
    final out = <LinkFrame>[];
    while (_buf.length >= 9) {
      final n = _buf[5] | (_buf[6] << 8);
      if (_buf.length < 9 + n) break;
      out.add(LinkFrame(_buf[2], _buf[3] | (_buf[4] << 8), Uint8List.fromList(_buf.sublist(7, 7 + n))));
      _buf.removeRange(0, 9 + n);
    }
    return out;
  }
}

void main() {
  test('hello lists the board characteristics and maps them to GATT uuids', () async {
    final board = _FakeBoard();
    final s = LinkSession(board);
    await s.open();
    expect(s.ids, [0x01, 0x02, 0x10]);
    expect(s.maxPayload, 1024);
    expect(linkGuidFor(0x10, GattUuids.service), GattUuids.detectionEvents);
    expect(linkIdFor(GattUuids.engineControl), 0x02);
    await s.close();
    expect(board.closed, isTrue);
  });

  test('write, read and notify go through the same characteristic ids', () async {
    final board = _FakeBoard();
    final s = LinkSession(board);
    await s.open();
    final c = UsbLinkCharacteristic(s, GattUuids.detectionEvents);
    final got = <List<int>>[];
    final sub = c.onValueReceived.listen(got.add);
    await c.setNotifyValue(true);
    board.notify(0x10, [9, 8, 7]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(got, [
      [9, 8, 7]
    ]);

    await UsbLinkCharacteristic(s, GattUuids.engineControl).write([0x01, 0x05]);
    expect(board.writes[0x02], [0x01, 0x05]);
    expect(await UsbLinkCharacteristic(s, GattUuids.deviceInfo).read(), [0x30, 0x00, 0x41, 0x00]);
    await expectLater(UsbLinkCharacteristic(s, GattUuids.melody).read(),
        throwsA(isA<FlutterBluePlusException>()));
    await sub.cancel();
    await s.close();
  });

  test('a board that stops answering closes the session', () async {
    final board = _FakeBoard();
    final s = LinkSession(board);
    await s.open();
    board.silent = true;
    await expectLater(
        UsbLinkCharacteristic(s, GattUuids.engineControl).write([1], timeout: 1),
        throwsA(isA<FlutterBluePlusException>()));
    await s.close();
    await s.done;
    expect(s.isOpen, isFalse);
  });
}
