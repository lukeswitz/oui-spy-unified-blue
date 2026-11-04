import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ota/ota_signature.dart';

const _vectorHex =
    'e94f55492d535059204f5441207369676e6174757265207465737420766563746f72'
    '4f534731'
    'eae9e4fb1aef65685986409063208637485a8155061dc7e6910d9e9e325fd234'
    '2c60eb86895c1f4e91c925c52944aaac1209bedbd56bb82a1a2d1c18e89a8bd0';

Uint8List _vector() {
  final out = Uint8List(_vectorHex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(_vectorHex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  test('accepts an image signed by sign_ota.py', () {
    expect(OtaSignature.verify(_vector()), isTrue);
  });

  test('refuses a changed image', () {
    final v = _vector();
    v[5] ^= 1;
    expect(OtaSignature.verify(v), isFalse);
  });

  test('refuses a changed signature', () {
    final v = _vector();
    v[v.length - 1] ^= 1;
    expect(OtaSignature.verify(v), isFalse);
  });

  test('refuses an image with no trailer', () {
    final v = _vector();
    expect(OtaSignature.verify(Uint8List.sublistView(v, 0, v.length - OtaSignature.trailerLen)), isFalse);
  });

  test('refuses a changed trailer marker', () {
    final v = _vector();
    v[v.length - OtaSignature.trailerLen] ^= 1;
    expect(OtaSignature.verify(v), isFalse);
  });

  test('refuses zero signature values', () {
    final v = _vector();
    v.fillRange(v.length - 64, v.length, 0);
    expect(OtaSignature.verify(v), isFalse);
  });

  test('app key matches the firmware key', () {
    final header = File('../src/ota_pubkey.h').readAsStringSync();
    final firmwareKey = RegExp(r'0x([0-9a-fA-F]{2})')
        .allMatches(header)
        .map((m) => int.parse(m.group(1)!, radix: 16))
        .toList();
    expect(firmwareKey, OtaSignature.publicKey);
  });
}
