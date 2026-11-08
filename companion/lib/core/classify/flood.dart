import 'dart:collection';

import 'adv_decoder.dart';
import 'observation.dart';

bool _rssiMeasured(int rssi) => rssi >= -127 && rssi <= 126;

class FloodNotice {
  final bool showDialog;
  final int popupCount;
  final int nameCount;
  final List<String> families;
  final int? medianRssi;
  final List<String> keys;
  final String label;

  const FloodNotice({
    required this.showDialog,
    required this.popupCount,
    required this.nameCount,
    this.families = const [],
    this.medianRssi,
    this.keys = const [],
    this.label = 'Pairing flood',
  });

  FloodNotice quiet() => FloodNotice(
    showDialog: false,
    popupCount: popupCount,
    nameCount: nameCount,
    families: families,
    medianRssi: medianRssi,
    keys: keys,
    label: label,
  );

  String title() => label;

  String line() {
    final loud = medianRssi != null ? ' · about $medianRssi dBm' : '';
    return '${title()} · $popupCount new addresses$loud';
  }
}

class _Hit {
  final String mac;
  final int at;
  final int rssi;
  final int families;
  _Hit(this.mac, this.at, this.rssi, this.families);
}

class _Band {
  final int count;
  final int? median;
  final List<_Hit> hits;
  _Band(this.count, this.median, this.hits);
}

class PairingFlood {
  static const windowMs = 10000;
  static const popupMin = 100;
  static const rssiBandDb = 4;
  static const oneTransmitterShare = 0.8;
  static const confirmMs = 20000;
  static const persistMs = 6000;
  static const seenTtlMs = 60000;
  static const _cap = 4096;
  static const _perSecond = 128;
  static const _bitProx = 1;
  static const _bitAction = 2;
  static const _bitFast = 4;
  static const _bitSwift = 8;
  static const _bitEasy = 16;
  static const _bitLove = 32;
  static const _loveSpouse = [0x6D, 0xB6, 0x43, 0xCE, 0x97, 0xFE, 0x42, 0x7C];
  static const _easyBuds = [0x42, 0x09, 0x81, 0x02, 0x14, 0x15, 0x03, 0x21, 0x01, 0x09];
  static const _easyWatch = [0x01, 0x00, 0x02, 0x00, 0x01, 0x01, 0xFF, 0x00, 0x00, 0x43];

  final _window = ListQueue<_Hit>();
  final _macs = <String>{};
  final _seen = <String, int>{};
  final _admitted = <int, int>{};
  final _arrived = <int, int>{};
  int _heardAt = 0;
  bool _acknowledged = false;
  FloodNotice? notice;

  void consider(Observation obs, int now) {
    if (obs.kind != RadioKind.ble) return;
    if (now > _heardAt) _heardAt = now;
    final mac = MacUtil.normalize(obs.mac);
    if (mac.isEmpty) return;
    if (_seen.containsKey(mac)) {
      _seen[mac] = now;
      seenAgain(obs, now);
      return;
    }
    _seen[mac] = now;
    final families = _classify(obs);
    if (families == 0) return;
    final sec = now ~/ 1000;
    _arrived[sec] = (_arrived[sec] ?? 0) + 1;
    if ((_admitted[sec] ?? 0) >= _perSecond || _window.length >= _cap || !_macs.add(mac)) return;
    _admitted[sec] = (_admitted[sec] ?? 0) + 1;
    _window.addLast(_Hit(mac, now, obs.rssi, families));
  }

  void seenAgain(Observation obs, int now) {
    if (now > _heardAt) _heardAt = now;
    final mac = MacUtil.normalize(obs.mac);
    if (mac.isEmpty || !_macs.contains(mac)) return;
    final before = _window.length;
    _window.removeWhere((h) => h.mac == mac && now - h.at >= persistMs);
    if (_window.length == before) return;
    _macs.remove(mac);
  }

  void tick(int now) {
    _seen.removeWhere((_, t) => now - t > seenTtlMs);
    final oldest = (now - windowMs - confirmMs) ~/ 1000;
    for (final m in [_admitted, _arrived]) {
      m.removeWhere((s, _) => s < oldest);
    }
    if (_window.isEmpty) {
      _finish();
      return;
    }
    _evict(now);
    _publish(now);
  }

