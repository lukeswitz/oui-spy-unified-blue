import 'dart:convert';

import 'observation.dart';

enum SignatureClass {
  finder('Finder tags'),
  beacon('Beacons'),
  signage('Signage'),
  wearable('Wearables'),
  surveillance('Surveillance'),
  drone('Drones'),
  hacking('Pentest'),
  bodyworn('Wearables'),
  lawEnforcement('Public safety'),
  vehicle('Vehicle'),
  glasses('Glasses'),
  audio('Audio'),
  camera('Cameras'),
  thermostat('Thermostats'),
  lock('Access control'),
  health('Health'),
  home('Home IoT'),
  isp('ISP / routers'),
  mesh('Mesh'),
  phone('Phones / PCs'),
  toy('Adult toys'),
  other('Other');

  final String label;
  const SignatureClass(this.label);

  SignatureClass get folded => this == bodyworn ? wearable : this;

  static SignatureClass parse(String? raw) {
    final k = (raw ?? '').toUpperCase();
    for (final c in values) {
      final wire = c.name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();
      if (wire == k) return c;
    }
    return other;
  }
}

enum RuleKind {
  oui,
  macPrefix,
  nameContains,
  nameGlob,
  serviceUuid,
  serviceData,
  manufacturerId,
  manufacturerData,
  radioKind,
  hiddenSsid,
  vendorIeOui;

  static RuleKind? parse(String raw) {
    for (final k in values) {
      final wire = k.name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();
      if (wire == raw) return k;
    }
    return null;
  }
}

RadioKind? _radio(Object? raw) => switch (raw) {
  'WIFI' => RadioKind.wifi,
  'BLE' => RadioKind.ble,
  _ => null,
};

class MatchRule {
  final RuleKind kind;
  final String text;
  final int companyId;
  final String dataPrefixHex;
  final RadioKind? radio;
  final bool enabled;

  const MatchRule(
    this.kind, {
    this.text = '',
    this.companyId = 0,
    this.dataPrefixHex = '',
    this.radio,
    this.enabled = true,
  });

  static MatchRule? fromJson(Map<String, dynamic> j) {
    final kind = RuleKind.parse(j['kind'] as String? ?? '');
    if (kind == null) return null;
    return MatchRule(
      kind,
      text: j['text'] as String? ?? '',
      companyId: (j['companyId'] as num?)?.toInt() ?? 0,
      dataPrefixHex: j['dataPrefixHex'] as String? ?? '',
      radio: _radio(j['radio']),
      enabled: j['enabled'] as bool? ?? true,
    );
  }
}

class Signature {
  final String id;
  final String name;
  final SignatureClass kind;
  final bool enabled;
  final bool matchAny;
  final List<MatchRule> rules;
  final String notes;
  final String attentionNote;
  final int minPeers;
  final int peerWindowSec;
  final bool clusterByOui;
  final bool sequentialMac;
  final Map<String, dynamic>? decode;

  const Signature({
    required this.id,
    required this.name,
    required this.kind,
    this.enabled = true,
    this.matchAny = true,
    this.rules = const [],
    this.notes = '',
    this.attentionNote = '',
    this.minPeers = 0,
    this.peerWindowSec = 60,
    this.clusterByOui = false,
    this.sequentialMac = false,
    this.decode,
  });

  bool get cluster => minPeers > 0 || clusterByOui || sequentialMac;

  static Signature fromJson(Map<String, dynamic> j) => Signature(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    kind: SignatureClass.parse(j['kind'] as String?).folded,
    enabled: j['enabled'] as bool? ?? true,
    matchAny: j['matchAny'] as bool? ?? true,
    rules: [for (final r in (j['rules'] as List? ?? const [])) ?MatchRule.fromJson(r as Map<String, dynamic>)],
    notes: j['notes'] as String? ?? '',
    attentionNote: j['attentionNote'] as String? ?? '',
    minPeers: (j['minPeers'] as num?)?.toInt() ?? 0,
    peerWindowSec: (j['peerWindowSec'] as num?)?.toInt() ?? 60,
    clusterByOui: j['clusterByOui'] as bool? ?? false,
    sequentialMac: j['sequentialMac'] as bool? ?? false,
    decode: j['decode'] as Map<String, dynamic>?,
  );

  static List<Signature> parseCatalog(String json) {
    final d = jsonDecode(json) as Map<String, dynamic>;
    return [for (final f in d['fleets'] as List) Signature.fromJson(f as Map<String, dynamic>)];
  }
}

const teslaIBeaconMfgPrefix = '021574278BDAB64445208F0C720EAF059935';
const _wifiProtocolIeOuis = {'0050F2', '000FAC'};
const _appleContinuityPrefixes = {'05', '07', '08', '09', '0A', '0B', '0C', '0D', '0E', '0F', '10'};

