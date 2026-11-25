// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:oui_spy/core/assistant/assistant_settings.dart';
import 'package:oui_spy/core/assistant/assistant_tools.dart';

class LlmError implements Exception {
  LlmError(this.message);
  final String message;
  @override
  String toString() => message;
}

class ToolCall {
  const ToolCall(this.id, this.name, this.args);
  final String id;
  final String name;
  final Map<String, dynamic> args;
}

sealed class Turn {
  const Turn();
}

class UserTurn extends Turn {
  const UserTurn(this.text);
  final String text;
}

class ModelTurn extends Turn {
  const ModelTurn(this.text, this.calls, [this.raw]);
  final String text;
  final List<ToolCall> calls;
  final List<Object?>? raw;
}

class ToolTurn extends Turn {
  const ToolTurn(this.callId, this.name, this.output, {this.isError = false});
  final String callId;
  final String name;
  final String output;
  final bool isError;
}

class LlmReply {
  const LlmReply(this.text, this.calls, {this.raw, this.stop = ''});
  final String text;
  final List<ToolCall> calls;
  final List<Object?>? raw;
  final String stop;
}

class ToolSpec {
  const ToolSpec(this.name, this.description, this.schema);
  final String name;
  final String description;
  final Map<String, dynamic> schema;

  factory ToolSpec.of(AssistantTool t) => ToolSpec(t.name, t.description, t.schema);
}

abstract class LlmProvider {
  LlmKind get kind;
  Future<LlmReply> send({required String system, required List<Turn> turns, required List<ToolSpec> tools});
  Future<List<String>> models();
  Future<String> check();
}

const anthropicVersion = '2026-10-21';
const anthropicBase = 'https://api.anthropic.com';
const openAiBase = 'https://api.openai.com';
const geminiBase = 'https://generativelanguage.googleapis.com/v1beta';
const emptyOutput = '(no output)';

String safeId(String id) {
  final s = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return s.isEmpty ? 'call' : s;
}

Map<String, dynamic> _args(Object? v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.trim().isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    } on FormatException {
      return const {};
    }
  }
  return const {};
}

int _seq = 0;
String _newCallId() => 'call_${++_seq}';

abstract class HttpLlm implements LlmProvider {
  HttpLlm({Dio? dio, this.secret = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
              followRedirects: false,
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ));

  final Dio _dio;
  final String secret;

  String scrub(String s) => secret.isEmpty ? s : s.replaceAll(secret, '[key]');

  static String _errorText(Object? decoded, String raw) {
    if (decoded is Map && decoded['error'] != null) {
      final e = decoded['error'];
      final m = e is Map ? (e['message'] ?? e['type'] ?? e['status']) : e;
      if (m != null) return '$m';
    }
    final t = raw.trim();
    return t.isEmpty ? 'an error' : (t.length > 200 ? '${t.substring(0, 200)}...' : t);
  }

  Future<Map<String, dynamic>> call(String method, String url, {Map<String, String> headers = const {}, Object? body}) async {
    Response<String> r;
    try {
      r = await _dio.request<String>(
        url,
        data: body == null ? null : jsonEncode(body),
        options: Options(
          method: method,
          headers: {'content-type': 'application/json', ...headers},
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      final what = e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout
          ? '${kind.label} did not answer in time'
          : "Can't reach ${kind.label}: ${e.message ?? e.type.name}";
      throw LlmError(scrub(what));
    }
    final text = r.data ?? '';
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    final code = r.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw LlmError(scrub('${kind.label} answered $code: ${_errorText(decoded, text)}'));
    }
    if (decoded is! Map) throw LlmError('${kind.label} answered with something that is not JSON');
    return Map<String, dynamic>.from(decoded);
  }
}

List<Map<String, dynamic>> _mergeRoles(List<Map<String, dynamic>> msgs, String contentKey) {
  final out = <Map<String, dynamic>>[];
  for (final m in msgs) {
    if (out.isNotEmpty && out.last['role'] == m['role']) {
      (out.last[contentKey] as List).addAll(m[contentKey] as List);
    } else {
      out.add({'role': m['role'], contentKey: [...(m[contentKey] as List)]});
    }
  }
  return out;
}

class AnthropicLlm extends HttpLlm {
  AnthropicLlm({required this.apiKey, required this.model, super.dio}) : super(secret: apiKey);
  final String apiKey;
  final String model;

  @override
  LlmKind get kind => LlmKind.claude;

