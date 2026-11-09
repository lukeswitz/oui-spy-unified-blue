import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/watchlist_state.dart';

import 'bt_sig_registry.dart';
import 'device_explain.dart';
import 'device_registry.dart';
import 'kin_index.dart';
import 'observation.dart';

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

  WatchlistEntry? get rule {
    final (type, desc) = switch (kind) {
      SuggestionKind.uuid => (WatchlistMatchType.serviceUuid, owner ?? 'Service $key'),
      SuggestionKind.oui => (WatchlistMatchType.oui, owner ?? 'Prefix $key'),
      SuggestionKind.name || SuggestionKind.company => (null, ''),
    };
    if (type == null) return null;
    final parsed = parseWatchlistImport('$key,$desc,${type.name}');
    return parsed.entries.isEmpty ? null : parsed.entries.first;
  }
}

class SignatureSuggest {
  SignatureSuggest._();

  static const minRadios = 3;
  static const maxGroups = 20;

  static bool isUnknown(ClassifiedDevice d) =>
      d.signatures.isEmpty && (d.guess.confidence == Confidence.low || DeviceExplain.isGeneric(d.guess));

  static String _hex4(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();

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
      for (final u in {for (final s in o.serviceUuids) ?uuid16(s)}) {
        if (u < 0x1800 || u > 0x18FF) add(SuggestionKind.uuid, _hex4(u), d);
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
        SuggestionKind.uuid => Suggestion(kind, key, ds, owner: BtSigRegistry.memberUuids[int.parse(key, radix: 16)]),
        SuggestionKind.oui => Suggestion(kind, key, ds,
            owner: ds.map((d) => d.vendor).firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null)),
        SuggestionKind.name => Suggestion(kind, key, ds,
            sample: ds.map((d) => d.obs.name.trim()).firstWhere((n) => n.isNotEmpty, orElse: () => key)),
        SuggestionKind.company => Suggestion(kind, key, ds, owner: BtSigRegistry.companies[int.parse(key, radix: 16)]),
      };
}