bool isAppleContinuity(Observation o) =>
    o.mfgRecords.any((r) => r.companyId == 0x004C && _appleContinuityPrefixes.contains(_take2(r.dataHex)));

bool isFindMyPayload(Observation o) =>
    !isAppleContinuity(o) && o.mfgRecords.any((r) => r.companyId == 0x004C && _take2(r.dataHex) == '12');

String _take2(String hex) {
  final h = hexOnly(hex);
  return h.length >= 2 ? h.substring(0, 2) : h;
}

class _Plan {
  final Signature sig;
  final List<MatchRule> rules;
  final List<bool Function(Observation)> other;
  _Plan(this.sig, this.rules, this.other);
}

class _LongOui {
  final String hex;
  final RadioKind? radio;
  final bool bssid;
  final bool vendor;
  final int idx;
  _LongOui(this.hex, this.radio, this.bssid, this.vendor, this.idx);
}

class SignatureEngine {
  final List<Signature> signatures;
  final _plans = <_Plan>[];
  final _wifiPlans = <int>[];
  final _blePlans = <int>[];
  final _clusterPlans = <int>[];
  final _bssidWifi = <String, List<int>>{};
  final _bssidBle = <String, List<int>>{};
  final _vendorIe = <String, List<int>>{};
  final _longOui = <_LongOui>[];
  late final Map<String, Signature> byId = {for (final s in signatures) s.id: s};

  SignatureEngine(this.signatures) {
    for (final sig in signatures) {
      final idx = _plans.length;
      final active = sig.enabled ? sig.rules.where((r) => r.enabled).toList() : <MatchRule>[];
      final other = <bool Function(Observation)>[];
      for (final r in active) {
        switch (r.kind) {
          case RuleKind.oui:
            _indexOui(r.text, r.radio, idx, bssid: true, vendor: true);
          case RuleKind.macPrefix:
            _indexOui(r.text, r.radio, idx, bssid: true, vendor: false);
          case RuleKind.vendorIeOui:
            _indexOui(r.text, r.radio, idx, bssid: false, vendor: true);
          default:
            if (_compileOther(r) case final f?) other.add(f);
        }
      }
      _plans.add(_Plan(sig, active, other));
      if (sig.enabled && sig.cluster) {
        _clusterPlans.add(idx);
        continue;
      }
      switch (_radioScope(active)) {
        case RadioKind.wifi:
          _wifiPlans.add(idx);
        case RadioKind.ble:
          _blePlans.add(idx);
        case null:
          _wifiPlans.add(idx);
          _blePlans.add(idx);
      }
    }
  }

  bool get hasClusters => _clusterPlans.isNotEmpty;

  List<Signature> clusterMatch(Observation a, Iterable<Observation> devices, int now) {
    if (_clusterPlans.isEmpty) return const [];
    final out = <Signature>[];
    final aOui = _ouiHits(a);
    for (final idx in _clusterPlans) {
      final plan = _plans[idx];
      final s = plan.sig;
      final windowMs = (s.peerWindowSec <= 0 ? 60 : s.peerWindowSec) * 1000;
      if (now - a.lastSeenMs > windowMs) continue;
      final eligible = plan.rules.isEmpty ||
          _fleetHits(a, plan, aOui.contains(idx)) ||
          (s.clusterByOui && (a.name.trim().isEmpty || a.randomized));
      if (!eligible) continue;
      var peers = 1;
      for (final b in devices) {
        if (b.key == a.key || now - b.lastSeenMs > windowMs) continue;
        if (s.clusterByOui && a.oui != b.oui) continue;
        if (s.sequentialMac && (_last16(a.mac) - _last16(b.mac)).abs() > 64) continue;
        if (plan.rules.isNotEmpty && !s.clusterByOui && !_fleetHits(b, plan, _ouiHits(b).contains(idx))) continue;
        peers++;
      }
      if (peers >= (s.minPeers <= 0 ? 3 : s.minPeers)) out.add(s);
    }
    return out;
  }

  static int _last16(String mac) {
    final h = hexOnly(mac);
    return h.length < 4 ? 0 : int.parse(h.substring(h.length - 4), radix: 16);
  }