  Map<String, String> get _headers => {'x-api-key': apiKey, 'anthropic-version': anthropicVersion};

  @override
  Future<String> check() async {
    await call('GET', '$anthropicBase/v1/models?limit=1', headers: _headers);
    return 'The key works';
  }

  @override
  Future<List<String>> models() async {
    final j = await call('GET', '$anthropicBase/v1/models?limit=1000', headers: _headers);
    return [for (final m in (j['data'] as List? ?? const [])) if (m is Map && m['id'] is String) m['id'] as String];
  }

  static List<Map<String, dynamic>> messagesOf(List<Turn> turns) {
    final msgs = <Map<String, dynamic>>[];
    for (final t in turns) {
      switch (t) {
        case UserTurn():
          msgs.add({'role': 'user', 'content': [{'type': 'text', 'text': t.text}]});
        case ModelTurn():
          msgs.add({
            'role': 'assistant',
            'content': t.raw ??
                [
                  if (t.text.isNotEmpty) {'type': 'text', 'text': t.text},
                  for (final c in t.calls) {'type': 'tool_use', 'id': safeId(c.id), 'name': c.name, 'input': c.args},
                ],
          });
        case ToolTurn():
          msgs.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': safeId(t.callId),
                'content': t.output.isEmpty ? emptyOutput : t.output,
                if (t.isError) 'is_error': true,
              },
            ],
          });
      }
    }
    return _mergeRoles(msgs, 'content');
  }

  @override
  Future<LlmReply> send({required String system, required List<Turn> turns, required List<ToolSpec> tools}) async {
    final j = await call('POST', '$anthropicBase/v1/messages', headers: _headers, body: {
      'model': model,
      'max_tokens': 8192,
      'system': system,
      'messages': messagesOf(turns),
      if (tools.isNotEmpty)
        'tools': [for (final t in tools) {'name': t.name, 'description': t.description, 'input_schema': t.schema}],
    });
    final content = (j['content'] as List? ?? const []);
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final b in content) {
      if (b is! Map) continue;
      if (b['type'] == 'text') {
        if (text.isNotEmpty) text.write('\n');
        text.write(b['text'] ?? '');
      } else if (b['type'] == 'tool_use') {
        calls.add(ToolCall('${b['id'] ?? _newCallId()}', '${b['name'] ?? ''}', _args(b['input'])));
      }
    }
    final stop = '${j['stop_reason'] ?? ''}';
    return LlmReply(text.toString(), calls, raw: content, stop: stop);
  }
}

class OpenAiLlm extends HttpLlm {
  OpenAiLlm({required this.apiKey, required this.model, super.dio}) : super(secret: apiKey);
  final String apiKey;
  final String model;

  @override
  LlmKind get kind => LlmKind.openai;

  Map<String, String> get _headers => {'authorization': 'Bearer $apiKey'};

  static bool chatModel(String id) {
    final ok = id.startsWith('gpt-') || id.startsWith('chatgpt-') || RegExp(r'^o\d').hasMatch(id);
    final other = ['audio', 'realtime', 'transcribe', 'tts', 'image', 'search', 'embedding', 'moderation', 'instruct']
        .any(id.contains);
    return ok && !other;
  }

  @override
  Future<String> check() async {
    final n = (await models()).length;
    return 'The key works: $n chat model${n == 1 ? '' : 's'}';
  }

  @override
  Future<List<String>> models() async {
    final j = await call('GET', '$openAiBase/v1/models', headers: _headers);
    return [for (final m in (j['data'] as List? ?? const [])) if (m is Map && m['id'] is String && chatModel(m['id'] as String)) m['id'] as String]
      ..sort();
  }

  static List<Map<String, dynamic>> messagesOf(String system, List<Turn> turns) => [
        {'role': 'system', 'content': system},
        for (final t in turns)
          switch (t) {
            UserTurn() => {'role': 'user', 'content': t.text},
            ModelTurn() => {
                'role': 'assistant',
                'content': t.text.isEmpty ? null : t.text,
                if (t.calls.isNotEmpty)
                  'tool_calls': [
                    for (final c in t.calls)
                      {'id': safeId(c.id), 'type': 'function', 'function': {'name': c.name, 'arguments': jsonEncode(c.args)}},
                  ],
              },
            ToolTurn() => {'role': 'tool', 'tool_call_id': safeId(t.callId), 'content': t.output.isEmpty ? emptyOutput : t.output},
          },
      ];

