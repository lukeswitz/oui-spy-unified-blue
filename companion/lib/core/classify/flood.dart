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
  final bool wifi;
  final List<String> keys;

  const FloodNotice({
    required this.showDialog,
    required this.popupCount,
    required this.nameCount,
    this.families = const [],
    this.medianRssi,
    this.wifi = false,
    this.keys = const [],
  });

  FloodNotice quiet() => FloodNotice(
    showDialog: false,
    popupCount: popupCount,
    nameCount: nameCount,
    families: families,
    medianRssi: medianRssi,
    wifi: wifi,
    keys: keys,
  );

  String title() => wifi
      ? 'Wi-Fi beacon flood'
      : popupCount >= PairingFlood.popupMin
      ? 'Pairing flood'
      : 'Name flood';

  String line() {
    final loud = medianRssi != null ? ' · about $medianRssi dBm' : '';
    if (wifi) return 'Wi-Fi beacon flood · $popupCount new names$loud';
    final popupHot = popupCount >= PairingFlood.popupMin;
    final count = popupHot ? popupCount : nameCount;
    final extra = popupHot && nameCount >= PairingFlood.nameMin ? ' · $nameCount named' : '';
    return '${title()} · $count new addresses$extra$loud';
  }
}

class _Hit {
  final String mac;
  final int at;
  final int rssi;
  final bool popup;
  final int families;
  final bool confirm;
  _Hit(this.mac, this.at, this.rssi, this.popup, this.families, this.confirm);
}

class _Band {
  final int count;
  final int? median;
  final List<_Hit> hits;
  _Band(this.count, this.median, this.hits);
}

class PairingFlood {
  static const windowMs = 10000;
  static const popupMin = 10;
  static const nameMin = 15;
  static const rssiBandDb = 12;
  static const confirmMs = 20000;
  static const persistMs = 6000;
  static const primeMs = 5000;
  static const _cap = 4096;
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
  int _heardAt = 0;
  bool _acknowledged = false;
  FloodNotice? notice;