  List<Signature> match(Observation o) {
    final ouiHit = _ouiHits(o);
    final hits = <String>[];
    for (final idx in o.kind == RadioKind.wifi ? _wifiPlans : _blePlans) {
      if (_fleetHits(o, _plans[idx], ouiHit.contains(idx))) hits.add(_plans[idx].sig.id);
    }
    if (hits.contains('fleet-ibeacon') &&
        hits.any((id) => id != 'fleet-ibeacon' && byId[id]?.kind != SignatureClass.beacon)) {
      hits.remove('fleet-ibeacon');
    }
    if (hits.contains('fleet-osmo') || hits.contains('fleet-dji-power')) hits.remove('fleet-dji');
    if (hits.contains('fleet-meraki')) hits.remove('fleet-cisco');
    if (hits.contains('fleet-airtag') &&
        !o.name.toLowerCase().contains('airtag') &&
        !_hasUuid(o, uuidAliases('FD44')) &&
        (hits.contains('fleet-apple-device') || hits.contains('fleet-apple-audio') || isAppleContinuity(o))) {
      hits.remove('fleet-airtag');
    }
    return [for (final id in hits) byId[id]!];
  }

  void _indexOui(String text, RadioKind? radio, int idx, {required bool bssid, required bool vendor}) {
    final hex = hexOnly(text);
    if (hex.isEmpty) return;
    if (hex.length != 6) {
      _longOui.add(_LongOui(hex, radio, bssid, vendor, idx));
      return;
    }
    if (bssid) {
      if (radio != RadioKind.ble) _add(_bssidWifi, hex, idx);
      if (radio != RadioKind.wifi) _add(_bssidBle, hex, idx);
    }
    if (vendor && radio != RadioKind.ble && !_wifiProtocolIeOuis.contains(hex)) _add(_vendorIe, hex, idx);
  }

  static void _add(Map<String, List<int>> m, String k, int idx) {
    final l = m.putIfAbsent(k, () => []);
    if (!l.contains(idx)) l.add(idx);
  }

  static RadioKind? _ruleScope(MatchRule r) => switch (r.kind) {
    RuleKind.vendorIeOui || RuleKind.hiddenSsid => RadioKind.wifi,
    RuleKind.serviceUuid ||
    RuleKind.serviceData ||
    RuleKind.manufacturerId ||
    RuleKind.manufacturerData => r.radio ?? RadioKind.ble,
    _ => r.radio,
  };

  static RadioKind? _radioScope(List<MatchRule> rules) {
    var wifi = false, ble = false, both = false;
    for (final r in rules) {
      switch (_ruleScope(r)) {
        case RadioKind.wifi:
          wifi = true;
        case RadioKind.ble:
          ble = true;
        case null:
          both = true;
      }
    }
    if (both || (wifi && ble)) return null;
    if (wifi) return RadioKind.wifi;
    if (ble) return RadioKind.ble;
    return null;
  }

  static bool _radioOk(Observation o, RadioKind? r) => r == null || o.kind == r;

  static RegExp _glob(String p) {
    final b = StringBuffer('^');
    for (final ch in p.split('')) {
      b.write(
        ch == '*'
            ? '.*'
            : ch == '?'
            ? '.'
            : RegExp.escape(ch),
      );
    }
    b.write(r'$');
    return RegExp(b.toString(), caseSensitive: false);
  }

  static bool _hasUuid(Observation o, Set<String> want) =>
      [...o.serviceUuids, ...o.serviceData.map((s) => s.uuid)].any((u) => uuidAliases(u).any(want.contains));

  static bool Function(Observation)? _compileOther(MatchRule r) {
    switch (r.kind) {
      case RuleKind.nameContains:
        if (r.text.trim().isEmpty) return null;
        final needle = r.text.toLowerCase();
        return (o) => _radioOk(o, r.radio) && o.name.isNotEmpty && o.name.toLowerCase().contains(needle);
      case RuleKind.nameGlob:
        if (r.text.trim().isEmpty) return null;
        final re = _glob(r.text);
        return (o) => _radioOk(o, r.radio) && o.name.isNotEmpty && re.hasMatch(o.name);
      case RuleKind.serviceUuid:
        if (r.text.trim().isEmpty) return null;
        final want = uuidAliases(r.text);
        return (o) => _radioOk(o, r.radio) && _hasUuid(o, want);
      case RuleKind.manufacturerId:
        return (o) => _radioOk(o, r.radio) && o.mfgRecords.any((m) => m.companyId == r.companyId);
      case RuleKind.manufacturerData:
        final prefix = hexOnly(r.dataPrefixHex);
        if (prefix.isEmpty) return null;
        return (o) =>
            _radioOk(o, r.radio) &&
            o.mfgRecords.any(
              (m) => (r.companyId == 0 || m.companyId == r.companyId) && hexOnly(m.dataHex).startsWith(prefix),
            );
      case RuleKind.serviceData:
        final prefix = hexOnly(r.dataPrefixHex);
        final aliases = uuidAliases(r.text)..removeWhere((a) => a.isEmpty);
        if (prefix.isEmpty && aliases.isEmpty) return null;
        final contains = r.text.trim().isEmpty && prefix.isNotEmpty;
        return (o) => _radioOk(o, r.radio) && _serviceDataHits(o, aliases, prefix, contains);
      case RuleKind.radioKind:
        return (o) => r.radio == null || o.kind == r.radio;
      case RuleKind.hiddenSsid:
        return (o) => o.hiddenSsid;
      case RuleKind.oui || RuleKind.macPrefix || RuleKind.vendorIeOui:
        return null;
    }
  }