  @override
  Future<LlmReply> send({required String system, required List<Turn> turns, required List<ToolSpec> tools}) async {
    final j = await call('POST', '$openAiBase/v1/chat/completions', headers: _headers, body: {
      'model': model,
      'messages': messagesOf(system, turns),
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools) {'type': 'function', 'function': {'name': t.name, 'description': t.description, 'parameters': t.schema}},
        ],
    });
    final choices = j['choices'] as List? ?? const [];
    if (choices.isEmpty || choices.first is! Map) return const LlmReply('', []);
    final choice = Map<String, dynamic>.from(choices.first as Map);
    final msg = choice['message'] is Map ? Map<String, dynamic>.from(choice['message'] as Map) : <String, dynamic>{};
    final calls = <ToolCall>[
      for (final c in (msg['tool_calls'] as List? ?? const []))
        if (c is Map && c['function'] is Map)
          ToolCall('${c['id'] ?? _newCallId()}', '${(c['function'] as Map)['name'] ?? ''}', _args((c['function'] as Map)['arguments'])),
    ];
    final text = '${msg['content'] ?? msg['refusal'] ?? ''}';
    return LlmReply(text, calls, stop: '${choice['finish_reason'] ?? ''}');
  }
}

class GeminiLlm extends HttpLlm {
  GeminiLlm({required this.apiKey, required this.model, super.dio}) : super(secret: apiKey);
  final String apiKey;
  final String model;

  @override
  LlmKind get kind => LlmKind.gemini;

  Map<String, String> get _headers => {'x-goog-api-key': apiKey};

  @override
  Future<String> check() async {
    final n = (await models()).length;
    return 'The key works: $n Gemini model${n == 1 ? '' : 's'}';
  }

  @override
  Future<List<String>> models() async {
    final out = <String>[];
    String? page;
    for (var i = 0; i < 10; i++) {
      final j = await call('GET', '$geminiBase/models?pageSize=1000${page == null ? '' : '&pageToken=${Uri.encodeQueryComponent(page)}'}',
          headers: _headers);
      for (final m in (j['models'] as List? ?? const [])) {
        if (m is! Map) continue;
        final name = '${m['name'] ?? ''}'.replaceFirst('models/', '');
        final methods = (m['supportedGenerationMethods'] as List? ?? const []);
        if (name.startsWith('gemini-') && methods.contains('generateContent')) out.add(name);
      }
      page = j['nextPageToken'] as String?;
      if (page == null || page.isEmpty) break;
    }
    return out..sort();
  }

  static const _schemaKeys = {'type', 'description', 'properties', 'items', 'enum', 'required', 'nullable'};

  static Map<String, dynamic> schemaOf(Map<String, dynamic> s) {
    final out = <String, dynamic>{};
    for (final e in s.entries) {
      if (!_schemaKeys.contains(e.key)) continue;
      if (e.key == 'properties' && e.value is Map) {
        out['properties'] = {for (final p in (e.value as Map).entries) '${p.key}': schemaOf(Map<String, dynamic>.from(p.value as Map))};
      } else if (e.key == 'items' && e.value is Map) {
        out['items'] = schemaOf(Map<String, dynamic>.from(e.value as Map));
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> contentsOf(List<Turn> turns) {
    final msgs = <Map<String, dynamic>>[];
    for (final t in turns) {
      switch (t) {
        case UserTurn():
          msgs.add({'role': 'user', 'parts': [{'text': t.text}]});
        case ModelTurn():
          msgs.add({
            'role': 'model',
            'parts': t.raw ??
                [
                  if (t.text.isNotEmpty) {'text': t.text},
                  for (final c in t.calls) {'functionCall': {'name': c.name, 'args': c.args}},
                ],
          });
        case ToolTurn():
          msgs.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': t.name,
                  'response': {(t.isError ? 'error' : 'output'): t.output.isEmpty ? emptyOutput : t.output},
                },
              },
            ],
          });
      }
    }
    return _mergeRoles(msgs, 'parts');
  }

  @override
  Future<LlmReply> send({required String system, required List<Turn> turns, required List<ToolSpec> tools}) async {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(model)) throw LlmError('That Gemini model name is not valid.');
    final j = await call('POST', '$geminiBase/models/$model:generateContent', headers: _headers, body: {
      'systemInstruction': {'parts': [{'text': system}]},
      'contents': contentsOf(turns),
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final t in tools) {'name': t.name, 'description': t.description, 'parameters': schemaOf(t.schema)},
            ],
          },
        ],
    });
    final cands = j['candidates'] as List? ?? const [];
    if (cands.isEmpty || cands.first is! Map) {
      final block = (j['promptFeedback'] is Map ? (j['promptFeedback'] as Map)['blockReason'] : null) ?? 'no answer';
      return LlmReply('', const [], stop: '$block');
    }
    final cand = Map<String, dynamic>.from(cands.first as Map);
    final parts = ((cand['content'] is Map ? (cand['content'] as Map)['parts'] : null) as List?) ?? const [];
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final p in parts) {
      if (p is! Map) continue;
      if (p['functionCall'] is Map) {
        final f = p['functionCall'] as Map;
        calls.add(ToolCall('${f['id'] ?? _newCallId()}', '${f['name'] ?? ''}', _args(f['args'])));
      } else if (p['text'] is String && p['thought'] != true) {
        text.write(p['text']);
      }
    }
    return LlmReply(text.toString(), calls, raw: parts, stop: '${cand['finishReason'] ?? ''}');
  }
}

