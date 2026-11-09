import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_registry.dart' show DeviceRegistry;
import 'kin_index.dart';
import 'observation.dart';
import 'signature_engine.dart';

enum SetFormat { fieldwatch, homeAssistant }

class SetError implements Exception {
  const SetError(this.message);
  final String message;

  @override
  String toString() => message;
}

class SignatureSet {
  SignatureSet({
    required this.id,
    required this.name,
    this.url,
    this.format = SetFormat.fieldwatch,
    this.license = '',
    this.source = '',
    this.enabled = false,
    this.updatedAt,
    this.count = 0,
    this.error,
  });

  final String id;
  final String name;
  final String? url;
  final SetFormat format;
  final String license;
  final String source;
  bool enabled;
  int? updatedAt;
  int count;
  String? error;

  bool get preset => !id.startsWith('custom-');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'format': format.name,
        'license': license,
        'source': source,
        'enabled': enabled,
        'updatedAt': updatedAt,
        'count': count,
        'error': error,
      };

  factory SignatureSet.fromJson(Map<String, dynamic> j) => SignatureSet(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        url: j['url'] as String?,
        format: SetFormat.values.firstWhere((f) => f.name == j['format'], orElse: () => SetFormat.fieldwatch),
        license: j['license'] as String? ?? '',
        source: j['source'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? false,
        updatedAt: (j['updatedAt'] as num?)?.toInt(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
      );
}

List<SignatureSet> presetSets() => [
      SignatureSet(
        id: 'fieldwatch',
        name: 'Fieldwatch stock catalog',
        url: 'https://raw.githubusercontent.com/OffGridPete/Fieldwatch/main/dist/fieldwatch-signatures-v2.json',
        license: 'MIT',
        source: 'github.com/OffGridPete/Fieldwatch',
      ),
      SignatureSet(
        id: 'home-assistant',
        name: 'Home Assistant Bluetooth devices',
        url: 'https://raw.githubusercontent.com/home-assistant/core/master/homeassistant/generated/bluetooth.py',
        format: SetFormat.homeAssistant,
        license: 'Apache-2.0',
        source: 'github.com/home-assistant/core',
      ),
    ];

class BuiltInIndex {
  BuiltInIndex._(this.ids, this._orRules, this._andKeys, this._haDomains);

  final Set<String> ids;
  final Map<String, Set<RadioKind?>> _orRules;
  final Set<String> _andKeys;
  final Set<String> _haDomains;

  static String _text(RuleKind kind, String text) => switch (kind) {
        RuleKind.serviceUuid || RuleKind.serviceData => () {
            final u = uuid16(text);
            return u != null ? u.toRadixString(16).padLeft(4, '0').toUpperCase() : hexOnly(text).toUpperCase();
          }(),
        RuleKind.oui || RuleKind.macPrefix || RuleKind.vendorIeOui => hexOnly(text).toUpperCase(),
        _ => text.trim().toUpperCase(),
      };

  static String _key(RuleKind kind, MatchRule r) =>
      '${kind.name}|${_text(kind, r.text)}|${r.companyId}|${hexOnly(r.dataPrefixHex).toUpperCase()}';

  static String _base(MatchRule r) => _key(r.kind, r);

  static String andKey(List<MatchRule> rules) => (rules.map((r) => '${_base(r)}|${r.radio?.name}').toList()..sort()).join('&');

  factory BuiltInIndex.of(List<Signature> builtIn) {
    final or = <String, Set<RadioKind?>>{};
    final and = <String>{};
    final ha = <String>{};
    final haNote = RegExp(r'Home Assistant (\S+) integration');
    for (final s in builtIn) {
      final rules = s.rules.where((r) => r.enabled).toList();
      if (s.matchAny || rules.length == 1) {
        for (final r in rules) {
          (or[_base(r)] ??= {}).add(r.radio);
        }
      } else {
        and.add(andKey(rules));
      }
      if (haNote.firstMatch(s.notes) case final m?) ha.add(m.group(1)!);
    }
    return BuiltInIndex._({for (final s in builtIn) s.id}, or, and, ha);
  }

  bool _coveredBy(String key, RadioKind? radio) {
    final radios = _orRules[key];
    return radios != null && (radios.contains(null) || (radio != null && radios.contains(radio)));
  }

  bool covered(MatchRule r) =>
      _coveredBy(_base(r), r.radio) ||
      (r.kind == RuleKind.serviceData && r.dataPrefixHex.trim().isEmpty && _coveredBy(_key(RuleKind.serviceUuid, r), r.radio)) ||
      (r.kind == RuleKind.macPrefix && _coveredBy(_key(RuleKind.oui, r), r.radio));

  bool coversAnd(List<MatchRule> rules) => _andKeys.contains(andKey(rules)) || rules.any(covered);

  bool haCovered(String domain) {
    final short = domain.replaceFirst(RegExp(r'_ble$'), '');
    return _haDomains.any((d) => d == domain || d == short || d.replaceFirst(RegExp(r'_ble$'), '') == short);
  }
}

class SetParser {
  SetParser._();

  static const maxBytes = 8 * 1024 * 1024;
  static const maxSignatures = 3000;
  static const maxRules = 64;
  static const maxText = 128;
  static const maxGlobStars = 2;

  static String _cap(String s, int n) => s.length > n ? s.substring(0, n) : s;

  static Signature? sanitize(Signature s, String setId, BuiltInIndex idx) {
    if (!s.enabled) return null;
    final rules = <MatchRule>[
      for (final r in s.rules.take(maxRules))
        if (r.enabled &&
            r.text.length <= maxText &&
            r.dataPrefixHex.length <= maxText &&
            (r.kind != RuleKind.nameGlob || '*'.allMatches(r.text).length <= maxGlobStars))
          r,
    ];
    final List<MatchRule> kept;
    if (s.cluster) {
      if (rules.length != s.rules.length) return null;
      kept = rules;
    } else if (!s.matchAny && rules.length > 1) {
      if (rules.length != s.rules.length || idx.coversAnd(rules)) return null;
      kept = rules;
    } else {
      kept = [for (final r in rules) if (!idx.covered(r)) r];
      if (kept.isEmpty) return null;
    }
    return Signature(
      id: 'set:$setId:${_cap(s.id, maxText)}',
      name: _cap(s.name.trim().isEmpty ? s.id : s.name.trim(), 64),
      kind: s.kind,
      matchAny: s.matchAny,
      rules: kept,
      notes: _cap(s.notes, 600),
      attentionNote: _cap(s.attentionNote, 300),
      minPeers: s.minPeers.clamp(0, 50),
      peerWindowSec: s.peerWindowSec.clamp(0, 600),
      clusterByOui: s.clusterByOui,
      sequentialMac: s.sequentialMac,
    );
  }

  static List<Signature> fieldwatch(String text, BuiltInIndex idx, String setId) {
    final Object? d;
    try {
      d = jsonDecode(text);
    } on FormatException {
      throw const SetError('Not a signature file: the JSON could not be read.');
    }
    if (d is! Map ||
        (d['format'] != 'fieldwatch-signatures' && d['format'] != 'spectre-signatures') ||
        d['fleets'] is! List) {
      throw const SetError('Not a Fieldwatch signature file.');
    }
    final out = <Signature>[];
    final seen = <String>{};
    for (final f in d['fleets'] as List) {
      if (out.length >= maxSignatures) break;
      if (f is! Map<String, dynamic>) continue;
      final Signature s;
      try {
        s = Signature.fromJson(f);
      } on TypeError {
        continue;
      }
      final raw = f['rules'];
      if ((!s.matchAny || s.cluster) && raw is List && raw.length != s.rules.length) continue;
      if (idx.ids.contains(s.id) || !seen.add(s.id)) continue;
      final clean = sanitize(s, setId, idx);
      if (clean != null) out.add(clean);
    }
    return out;
  }

  static const _chipCompanies = {0x0059, 0x02E5, 0x000D, 0xFFFF};

  static bool _generic(MatchRule r) {
    switch (r.kind) {
      case RuleKind.manufacturerId:
        return _chipCompanies.contains(r.companyId) || KinIndex.platformCompanies.contains(r.companyId);
      case RuleKind.serviceUuid || RuleKind.serviceData:
        final u = uuid16(r.text);
        return u != null && u >= 0x1800 && u <= 0x18FF;
      case RuleKind.nameGlob:
        final wild = r.text.indexOf(RegExp(r'[*?]'));
        return wild >= 0 && wild < 4;
      default:
        return false;
    }
  }

  static String _haName(String domain) => domain
      .replaceFirst(RegExp(r'_ble$'), '')
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static List<Signature> homeAssistant(String text, BuiltInIndex idx, String setId) {
    final head = RegExp(r'BLUETOOTH\b[^=\n]*=\s*\[').firstMatch(text);
    final end = text.lastIndexOf(']');
    if (head == null || end < head.end) throw const SetError('Not the Home Assistant Bluetooth matcher file.');
    final body = text
        .substring(head.end - 1, end + 1)
        .replaceAllMapped(RegExp(r'([:\[,\s])True(?=[\s,\]\}])'), (m) => '${m[1]}true')
        .replaceAllMapped(RegExp(r'([:\[,\s])False(?=[\s,\]\}])'), (m) => '${m[1]}false')
        .replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m[1]!);
    final Object? list;
    try {
      list = jsonDecode(body);
    } on FormatException {
      throw const SetError('The Home Assistant file format changed and could not be read.');
    }
    if (list is! List) throw const SetError('The Home Assistant file format changed and could not be read.');
    final out = <Signature>[];
    var n = 0;
    for (final m in list) {
      if (out.length >= maxSignatures) break;
      if (m is! Map) continue;
      final domain = m['domain'];
      if (domain is! String || domain.isEmpty || domain == 'ibeacon' || idx.haCovered(domain)) continue;
      final rules = <MatchRule>[
        if (m['local_name'] case final String v) MatchRule(RuleKind.nameGlob, text: v, radio: RadioKind.ble),
        if (m['service_uuid'] case final String v) MatchRule(RuleKind.serviceUuid, text: v, radio: RadioKind.ble),
        if (m['service_data_uuid'] case final String v) MatchRule(RuleKind.serviceData, text: v, radio: RadioKind.ble),
      ];
      if (m['manufacturer_id'] case final int company) {
        final start = m['manufacturer_data_start'];
        if (start is List && start.isNotEmpty && start.every((b) => b is int && b >= 0 && b <= 255)) {
          final hex = start.map((b) => (b as int).toRadixString(16).padLeft(2, '0')).join().toUpperCase();
          rules.add(MatchRule(RuleKind.manufacturerData, companyId: company, dataPrefixHex: hex, radio: RadioKind.ble));
        } else if (rules.isNotEmpty || !KinIndex.platformCompanies.contains(company)) {
          rules.add(MatchRule(RuleKind.manufacturerId, companyId: company, radio: RadioKind.ble));
        }
      }
      if (rules.isEmpty || (rules.length == 1 && _generic(rules.single))) continue;
      final clean = sanitize(
        Signature(
          id: 'ha-$domain-${n++}',
          name: _haName(domain),
          kind: SignatureClass.home,
          matchAny: rules.length == 1,
          rules: rules,
          notes: 'Bluetooth matcher from the Home Assistant $domain integration (homeassistant/generated/bluetooth.py).',
        ),
        setId,
        idx,
      );
      if (clean != null) out.add(clean);
    }
    return out;
  }

  static String exportPack(List<Signature> sigs) => const JsonEncoder.withIndent('  ').convert({
        'format': 'fieldwatch-signatures',
        'formatVersion': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'fleets': [for (final s in sigs) s.toJson()],
      });
}