  static bool _serviceDataHits(Observation o, Set<String> aliases, String prefix, bool contains) {
    final rev = contains ? _reverseHexBytes(prefix) : '';
    return o.serviceData.any((rec) {
      if (aliases.isNotEmpty && !uuidAliases(rec.uuid).any(aliases.contains)) return false;
      final data = hexOnly(rec.dataHex);
      if (!contains) return data.startsWith(prefix);
      return data.contains(prefix) || (rev.isNotEmpty && data.contains(rev));
    });
  }

  static String _reverseHexBytes(String hex) {
    final h = hexOnly(hex);
    if (h.length < 2 || h.length.isOdd) return '';
    final b = StringBuffer();
    for (var i = h.length; i >= 2; i -= 2) {
      b.write(h.substring(i - 2, i));
    }
    return b.toString();
  }

  static bool _teslaIBeacon(Observation o) =>
      o.mfgRecords.any((m) => m.companyId == 0x004C && hexOnly(m.dataHex).startsWith(teslaIBeaconMfgPrefix));

  bool _fleetHits(Observation o, _Plan p, bool ouiHit) {
    if (p.sig.id == 'fleet-ibeacon' && _teslaIBeacon(o)) return false;
    if (p.rules.isEmpty) return false;
    if (!p.sig.matchAny) return p.rules.every((r) => _ruleHits(o, r));
    if (ouiHit) return true;
    return p.other.any((f) => f(o));
  }

  static bool _vendorIeHits(Observation o, String prefix) {
    if (o.kind != RadioKind.wifi) return false;
    final want = hexOnly(prefix);
    if (want.isEmpty || _wifiProtocolIeOuis.contains(want.length >= 6 ? want.substring(0, 6) : want)) return false;
    return o.vendorIeOuis.any((ie) {
      final h = hexOnly(ie);
      if (h.length >= 6 && _wifiProtocolIeOuis.contains(h.substring(0, 6))) return false;
      return h.startsWith(want);
    });
  }

  bool _ruleHits(Observation o, MatchRule r) {
    if (r.kind != RuleKind.radioKind && r.radio != null && o.kind != r.radio) return false;
    switch (r.kind) {
      case RuleKind.oui:
        final univ = o.kind == RadioKind.wifi && o.isAp ? MacUtil.wifiOui24Universal(o.mac) : null;
        final want = hexOnly(r.text);
        return MacUtil.matchesPrefix(o.mac, r.text) ||
            _vendorIeHits(o, r.text) ||
            (univ != null && want.length == 6 && univ == want);
      case RuleKind.macPrefix:
        return MacUtil.matchesPrefix(o.mac, r.text);
      case RuleKind.vendorIeOui:
        return _vendorIeHits(o, r.text);
      default:
        return _compileOther(r)?.call(o) ?? false;
    }
  }

  Set<int> _ouiHits(Observation o) {
    final hits = <int>{};
    final macHex = hexOnly(o.mac);
    final oui6 = macHex.length >= 6 ? macHex.substring(0, 6) : macHex;
    final bssid = o.kind == RadioKind.wifi ? _bssidWifi : _bssidBle;
    hits.addAll(bssid[oui6] ?? const []);
    if (o.kind == RadioKind.wifi) {
      final univ = o.isAp ? MacUtil.wifiOui24Universal(o.mac) : null;
      if (univ != null) hits.addAll(bssid[univ] ?? const []);
      for (final ie in o.vendorIeOuis) {
        final h = hexOnly(ie);
        if (h.length < 6 || _wifiProtocolIeOuis.contains(h.substring(0, 6))) continue;
        hits.addAll(_vendorIe[h.substring(0, 6)] ?? const []);
      }
    }
    for (final l in _longOui) {
      if (l.radio != null && l.radio != o.kind) continue;
      if (l.bssid && macHex.isNotEmpty && macHex.startsWith(l.hex)) hits.add(l.idx);
      if (l.vendor && o.kind == RadioKind.wifi) {
        for (final ie in o.vendorIeOuis) {
          final h = hexOnly(ie);
          if (h.length >= 6 && _wifiProtocolIeOuis.contains(h.substring(0, 6))) continue;
          if (h.startsWith(l.hex)) hits.add(l.idx);
        }
      }
    }
    return hits;
  }
}