class OllamaLlm extends HttpLlm {
  OllamaLlm({required this.baseUrl, required this.model, super.dio});
  final String baseUrl;
  final String model;

  @override
  LlmKind get kind => LlmKind.ollama;

  @override
  Future<String> check() async {
    final n = (await models()).length;
    if (n == 0) return 'Ollama answers but has no models yet: pull one on the server (ollama pull qwen3)';
    return 'Ollama answers: $n model${n == 1 ? '' : 's'}';
  }

  @override
  Future<List<String>> models() async {
    final j = await call('GET', '$baseUrl/api/tags');
    return [for (final m in (j['models'] as List? ?? const [])) if (m is Map && m['name'] is String) m['name'] as String];
  }

  static List<Map<String, dynamic>> messagesOf(String system, List<Turn> turns) => [
        {'role': 'system', 'content': system},
        for (final t in turns)
          switch (t) {
            UserTurn() => {'role': 'user', 'content': t.text},
            ModelTurn() => {
                'role': 'assistant',
                'content': t.text,
                if (t.calls.isNotEmpty)
                  'tool_calls': [
                    for (final c in t.calls) {'function': {'name': c.name, 'arguments': c.args}},
                  ],
              },
            ToolTurn() => {'role': 'tool', 'tool_name': t.name, 'content': t.output.isEmpty ? emptyOutput : t.output},
          },
      ];

  @override
  Future<LlmReply> send({required String system, required List<Turn> turns, required List<ToolSpec> tools}) async {
    final j = await call('POST', '$baseUrl/api/chat', body: {
      'model': model,
      'stream': false,
      'messages': messagesOf(system, turns),
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools) {'type': 'function', 'function': {'name': t.name, 'description': t.description, 'parameters': t.schema}},
        ],
      'options': {'num_ctx': 16384},
    });
    final msg = j['message'] is Map ? Map<String, dynamic>.from(j['message'] as Map) : <String, dynamic>{};
    final calls = <ToolCall>[
      for (final c in (msg['tool_calls'] as List? ?? const []))
        if (c is Map && c['function'] is Map)
          ToolCall(_newCallId(), '${(c['function'] as Map)['name'] ?? ''}', _args((c['function'] as Map)['arguments'])),
    ];
    return LlmReply('${msg['content'] ?? ''}', calls, stop: '${j['done_reason'] ?? ''}');
  }
}

Future<LlmProvider?> buildProvider(AssistantSettings s, KeyStore store, {Dio? dio}) async {
  final kind = s.provider;
  if (kind == null || !s.readyFor(kind)) return null;
  return buildProviderForChecks(kind, s.ollamaUrl, store, dio: dio, model: s.modelOf(kind));
}

Future<LlmProvider?> buildProviderForChecks(LlmKind kind, String? ollamaUrl, KeyStore store, {Dio? dio, String model = ''}) async {
  if (kind == LlmKind.ollama) {
    final url = normalizeOllamaUrl(ollamaUrl ?? '');
    return url == null ? null : OllamaLlm(baseUrl: url, model: model, dio: dio);
  }
  final key = await store.read(kind.keyName);
  if (key == null || key.isEmpty) return null;
  return switch (kind) {
    LlmKind.claude => AnthropicLlm(apiKey: key, model: model, dio: dio),
    LlmKind.openai => OpenAiLlm(apiKey: key, model: model, dio: dio),
    LlmKind.gemini => GeminiLlm(apiKey: key, model: model, dio: dio),
    LlmKind.ollama => null,
  };
}