typedef SetFetcher = Future<String> Function(Uri url);

Future<String> fetchSetText(Uri url) async {
  if (url.scheme != 'https') throw const SetError('Only https:// links are allowed.');
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    responseType: ResponseType.stream,
    maxRedirects: 3,
    headers: {'User-Agent': 'oui-spy-companion/1.0'},
  ));
  try {
    final res = await dio.getUri<ResponseBody>(url);
    if (res.realUri.scheme != 'https') throw const SetError('The link redirected to a non-https address.');
    final body = res.data;
    if (body == null) throw const SetError('The server sent an empty reply.');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      bytes.add(chunk);
      if (bytes.length > SetParser.maxBytes) throw const SetError('The set is larger than 8 MB.');
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const SetError('The set is not UTF-8 text.');
    }
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    throw SetError(code != null ? 'Download failed: HTTP $code.' : 'Download failed: ${e.message ?? e.type.name}.');
  } finally {
    dio.close();
  }
}

class SignatureSets extends ChangeNotifier {
  SignatureSets({
    SetFetcher? fetch,
    Future<Directory> Function()? dir,
    Future<List<Signature>> Function()? builtIn,
  })  : _fetch = fetch ?? fetchSetText,
        _dir = dir ?? getApplicationSupportDirectory,
        _builtIn = builtIn ?? _bundledCatalog {
    _loaded = _load();
  }

