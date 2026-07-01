class FlockOui {
  const FlockOui._();

  static const _table = <int>[
    0x00180a, 0x00236c, 0x00f48d, 0x040d84, 0x083a88, 0x145afc, 0x14b5cd,
    0x1c34f1, 0x1cb72c, 0x240ac4, 0x246f28, 0x24b2b9, 0x2cf432, 0x30aea4,
    0x385b44, 0x3c6105, 0x3c71bf, 0x3c9180, 0x4827ea, 0x5800e3, 0x588e81,
    0x5c93a2, 0x606201, 0x646e69, 0x700894, 0x70c94e, 0x744ca1, 0x803049,
    0x826bf2, 0x840d8e, 0x84f3eb, 0x8caab5, 0x9035ea, 0x940853, 0x942a6f,
    0x943469, 0x98f4ab, 0x9c2f9d, 0x9c9c1f, 0xa0c9a0, 0xa4cf12, 0xac67b2,
    0xb41e52, 0xb4e3f9, 0xb81ea4, 0xb83532, 0xbcddc2, 0xc03532, 0xc82b96,
    0xcc50e3, 0xd03957, 0xd411d6, 0xd8a01d, 0xd8f3bc, 0xdc5475, 0xe00af6,
    0xe04f43, 0xe4aaea, 0xe8d0fc, 0xec1bbd, 0xec6260, 0xf082c0, 0xf46add,
    0xf4cfa2, 0xf4e2c6, 0xfcf5c4,
  ];

  static final Set<int> _set = Set<int>.unmodifiable(_table);

  static bool match(String mac) {
    if (mac.length < 8) return false;
    final p = _parsePrefix(mac);
    if (p == null) return false;
    final firstByte = (p >> 16) & 0xff;
    if ((firstByte & 0x02) != 0) return false;
    return _set.contains(p);
  }

  static int? _parsePrefix(String mac) {
    final clean = StringBuffer();
    for (var i = 0; i < mac.length && clean.length < 6; i++) {
      final c = mac.codeUnitAt(i);
      final isHex = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x46) ||
          (c >= 0x61 && c <= 0x66);
      if (isHex) clean.writeCharCode(c);
    }
    if (clean.length < 6) return null;
    return int.tryParse(clean.toString().substring(0, 6), radix: 16);
  }
}
