import 'observation.dart';

class SmartTagAdv {
  final int state;
  final String privacyId;
  final bool uwb;
  const SmartTagAdv(this.state, this.privacyId, this.uwb);

  bool get separated => state >= 1 && state <= 3;

  String get stateLabel => switch (state) {
        1 => 'just left its owner',
        2 => 'lost, away from its owner',
        3 => 'lost for over a day, away from its owner',
        4 => 'paired with its owner',
        _ => 'connected to its owner',
      };

  static SmartTagAdv? parse(List<int> b) {
    if (b.length < 13 || (b[0] & 0xF8) != 0x10) return null;
    final state = b[0] & 0x07;
    if (state < 1 || state > 6) return null;
    final pid = StringBuffer();
    for (var i = 4; i < 12; i++) {
      pid.write(b[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return SmartTagAdv(state, pid.toString(), b[12] & 0x04 != 0);
  }

  static SmartTagAdv? of(Observation o) {
    if (o.kind != RadioKind.ble) return null;
    for (final sd in o.serviceData) {
      if (uuid16(sd.uuid) != 0xFD5A) continue;
      final h = hexOnly(sd.dataHex);
      if (h.length < 26 || h.length.isOdd) return null;
      return parse([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
    }
    return null;
  }
}