  static const prefsKey = 'signature_sets_v1';

  final SetFetcher _fetch;
  final Future<Directory> Function() _dir;
  final Future<List<Signature>> Function() _builtIn;
  final sets = <SignatureSet>[];
  final busy = <String>{};
  final _sigs = <String, List<Signature>>{};
  late final Future<void> _loaded;

  Future<void> get loaded => _loaded;

  List<Signature> get signatures => [
        for (final s in sets)
          if (s.enabled) ...?_sigs[s.id],
      ];

  int get enabledCount => sets.where((s) => s.enabled).length;

  static Future<List<Signature>> _bundledCatalog() async =>
      Signature.parseCatalog(await rootBundle.loadString(DeviceRegistry.catalogAsset));

  Future<File> _file(String id) async => File('${(await _dir()).path}/signature_sets/$id.json');

  SignatureSet? _byId(String id) {
    for (final s in sets) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _load() async {
    final saved = <String, SignatureSet>{};
    final raw = (await SharedPreferences.getInstance()).getString(prefsKey);
    if (raw != null) {
      try {
        for (final j in jsonDecode(raw) as List) {
          final s = SignatureSet.fromJson(j as Map<String, dynamic>);
          saved[s.id] = s;
        }
      } on FormatException catch (e) {
        DebugLog.log('SETS: stored list unreadable, kept as is: $e');
      } on TypeError catch (e) {
        DebugLog.log('SETS: stored list unreadable, kept as is: $e');
      }
    }
    for (final p in presetSets()) {
      final s = saved.remove(p.id);
      if (s != null) {
        p
          ..enabled = s.enabled
          ..updatedAt = s.updatedAt
          ..count = s.count
          ..error = s.error;
      }
      sets.add(p);
    }
    sets.addAll(saved.values.where((s) => !s.preset));
    for (final s in sets) {
      final f = await _file(s.id);
      if (!await f.exists()) continue;
      try {
        final d = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _sigs[s.id] = [for (final j in d['fleets'] as List) Signature.fromJson(j as Map<String, dynamic>)];
      } on FormatException catch (e) {
        s.error = 'Saved copy unreadable. Tap Update.';
        DebugLog.log('SETS: ${s.id} file unreadable: $e');
      } on TypeError catch (e) {
        s.error = 'Saved copy unreadable. Tap Update.';
        DebugLog.log('SETS: ${s.id} file unreadable: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _saveMeta() async => (await SharedPreferences.getInstance())
      .setString(prefsKey, jsonEncode([for (final s in sets) s.toJson()]));

  Future<void> _store(SignatureSet s, String text) async {
    final idx = BuiltInIndex.of(await _builtIn());
    final sigs = s.format == SetFormat.homeAssistant
        ? SetParser.homeAssistant(text, idx, s.id)
        : SetParser.fieldwatch(text, idx, s.id);
    final f = await _file(s.id);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({'fleets': [for (final x in sigs) x.toJson()]}));
    _sigs[s.id] = sigs;
    s
      ..count = sigs.length
      ..updatedAt = DateTime.now().millisecondsSinceEpoch
      ..error = null;
  }

  Future<void> setEnabled(String id, bool on) async {
    await _loaded;
    final s = _byId(id);
    if (s == null) return;
    s.enabled = on;
    notifyListeners();
    await _saveMeta();
    if (on && !_sigs.containsKey(id) && s.url != null) await update(id);
  }

  Future<void> update(String id) async {
    await _loaded;
    final s = _byId(id);
    final url = s?.url;
    if (s == null || url == null || busy.contains(id)) return;
    busy.add(id);
    s.error = null;
    notifyListeners();
    try {
      await _store(s, await _fetch(Uri.parse(url)));
    } on SetError catch (e) {
      s.error = e.message;
    } on FileSystemException catch (e) {
      s.error = 'Could not save the set: ${e.message}';
    } on Exception catch (e) {
      s.error = 'Update failed: $e';
      DebugLog.log('SETS: ${s.id} update failed: $e');
    } finally {
      busy.remove(id);
      notifyListeners();
    }
    await _saveMeta();
  }

  Future<void> addLink(String link, String name) async {
    final u = Uri.tryParse(link.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) throw const SetError('Use a link that starts with https://');
    await _loaded;
    final s = SignatureSet(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? u.host : name.trim(),
      url: u.toString(),
      source: u.host,
      enabled: true,
    );
    sets.add(s);
    notifyListeners();
    await _saveMeta();
    await update(s.id);
  }

  Future<void> addFile(String text, String name) async {
    await _loaded;
    final s = SignatureSet(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Imported set' : name.trim(),
      source: 'file',
      enabled: true,
    );
    await _store(s, text);
    sets.add(s);
    notifyListeners();
    await _saveMeta();
  }

  Future<void> remove(String id) async {
    await _loaded;
    final s = _byId(id);
    if (s == null || s.preset) return;
    sets.remove(s);
    _sigs.remove(id);
    final f = await _file(id);
    if (await f.exists()) await f.delete();
    notifyListeners();
    await _saveMeta();
  }
}

final signatureSetsProvider = ChangeNotifierProvider<SignatureSets>((ref) => SignatureSets());
