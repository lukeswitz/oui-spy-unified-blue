import 'package:oui_spy/core/privacy.dart';

import 'bt_sig_registry.dart';
import 'device_explain.dart';
import 'device_registry.dart';
import 'kin_index.dart';
import 'observation.dart';
import 'signature_engine.dart';

enum SuggestionKind { uuid, oui, name, company }

class Suggestion {
  Suggestion(this.kind, this.key, this.devices, {this.owner, this.sample = ''});

  final SuggestionKind kind;
  final String key;
  final List<ClassifiedDevice> devices;
  final String? owner;
  final String sample;
  final also = <Suggestion>[];

  String label({bool masked = false}) {
    final of = owner == null ? '' : ' ($owner)';
    return switch (kind) {
      SuggestionKind.uuid => 'Service $key$of',
      SuggestionKind.oui => 'Vendor prefix ${masked ? '${key.substring(0, 5)}:XX' : key}$of',
      SuggestionKind.name => 'Name like "${maskName(sample, masked)}"',
      SuggestionKind.company => 'Bluetooth company 0x$key$of',
    };
  }

  RadioKind? get _radio {
    final kinds = {for (final d in devices) d.obs.kind};
    return kinds.length == 1 ? kinds.single : null;
  }

  String get nameGlob {
    final s = sample.trim();
    if (s.length < key.length || s.substring(0, key.length).toLowerCase() != key) return '$key*';
    final next = s.length > key.length ? s[key.length] : '';
    return '${s.substring(0, key.length)}${next.isNotEmpty && ' -_:#'.contains(next) ? next : ''}*';
  }

  MatchRule get matchRule => switch (kind) {
        SuggestionKind.uuid => MatchRule(RuleKind.serviceUuid, text: key, radio: RadioKind.ble),
        SuggestionKind.oui => MatchRule(RuleKind.macPrefix, text: key, radio: _radio),
        SuggestionKind.name => MatchRule(RuleKind.nameGlob, text: nameGlob, radio: _radio),
        SuggestionKind.company =>
          MatchRule(RuleKind.manufacturerId, companyId: int.parse(key, radix: 16), radio: RadioKind.ble),
      };

  String get defaultName => switch (kind) {
        SuggestionKind.uuid => owner ?? 'Service $key',
        SuggestionKind.oui => owner ?? 'Prefix $key',
        SuggestionKind.name => '${nameGlob.replaceFirst(RegExp(r'[ \-_:#]?\*$'), '')} devices',
        SuggestionKind.company => owner ?? 'Company 0x$key',
      };

  Signature toSignature({required String name, required SignatureClass kind, required bool alert}) => Signature(
        id: 'user-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        kind: kind,
        rules: [matchRule],
        notes: 'Saved from a suggested group of ${devices.length} radios.',
        alert: alert,
      );
}

class SignatureSuggest {
  SignatureSuggest._();

  static const minRadios = 3;
  static const maxGroups = 20;

  static bool isUnknown(ClassifiedDevice d) =>
      d.signatures.isEmpty && (d.guess.confidence == Confidence.low || DeviceExplain.isGeneric(d.guess));

  static String _hex4(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();

  static String? _uuidKey(String raw) {
    final u16 = uuid16(raw);
    if (u16 != null) return u16 >= 0x1800 && u16 <= 0x18FF ? null : _hex4(u16);
    final h = hexOnly(raw).toUpperCase();
    if (h.length != 32 || h.endsWith('00001000800000805F9B34FB')) return null;
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static List<Suggestion> of(Iterable<ClassifiedDevice> devices) {
    final members = <(SuggestionKind, String), List<ClassifiedDevice>>{};
    void add(SuggestionKind k, String key, ClassifiedDevice d) => (members[(k, key)] ??= []).add(d);
    for (final d in devices) {
      if (!isUnknown(d)) continue;
      final o = d.obs;
      final stem = KinIndex.nameStem(o.name);
      if (stem != null) add(SuggestionKind.name, stem, d);
      if (o.mac.isNotEmpty && !o.randomized && d.vendor != null) {
        add(SuggestionKind.oui, MacUtil.prefixBytes(o.mac).toUpperCase(), d);
      }
      if (o.kind != RadioKind.ble) continue;
      for (final u in {for (final s in [...o.serviceUuids, ...o.serviceData.map((x) => x.uuid)]) ?_uuidKey(s)}) {
        add(SuggestionKind.uuid, u, d);
      }
      for (final c in {for (final m in o.mfgRecords) m.companyId}) {
        if (!KinIndex.platformCompanies.contains(c)) add(SuggestionKind.company, _hex4(c), d);
      }
    }
    final ranked = members.entries.where((e) => e.value.length >= minRadios).toList()
      ..sort((a, b) => a.key.$1.index.compareTo(b.key.$1.index));
    final bySet = <String, Suggestion>{};
    for (final e in ranked) {
      final s = _build(e.key.$1, e.key.$2, e.value);
      final set = (e.value.map((d) => d.obs.key).toList()..sort()).join('|');
      final prev = bySet[set];
      if (prev == null) {
        bySet[set] = s;
      } else {
        prev.also.add(s);
      }
    }
    final out = bySet.values.toList()
      ..sort((a, b) {
        final c = b.devices.length.compareTo(a.devices.length);
        return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
      });
    return out.take(maxGroups).toList();
  }

  static Suggestion _build(SuggestionKind kind, String key, List<ClassifiedDevice> ds) => switch (kind) {
        SuggestionKind.uuid => Suggestion(kind, key, ds,
            owner: key.length == 4 ? BtSigRegistry.memberUuids[int.parse(key, radix: 16)] : null),
        SuggestionKind.oui => Suggestion(kind, key, ds,
            owner: ds.map((d) => d.vendor).firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null)),
        SuggestionKind.name => Suggestion(kind, key, ds,
            sample: ds.map((d) => d.obs.name.trim()).firstWhere((n) => n.isNotEmpty, orElse: () => key)),
        SuggestionKind.company => Suggestion(kind, key, ds, owner: BtSigRegistry.companies[int.parse(key, radix: 16)]),
      };
}

String ruleSummary(MatchRule r, {bool masked = false}) => switch (r.kind) {
      RuleKind.nameGlob || RuleKind.nameContains => 'Name ${maskName(r.text, masked)}',
      RuleKind.serviceUuid => 'Service ${r.text}',
      RuleKind.macPrefix || RuleKind.oui => 'Prefix ${masked && r.text.length >= 5 ? '${r.text.substring(0, 5)}:XX' : r.text}',
      RuleKind.manufacturerId => 'Company 0x${r.companyId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      _ => r.kind.name,
    };
