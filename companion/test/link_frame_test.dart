import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/link/link_frame.dart';

void main() {
  test('crc16 is CRC-16/CCITT-FALSE', () {
    final d = utf8.encode('123456789');
    expect(linkCrc16(d, 0, d.length), 0x29B1);
  });

  test('a frame survives log text on both sides and split delivery', () {
    final frame = encodeLinkFrame(LinkFrameType.notify, 0x10, [1, 2, 3, 0xA5, 0x5A]);
    final stream = [
      ...utf8.encode('[HB] tx id=ABCD ch=1\n'),
      ...frame,
      ...utf8.encode('[WD] scan done\n'),
    ];
    final p = LinkFrameParser();
    final got = <LinkFrame>[];
    for (var i = 0; i < stream.length; i += 5) {
      got.addAll(p.add(stream.sublist(i, i + 5 > stream.length ? stream.length : i + 5)));
    }
    expect(got, hasLength(1));
    expect(got.single.type, LinkFrameType.notify);
    expect(got.single.id, 0x10);
    expect(got.single.payload, [1, 2, 3, 0xA5, 0x5A]);
  });

  test('a false sync in log bytes does not swallow the next real frame', () {
    final real = encodeLinkFrame(LinkFrameType.writeAck, 0x02, [0]);
    final fakeHeader = [0xA5, 0x5A, LinkFrameType.notify, 0x10, 0x00, 0x05, 0x00, 9, 9, 9, 9, 9, 0, 0];
    final p = LinkFrameParser();
    final got = p.add([...fakeHeader, ...real]);
    expect(got, hasLength(1));
    expect(got.single.type, LinkFrameType.writeAck);
    expect(p.crcErrors, 1);
  });

  test('a corrupted frame is dropped and counted', () {
    final f = encodeLinkFrame(LinkFrameType.notify, 0x10, [7, 7, 7]);
    f[8] ^= 0xFF;
    final p = LinkFrameParser();
    expect(p.add(f), isEmpty);
    expect(p.crcErrors, 1);
  });

  test('payloads over the protocol limit are refused', () {
    expect(() => encodeLinkFrame(LinkFrameType.write, 2, List.filled(linkMaxPayload + 1, 0)),
        throwsArgumentError);
  });
}
