class FlockOui {
  const FlockOui._();

  static const table = <int>[
    0x00037f, 0x00f48d, 0x083a88, 0x145afc, 0x14b5cd, 0x24b2b9, 0x3c71bf,
    0x3c9180, 0x4827ea, 0x5800e3, 0x588e81, 0x5c93a2, 0x646e69, 0x700894,
    0x70c94e, 0x744ca1, 0x803049, 0x826bf2, 0x9035ea, 0x940853, 0x9c2f9d,
    0xa4cf12, 0xb41e52, 0xb81ea4, 0xb83532, 0xc03532, 0xd03957, 0xd8f3bc,
    0xe00af6, 0xe04f43, 0xe4aaea, 0xe8d0fc, 0xec1bbd, 0xf46add,
  ];

  static final Set<int> _set = Set<int>.unmodifiable(table);

  static bool match(String mac) {
    if (mac.length < 8) return false;
    final p = _parsePrefix(mac);
    if (p == null) return false;
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