  void dismiss() {
    final cur = notice;
    if (cur == null) return;
    _acknowledged = true;
    notice = cur.quiet();
  }

  void _evict(int now) {
    _window.removeWhere((h) {
      final gone = now - h.at > windowMs + confirmMs;
      if (gone) _macs.remove(h.mac);
      return gone;
    });
  }

  void _publish(int now) {
    final live = _window.where((h) => now - h.at >= confirmMs && _heardAt - h.at >= confirmMs).toList();
    final pop = _band(live);
    int scaled(List<_Hit> hits) {
      var n = 0.0;
      for (final h in hits) {
        final s = h.at ~/ 1000;
        final a = _admitted[s] ?? 0;
        n += a == 0 ? 1 : (_arrived[s] ?? a) / a;
      }
      return n.round();
    }
    final popCount = scaled(pop.hits);
    if (popCount < popupMin) {
      _finish();
      return;
    }
    notice = FloodNotice(
      showDialog: !_acknowledged,
      popupCount: popCount,
      nameCount: 0,
      families: _labels(pop.hits),
      medianRssi: pop.median,
      keys: [for (final h in pop.hits) 'BLE:${h.mac}'],
    );
  }

  void _finish() {
    _acknowledged = false;
    notice = null;
  }

  static _Band _band(List<_Hit> hits) {
    if (hits.isEmpty) return _Band(0, null, const []);
    final measured = hits.where((h) => _rssiMeasured(h.rssi)).toList();
    if (measured.length * 2 <= hits.length) return _Band(0, null, const []);
    final values = measured.map((h) => h.rssi).toList()..sort();
    final median = values[values.length ~/ 2];
    final kept = measured.where((h) => (h.rssi - median).abs() <= rssiBandDb).toList();
    if (kept.length < measured.length * oneTransmitterShare) return _Band(0, median, const []);
    return _Band(kept.length, median, kept);
  }

  static List<String> _labels(List<_Hit> hits) {
    final bits = hits.fold<int>(0, (a, h) => a | h.families);
    return [
      if (bits & _bitProx != 0) 'Apple proximity pairing',
      if (bits & _bitAction != 0) 'Apple Nearby Action',
      if (bits & _bitFast != 0) 'Fast Pair',
      if (bits & _bitSwift != 0) 'Swift Pair',
      if (bits & _bitEasy != 0) 'Samsung Easy Setup',
      if (bits & _bitLove != 0) 'LoveSpouse',
    ];
  }

  static int _classify(Observation obs) {
    var bits = 0;
    for (final rec in obs.mfgRecords) {
      final bytes = hexToBytes(rec.dataHex);
      if (bytes == null) continue;
      switch (rec.companyId) {
        case 0x004C:
          bits |= _appleBits(bytes);
        case 0x0006:
          if (_swiftPair(bytes)) bits |= _bitSwift;
        case 0x0075:
          if (_startsWith(bytes, _easyBuds) || _startsWith(bytes, _easyWatch)) bits |= _bitEasy;
        case 0x00FF:
          if (_startsWith(bytes, _loveSpouse)) bits |= _bitLove;
      }
    }
    if (obs.serviceData.any((s) => uuid16(s.uuid) == 0xFE2C && hexOnly(s.dataHex).length == 6)) bits |= _bitFast;
    return bits;
  }

  static int _appleBits(List<int> bytes) {
    var i = 0;
    var bits = 0;
    var sawFindMy = false;
    while (i + 2 <= bytes.length) {
      final type = bytes[i];
      final len = bytes[i + 1];
      if (len <= 0 || i + 2 + len > bytes.length) break;
      if (type == 0x12) sawFindMy = true;
      if (type == 0x07 && !sawFindMy) bits |= _bitProx;
      if (type == 0x0F) bits |= _bitAction;
      i += 2 + len;
    }
    return bits;
  }

  static bool _swiftPair(List<int> b) {
    if (b.length < 3 || b[0] != 0x03) return false;
    return b[1] <= 0x02 && b[2] == 0x80;
  }

  static bool _startsWith(List<int> b, List<int> p) {
    if (b.length < p.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (b[i] != p[i]) return false;
    }
    return true;
  }
}
