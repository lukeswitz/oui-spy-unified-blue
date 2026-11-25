// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LlmKind {
  ollama('ollama', 'Ollama', 'your Ollama server', false),
  claude('claude', 'Claude', 'Anthropic', true),
  openai('openai', 'OpenAI', 'OpenAI', true),
  gemini('gemini', 'Gemini', 'Google', true);

  const LlmKind(this.id, this.label, this.vendor, this.isCloud);
  final String id;
  final String label;
  final String vendor;
  final bool isCloud;

  String get keyName => 'assistant.key.$id';
  String get modelPref => 'assistant_model.$id';
  String get ackPref => 'assistant_ack.$id';

  static LlmKind? byId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

abstract class KeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

class SecureKeyStore implements KeyStore {
  const SecureKeyStore();
  static const _s = FlutterSecureStorage();

  @override
  Future<String?> read(String name) => _s.read(key: name);
  @override
  Future<void> write(String name, String value) => _s.write(key: name, value: value);
  @override
  Future<void> delete(String name) => _s.delete(key: name);
}

final assistantKeyStoreProvider = Provider<KeyStore>((ref) => const SecureKeyStore());

String? normalizeOllamaUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return null;
  var path = u.path.replaceAll(RegExp(r'/+$'), '');
  if (path.endsWith('/api')) path = path.substring(0, path.length - 4);
  return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : (u.scheme == 'http' ? 11434 : null), path: path).toString();
}

class AssistantSettings {
  const AssistantSettings({
    this.provider,
    this.models = const {},
    this.ollamaUrl = '',
    this.hasKey = const {},
    this.acked = const {},
  });

  final LlmKind? provider;
  final Map<LlmKind, String> models;
  final String ollamaUrl;
  final Set<LlmKind> hasKey;
  final Set<LlmKind> acked;

  String modelOf(LlmKind k) => models[k] ?? '';

  bool readyFor(LlmKind k) {
    if (modelOf(k).isEmpty) return false;
    if (k == LlmKind.ollama) return normalizeOllamaUrl(ollamaUrl) != null;
    return hasKey.contains(k) && acked.contains(k);
  }

  bool get ready => provider != null && readyFor(provider!);

  AssistantSettings copyWith({
    LlmKind? provider,
    bool clearProvider = false,
    Map<LlmKind, String>? models,
    String? ollamaUrl,
    Set<LlmKind>? hasKey,
    Set<LlmKind>? acked,
  }) =>
      AssistantSettings(
        provider: clearProvider ? null : provider ?? this.provider,
        models: models ?? this.models,
        ollamaUrl: ollamaUrl ?? this.ollamaUrl,
        hasKey: hasKey ?? this.hasKey,
        acked: acked ?? this.acked,
      );
}

class AssistantSettingsNotifier extends StateNotifier<AssistantSettings> {
  AssistantSettingsNotifier(this._store) : super(const AssistantSettings()) {
    _load();
  }

  final KeyStore _store;
  bool _changed = false;
  static const keyProvider = 'assistant_provider';
  static const keyOllamaUrl = 'assistant_ollama_url';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final keys = <LlmKind>{};
    for (final k in LlmKind.values) {
      if (!k.isCloud) continue;
      try {
        if ((await _store.read(k.keyName) ?? '').isNotEmpty) keys.add(k);
      } on Object {
        continue;
      }
    }
    if (_changed || !mounted) return;
    state = AssistantSettings(
      provider: LlmKind.byId(p.getString(keyProvider)),
      models: {for (final k in LlmKind.values) if ((p.getString(k.modelPref) ?? '').isNotEmpty) k: p.getString(k.modelPref)!},
      ollamaUrl: p.getString(keyOllamaUrl) ?? '',
      hasKey: keys,
      acked: {for (final k in LlmKind.values) if (p.getBool(k.ackPref) ?? false) k},
    );
  }

  Future<void> setProvider(LlmKind k) async {
    _changed = true;
    state = state.copyWith(provider: k);
    final p = await SharedPreferences.getInstance();
    await p.setString(keyProvider, k.id);
  }

  Future<void> acknowledge(LlmKind k) async {
    _changed = true;
    state = state.copyWith(acked: {...state.acked, k});
    final p = await SharedPreferences.getInstance();
    await p.setBool(k.ackPref, true);
  }

  Future<void> setModel(LlmKind k, String model) async {
    _changed = true;
    final next = {...state.models};
    model.trim().isEmpty ? next.remove(k) : next[k] = model.trim();
    state = state.copyWith(models: next);
    final p = await SharedPreferences.getInstance();
    await p.setString(k.modelPref, model.trim());
  }

  Future<void> setOllamaUrl(String raw) async {
    _changed = true;
    final url = normalizeOllamaUrl(raw) ?? '';
    state = state.copyWith(ollamaUrl: url);
    final p = await SharedPreferences.getInstance();
    await p.setString(keyOllamaUrl, url);
  }

  Future<void> setKey(LlmKind k, String key) async {
    _changed = true;
    final trimmed = key.trim();
    if (trimmed.isEmpty) return removeKey(k);
    await _store.write(k.keyName, trimmed);
    state = state.copyWith(hasKey: {...state.hasKey, k});
  }

  Future<void> removeKey(LlmKind k) async {
    _changed = true;
    await _store.delete(k.keyName);
    state = state.copyWith(hasKey: {...state.hasKey}..remove(k));
  }

  Future<String?> keyOf(LlmKind k) => _store.read(k.keyName);
}

final assistantSettingsProvider = StateNotifierProvider<AssistantSettingsNotifier, AssistantSettings>(
    (ref) => AssistantSettingsNotifier(ref.read(assistantKeyStoreProvider)));
