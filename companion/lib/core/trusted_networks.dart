import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/stops_report.dart' show StopsReport;

class TrustedAp {
  final String bssid;
  final String vendor;
  final int auth;
  const TrustedAp(this.bssid, this.vendor, this.auth);

  Map<String, dynamic> toJson() => {'b': bssid, 'v': vendor, 'a': auth};
  factory TrustedAp.fromJson(Map<String, dynamic> j) =>
      TrustedAp(j['b'] as String, j['v'] as String? ?? '', (j['a'] as num?)?.toInt() ?? -1);
}

class TrustedNetwork {
  final String ssid;
  int addedMs;
  final List<TrustedAp> aps;
  final List<(double, double)> places;
  TrustedNetwork(this.ssid, this.addedMs, this.aps, this.places);

  bool learning(int now) => now - addedMs < TrustedNetworks.learnMs;

  Map<String, dynamic> toJson() => {
        's': ssid,
        't': addedMs,
        'aps': [for (final a in aps) a.toJson()],
        'p': [for (final p in places) [p.$1, p.$2]],
      };

  factory TrustedNetwork.fromJson(Map<String, dynamic> j) => TrustedNetwork(
        j['s'] as String,
        (j['t'] as num).toInt(),
        [for (final a in (j['aps'] as List? ?? const [])) TrustedAp.fromJson(a as Map<String, dynamic>)],
        [
          for (final p in (j['p'] as List? ?? const []))
            (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
      );
}

class TrustedSighting {
  final String bssid;
  final String vendor;
  final int? auth;
  final double? lat;
  final double? lon;
  const TrustedSighting(this.bssid, this.vendor, this.auth, this.lat, this.lon);
}

class TrustedNetworks extends ChangeNotifier {
  static const _key = 'trusted_networks_v1';
  static const learnMs = 24 * 3600 * 1000;
  static const farM = 2000.0;
  static const placeM = 300.0;
  static const maxPlaces = 24;
  static const maxAps = 64;
  static const alertCooldownMs = 3600 * 1000;
  static const weakSecurity = 'weaker security';
  static const unknownMaker = 'unknown device';
  static const awayFromUsual = 'away from usual places';

  TrustedNetworks({bool persist = true}) : _persist = persist {
    if (persist) _load();
  }

  final bool _persist;
  final _nets = <String, TrustedNetwork>{};
  final _alerted = <String, int>{};

  List<TrustedNetwork> get networks => _nets.values.toList()..sort((a, b) => a.ssid.compareTo(b.ssid));
  bool isTrusted(String ssid) => _nets.containsKey(ssid);
  bool get isEmpty => _nets.isEmpty;

  static bool _weak(int auth) => auth == 0 || auth == 1;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      for (final j in jsonDecode(raw) as List) {
        final n = TrustedNetwork.fromJson(j as Map<String, dynamic>);
        _nets[n.ssid] = n;
      }
    } on FormatException {
      return;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final n in _nets.values) n.toJson()]));
  }

  Future<void> trust(String ssid, Iterable<TrustedSighting> seed, int now) async {
    final net = TrustedNetwork(ssid, now, [], []);
    for (final s in seed) {
      _learn(net, s);
    }
    _nets[ssid] = net;
    notifyListeners();
    await _save();
  }

  Future<void> forget(String ssid) async {
    if (_nets.remove(ssid) == null) return;
    notifyListeners();
    await _save();
  }

  void _learn(TrustedNetwork net, TrustedSighting s) {
    if (!net.aps.any((a) => a.bssid == s.bssid) && net.aps.length < maxAps) {
      net.aps.add(TrustedAp(s.bssid, s.vendor, s.auth ?? -1));
    }
    final lat = s.lat, lon = s.lon;
    if (lat == null || lon == null) return;
    final near = net.places.any((p) => StopsReport.meters(p.$1, p.$2, lat, lon) <= placeM);
    if (!near && net.places.length < maxPlaces) net.places.add((lat, lon));
  }

  List<String>? check(String ssid, TrustedSighting s, int now) {
    final net = _nets[ssid];
    if (net == null || s.bssid.isEmpty) return null;
    final known = net.aps.any((a) => a.bssid == s.bssid);
    final reasons = <String>[];
    if (!known) {
      final auth = s.auth;
      if (auth != null && auth >= 0 && _weak(auth) && net.aps.isNotEmpty && !net.aps.any((a) => a.auth >= 0 && _weak(a.auth))) {
        reasons.add(weakSecurity);
      }
      final vendors = {for (final a in net.aps) a.vendor};
      if (net.aps.isNotEmpty && (s.vendor.isEmpty || !vendors.contains(s.vendor))) reasons.add(unknownMaker);
    }
    final lat = s.lat, lon = s.lon;
    if (lat != null && lon != null && net.places.isNotEmpty) {
      final nearest = net.places.map((p) => StopsReport.meters(p.$1, p.$2, lat, lon)).reduce(math.min);
      if (nearest > farM && !net.learning(now)) reasons.add(awayFromUsual);
    }
    if (reasons.isEmpty) {
      final before = (net.aps.length, net.places.length);
      _learn(net, s);
      if (before != (net.aps.length, net.places.length)) {
        notifyListeners();
        _save();
      }
      return null;
    }
    final last = _alerted[s.bssid];
    if (last != null && now - last < alertCooldownMs) return null;
    _alerted[s.bssid] = now;
    if (_alerted.length > 2048) _alerted.remove(_alerted.keys.first);
    return reasons;
  }
}

final trustedNetworksProvider = ChangeNotifierProvider<TrustedNetworks>((ref) => TrustedNetworks());
