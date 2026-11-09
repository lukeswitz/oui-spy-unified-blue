import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'signature_engine.dart';

class UserSignatures extends ChangeNotifier {
  UserSignatures() {
    _loaded = _load();
  }

  static const prefsKey = 'user_signatures_v1';

  final items = <Signature>[];
  late final Future<void> _loaded;

  Future<void> get loaded => _loaded;

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(prefsKey);
    if (raw == null) return;
    try {
      items.addAll([for (final j in jsonDecode(raw) as List) Signature.fromJson(j as Map<String, dynamic>)]);
    } on FormatException catch (e) {
      DebugLog.log('SIGS: stored user signatures unreadable, kept as is: $e');
      return;
    } on TypeError catch (e) {
      DebugLog.log('SIGS: stored user signatures unreadable, kept as is: $e');
      return;
    }
    notifyListeners();
  }

  bool hasRule(MatchRule r) => items.any(
        (s) => s.rules.any((x) => x.kind == r.kind && x.text == r.text && x.companyId == r.companyId),
      );

  Future<void> add(Signature s) async {
    await _loaded;
    items.add(s);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    await _loaded;
    items.removeWhere((s) => s.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> setAlert(String id, bool on) async {
    await _loaded;
    final i = items.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final s = items[i];
    items[i] = Signature(
      id: s.id,
      name: s.name,
      kind: s.kind,
      enabled: s.enabled,
      matchAny: s.matchAny,
      rules: s.rules,
      notes: s.notes,
      alert: on,
    );
    notifyListeners();
    await _save();
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(prefsKey, jsonEncode([for (final s in items) s.toJson()]));
}

final userSignaturesProvider = ChangeNotifierProvider<UserSignatures>((ref) => UserSignatures());
