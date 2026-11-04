import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class OtaSignature {
  static const int _sigLen = 64;
  static const int trailerLen = 4 + _sigLen;
  static const List<int> _magic = [0x4F, 0x53, 0x47, 0x31];

  static const List<int> publicKey = [
    0x04,
    0xb8, 0x45, 0xcc, 0xd6, 0x08, 0x02, 0x88, 0x0e, 0x2b, 0x36, 0x0e, 0xfb, 0xe9, 0x44, 0x92, 0x22,
    0x00, 0x7f, 0xc9, 0x0a, 0x8e, 0x5b, 0x56, 0x26, 0xb9, 0xc6, 0x38, 0x8f, 0xbe, 0x75, 0xc2, 0xcb,
    0x18, 0x42, 0x6b, 0xe2, 0x80, 0xf4, 0x67, 0x67, 0x15, 0xa3, 0x73, 0x0d, 0xc1, 0xc1, 0xb9, 0x6d,
    0xdb, 0xc0, 0xea, 0xef, 0x7e, 0xa0, 0xcd, 0xc4, 0x33, 0x70, 0x2d, 0xee, 0xa6, 0x90, 0x07, 0x17,
  ];

  static BigInt _unsigned(List<int> bytes) =>
      bytes.fold(BigInt.zero, (value, b) => (value << 8) | BigInt.from(b));

  static bool verify(Uint8List file) {
    if (file.length <= trailerLen) return false;
    final imageLen = file.length - trailerLen;
    for (var i = 0; i < _magic.length; i++) {
      if (file[imageLen + i] != _magic[i]) return false;
    }
    final sigStart = imageLen + _magic.length;
    final domain = ECCurve_secp256r1();
    final point = domain.curve.decodePoint(publicKey);
    final signer = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
    return signer.verifySignature(
      Uint8List.sublistView(file, 0, imageLen),
      ECSignature(
        _unsigned(Uint8List.sublistView(file, sigStart, sigStart + _sigLen ~/ 2)),
        _unsigned(Uint8List.sublistView(file, sigStart + _sigLen ~/ 2)),
      ),
    );
  }
}
