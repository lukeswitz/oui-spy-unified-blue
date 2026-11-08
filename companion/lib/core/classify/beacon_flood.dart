import 'flood.dart' show FloodNotice;
import 'observation.dart';

class _FreshAp {
  final String key;
  final String mac;
  final int at;
  final int rssi;
  final int channel;
  final bool unknownMaker;
  _FreshAp(this.key, this.mac, this.at, this.rssi, this.channel, this.unknownMaker);
}

class BeaconFlood {
  static const label = 'Wi-Fi beacon flood';
  static const windowMs = 10000;
  static const warmupMs = 30000;
  static const minAps = 15;
  static const rssiBandDb = 6;
  static const unknownMakerShare = 0.6;
  static const holdMs = 60000;
  static const seenTtlMs = 600000;

  bool enabled = false;
  FloodNotice? notice;
  int? _firstAt;
  int _hotAt = 0;
  bool _acknowledged = false;
  final _seen = <String, int>{};
  final _fresh = <_FreshAp>[];

  static String? apKey(String mac) {
    final h = hexOnly(mac);
    return h.length == 12 ? h.substring(2, 10) : null;
  }

  void consider(Observation o, int now, bool Function() unknownMaker) {
    if (!enabled || o.kind != RadioKind.wifi || !o.isAp) return;
    final key = apKey(o.mac);
    if (key == null) return;
    final first = _firstAt ??= now;
    if (_seen.containsKey(key)) {
      _seen[key] = now;
      return;
    }
    _seen[key] = now;
    if (now - first < warmupMs) return;
    _fresh.add(_FreshAp(key, MacUtil.normalize(o.mac), now, o.rssi, o.channel, unknownMaker()));
  }

  void tick(int now) {
    if (!enabled) {
      _reset();
      return;
    }
    _seen.removeWhere((_, t) => now - t > seenTtlMs);
    _fresh.removeWhere((a) => now - a.at > windowMs);
    final burst = _bestCluster();
    if (burst != null) {
      _hotAt = now;
      final rssis = [for (final a in burst) a.rssi]..sort();
      notice = FloodNotice(
        label: label,
        showDialog: !_acknowledged,
        popupCount: burst.length,
        nameCount: 0,
        families: ['channel ${burst.first.channel}'],
        medianRssi: rssis[rssis.length ~/ 2],
        keys: [for (final a in burst) 'WIFI:${a.mac}'],
      );
      return;
    }
    if (notice != null && now - _hotAt > holdMs) {
      notice = null;
      _acknowledged = false;
    }
  }

  void dismiss() {
    final cur = notice;
    if (cur == null) return;
    _acknowledged = true;
    notice = cur.quiet();
  }

  void _reset() {
    _seen.clear();
    _fresh.clear();
    _firstAt = null;
    _hotAt = 0;
    _acknowledged = false;
    notice = null;
  }

  List<_FreshAp>? _bestCluster() {
    if (_fresh.length < minAps) return null;
    List<_FreshAp>? best;
    for (final anchor in _fresh) {
      final band = [
        for (final a in _fresh)
          if (a.channel == anchor.channel && (a.rssi - anchor.rssi).abs() <= rssiBandDb) a,
      ];
      if (band.length >= minAps && (best == null || band.length > best.length)) best = band;
    }
    if (best == null) return null;
    final unknown = best.where((a) => a.unknownMaker).length;
    return unknown >= best.length * unknownMakerShare ? best : null;
  }
}