  void consider(Observation obs, int now, {bool confirm = false, int ignoreBefore = 0}) {
    if (obs.kind != RadioKind.ble) return;
    if (confirm && now > _heardAt) _heardAt = now;
    if (now < ignoreBefore) return;
    final kind = _classify(obs);
    if (kind == null) return;
    if (!confirm) _evict(now);
    final mac = MacUtil.normalize(obs.mac);
    if (mac.isNotEmpty && _window.length < _cap && _macs.add(mac)) {
      _window.addLast(_Hit(mac, now, obs.rssi, kind.$1, kind.$2, confirm));
    }
    if (!confirm) _publish(now);
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
      final gone = now - h.at > windowMs + (h.confirm ? confirmMs : 0);
      if (gone) _macs.remove(h.mac);
      return gone;
    });
  }

  void _publish(int now) {
    final live = _window.where((h) => !h.confirm || (now - h.at >= confirmMs && _heardAt - h.at >= confirmMs)).toList();
    final pop = _band(live.where((h) => h.popup).toList());
    final nam = _band(live.where((h) => !h.popup).toList());
    final popupHot = pop.count >= popupMin;
    final nameHot = nam.count >= nameMin;
    if (!popupHot && !nameHot) {
      _finish();
      return;
    }
    final median = popupHot && pop.median != null
        ? pop.median
        : nameHot
        ? nam.median
        : null;
    notice = FloodNotice(
      showDialog: !_acknowledged,
      popupCount: pop.count,
      nameCount: nam.count,
      families: popupHot ? _labels(pop.hits) : const [],
      medianRssi: median,
      keys: [if (popupHot) ...pop.hits.map((h) => 'BLE:${h.mac}'), if (nameHot) ...nam.hits.map((h) => 'BLE:${h.mac}')],
    );
  }

  void _finish() {
    _acknowledged = false;
    notice = null;
  }

  static _Band _band(List<_Hit> hits) {
    if (hits.isEmpty) return _Band(0, null, const []);
    final measured = hits.where((h) => _rssiMeasured(h.rssi)).toList();
    if (measured.length * 2 <= hits.length) return _Band(hits.length, null, hits);
    final values = measured.map((h) => h.rssi).toList()..sort();
    final median = values[values.length ~/ 2];
    final kept = measured.where((h) => (h.rssi - median).abs() <= rssiBandDb).toList();
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

  static (bool, int)? _classify(Observation obs) {
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
    if (bits != 0) return (true, bits);
    if (obs.name.trim().isNotEmpty && MacUtil.isRandomized(obs.mac)) return (false, 0);
    return null;
  }

  static int _appleBits(List<int> bytes) {
    var i = 0;
    var bits = 0;
    while (i + 2 <= bytes.length) {
      final type = bytes[i];
      final len = bytes[i + 1];
      if (len <= 0 || i + 2 + len > bytes.length) break;
      if (type == 0x07) bits |= _bitProx;
      if (type == 0x0F) bits |= _bitAction;
      i += 2 + len;
    }
    return bits;
  }

  static bool _swiftPair(List<int> b) {
    if (b.length >= 2 && b[0] == 0x01) return true;
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

class _Row {
  final String mac;
  final String base;
  final int rssi;
  final int channel;
  _Row(this.mac, this.base, this.rssi, this.channel);
}

class _Pending {
  final Set<String> macs;
  final List<String> keys;
  final int median;
  _Pending(this.macs, this.keys, this.median);
}

class WifiBeaconFlood {
  static const minNames = 15;
  static const rssiBandDb = 6;
  static const scanGapMs = 3000;
  static const _suffixes = {'guest', 'guests', 'extender', 'ext', '2.4ghz', '5ghz', '6ghz', '2.4g', '5g', '6g', '2.4'};

  final _seenMacs = <String>{};
  final _seenNames = <String>{};
  final _reportKeys = <String>{};
  _Pending? _pending;
  bool _primed = false;
  int _lastAcceptedAt = 0;
  bool _episode = false;
  bool _acknowledged = false;
  int? _median;
  FloodNotice? notice;

  void scan(List<Observation> observations, int now) {
    final rows = _parse(observations);
    if (rows.isEmpty) return;
    if (_lastAcceptedAt != 0 && now - _lastAcceptedAt < scanGapMs) return;
    _lastAcceptedAt = now;
    if (!_primed) {
      _absorb(rows);
      _primed = true;
      return;
    }
    final open = _pending;
    var confirmed = false;
    if (open != null) {
      final here = rows.map((r) => r.mac).toSet();
      final anchor = rows.any((r) => _seenMacs.contains(r.mac) && !open.macs.contains(r.mac));
      if (!anchor) {
        _seenMacs.clear();
        _seenNames.clear();
        _absorb(rows);
        _finish();
        return;
      }
      _pending = null;
      if (!open.macs.any(here.contains)) {
        _confirm(open);
        confirmed = true;
      }
    }
    final next = _cluster(rows);
    if (next != null) {
      _pending = next;
    } else if (!confirmed) {
      _finish();
    }
    _absorb(rows);
  }

  void dismiss() {
    final cur = notice;
    if (cur == null) return;
    _acknowledged = true;
    notice = cur.quiet();
  }

  void _confirm(_Pending open) {
    if (!_episode) {
      _reportKeys.clear();
      _median = open.median;
      _episode = true;
    }
    final before = _reportKeys.length;
    _reportKeys.addAll(open.keys);
    if (_reportKeys.length > before) _median = open.median;
    notice = FloodNotice(
      showDialog: !_acknowledged,
      popupCount: _reportKeys.length,
      nameCount: 0,
      medianRssi: _median,
      wifi: true,
      keys: _reportKeys.toList(),
    );
  }

  void _finish() {
    _episode = false;
    _acknowledged = false;
    _reportKeys.clear();
    _median = null;
    _pending = null;
    notice = null;
  }

  _Pending? _cluster(List<_Row> rows) {
    final fresh = rows
        .where(
          (r) =>
              !_seenMacs.contains(r.mac) &&
              r.base.isNotEmpty &&
              !_seenNames.contains(r.base) &&
              r.channel > 0 &&
              _rssiMeasured(r.rssi),
        )
        .toList();
    if (fresh.length < minNames) return null;
    final byBase = <String, List<_Row>>{};
    for (final r in fresh) {
      byBase.putIfAbsent(r.base, () => []).add(r);
    }
    final singles = [
      for (final g in byBase.values)
        if (g.length == 1) g.first,
    ];
    if (singles.length < minNames) return null;
    final byChannel = <int, List<_Row>>{};
    for (final r in singles) {
      byChannel.putIfAbsent(r.channel, () => []).add(r);
    }
    List<_Row>? best;
    var bestChannel = 1 << 30;
    byChannel.forEach((ch, g) {
      if (best == null || g.length > best!.length || (g.length == best!.length && ch < bestChannel)) {
        best = g;
        bestChannel = ch;
      }
    });
    final group = best!;
    final values = group.map((r) => r.rssi).toList()..sort();
    final median = values[values.length ~/ 2];
    final kept = group.where((r) => (r.rssi - median).abs() <= rssiBandDb).toList();
    if (kept.length < minNames) return null;
    return _Pending(kept.map((r) => r.mac).toSet(), kept.map((r) => 'WIFI:${r.mac}').toList(), median);
  }

  void _absorb(List<_Row> rows) {
    for (final r in rows) {
      _seenMacs.add(r.mac);
      if (r.base.isNotEmpty) _seenNames.add(r.base);
    }
  }

  static List<_Row> _parse(List<Observation> obs) {
    final byMac = <String, _Row>{};
    for (final o in obs) {
      if (o.kind != RadioKind.wifi) continue;
      final mac = MacUtil.normalize(o.mac);
      if (!mac.contains(':')) continue;
      final row = _Row(mac, _baseName(o.name), o.rssi, o.channel);
      final prev = byMac[mac];
      if (prev == null || _prefer(row, prev)) byMac[mac] = row;
    }
    return byMac.values.toList();
  }

  static bool _prefer(_Row next, _Row prev) {
    final a = _rssiMeasured(next.rssi);
    final b = _rssiMeasured(prev.rssi);
    if (a != b) return a;
    return next.rssi > prev.rssi;
  }

  static String _baseName(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.isEmpty || lower == '<unknown ssid>') return '';
    final cut = [
      lower.lastIndexOf('-'),
      lower.lastIndexOf('_'),
      lower.lastIndexOf(' '),
    ].reduce((a, b) => a > b ? a : b);
    if (cut <= 0 || cut >= lower.length - 1) return lower;
    final head = lower.substring(0, cut).trim();
    final tail = lower.substring(cut + 1).trim();
    if (head.isNotEmpty && _suffixes.contains(tail)) return head;
    return lower;
  }
}
