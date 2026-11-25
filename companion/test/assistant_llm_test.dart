// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/assistant/assistant_llm.dart';
import 'package:oui_spy/core/assistant/assistant_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Seen {
  Seen(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final Map<String, dynamic>? body;
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.route);
  final (int, Object) Function(RequestOptions o) route;
  final seen = <Seen>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final data = options.data;
    seen.add(Seen(options.method, options.uri, Map<String, dynamic>.from(options.headers), data is String ? jsonDecode(data) as Map<String, dynamic> : null));
    final (status, body) = route(options);
    return ResponseBody.fromString(body is String ? body : jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class ThrowingAdapter implements HttpClientAdapter {
  ThrowingAdapter(this.message);
  final String message;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: message);
  @override
  void close({bool force = false}) {}
}

Dio dioWith(HttpClientAdapter a) => Dio()..httpClientAdapter = a;

const tools = [
  ToolSpec('app_devices', 'Devices', {
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'description': 'How many', 'minimum': 1, 'maximum': 100},
    },
  }),
];

const turns = <Turn>[
  UserTurn('what is new'),
  ModelTurn('', [ToolCall('toolu_1', 'app_devices', {'limit': 5})]),
  ToolTurn('toolu_1', 'app_devices', '{"total":0}'),
  ToolTurn('toolu_2', 'app_devices', '', isError: true),
];

class MemKeys implements KeyStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String name) async => map[name];
  @override
  Future<void> write(String name, String value) async => map[name] = value;
  @override
  Future<void> delete(String name) async => map.remove(name);
}

void main() {
  const secret = 'sk-test-SECRET-123';

  group('Anthropic', () {
    test('request shape and parsing', () async {
      final a = FakeAdapter((o) => (
            200,
            {
              'content': [
                {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
                {'type': 'text', 'text': 'Looking.'},
                {'type': 'tool_use', 'id': 'toolu_9', 'name': 'app_devices', 'input': {'limit': 3}},
              ],
              'stop_reason': 'tool_use',
            }
          ));
      final llm = AnthropicLlm(apiKey: secret, model: 'claude-test', dio: dioWith(a));
      final r = await llm.send(system: 'sys', turns: turns, tools: tools);
      final s = a.seen.single;
      expect(s.uri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(s.headers['x-api-key'], secret);
      expect(s.headers['anthropic-version'], '2026-10-21');
      expect(s.uri.toString(), isNot(contains(secret)));
      final b = s.body!;
      expect(b['model'], 'claude-test');
      expect(b['system'], 'sys');
      expect(b.containsKey('temperature'), isFalse);
      expect((b['tools'] as List).single['input_schema']['type'], 'object');
      final msgs = b['messages'] as List;
      expect(msgs.map((m) => m['role']).toList(), ['user', 'assistant', 'user']);
      final results = msgs.last['content'] as List;
      expect(results, hasLength(2));
      expect(results[0]['type'], 'tool_result');
      expect(results[1]['is_error'], true);
      expect(results[1]['content'], '(no output)');
      expect(r.text, 'Looking.');
      expect(r.calls.single.name, 'app_devices');
      expect(r.calls.single.args['limit'], 3);
      expect(r.raw, hasLength(3));
    });

    test('raw content is replayed unchanged', () {
      final raw = <Object?>[
        {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
        {'type': 'tool_use', 'id': 'toolu_9', 'name': 'x', 'input': {}},
      ];
      final msgs = AnthropicLlm.messagesOf([const UserTurn('hi'), ModelTurn('', const [], raw)]);
      expect(msgs.last['content'], raw);
    });

    test('an error never carries the key', () async {
      final a = FakeAdapter((o) => (401, {'error': {'message': 'invalid x-api-key $secret'}}));
      final llm = AnthropicLlm(apiKey: secret, model: 'm', dio: dioWith(a));
      await expectLater(
        llm.check(),
        throwsA(isA<LlmError>().having((e) => e.message, 'message', allOf(contains('401'), contains('[key]'), isNot(contains(secret))))),
      );
    });

    test('a network failure never carries the key', () async {
      final llm = AnthropicLlm(apiKey: secret, model: 'm', dio: dioWith(ThrowingAdapter('failed with $secret')));
      await expectLater(
        llm.send(system: 's', turns: const [UserTurn('x')], tools: const []),
        throwsA(isA<LlmError>().having((e) => e.message, 'message', allOf(contains("Can't reach Claude"), isNot(contains(secret))))),
      );
    });

    test('models lists ids', () async {
      final a = FakeAdapter((o) => (200, {'data': [{'id': 'claude-a'}, {'id': 'claude-b'}]}));
      expect(await AnthropicLlm(apiKey: secret, model: '', dio: dioWith(a)).models(), ['claude-a', 'claude-b']);
    });
  });

  group('OpenAI', () {
    test('request shape and parsing', () async {
      final a = FakeAdapter((o) => (
            200,
            {
              'choices': [
                {
                  'finish_reason': 'tool_calls',
                  'message': {
                    'content': null,
                    'tool_calls': [
                      {'id': 'call_a', 'type': 'function', 'function': {'name': 'app_devices', 'arguments': '{"limit": 2}'}},
                    ],
                  },
                },
              ],
            }
          ));
      final llm = OpenAiLlm(apiKey: secret, model: 'gpt-test', dio: dioWith(a));
      final r = await llm.send(system: 'sys', turns: turns, tools: tools);
      final s = a.seen.single;
      expect(s.uri.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(s.headers['authorization'], 'Bearer $secret');
      final msgs = s.body!['messages'] as List;
      expect(msgs.first, {'role': 'system', 'content': 'sys'});
      expect(msgs[2]['tool_calls'][0]['function']['arguments'], '{"limit":5}');
      expect(msgs[3]['role'], 'tool');
      expect(r.calls.single.args, {'limit': 2});
    });

    test('model list keeps chat models only', () async {
      final a = FakeAdapter((o) => (200, {'data': [{'id': 'gpt-x'}, {'id': 'text-embedding-3'}, {'id': 'o3'}, {'id': 'gpt-4o-realtime'}, {'id': 'whisper-1'}]}));
      expect(await OpenAiLlm(apiKey: secret, model: '', dio: dioWith(a)).models(), ['gpt-x', 'o3']);
    });
  });

  group('Gemini', () {
    test('key goes in a header and the schema is reduced', () async {
      final a = FakeAdapter((o) => (
            200,
            {
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'thinking', 'thought': true},
                      {'functionCall': {'name': 'app_devices', 'args': {'limit': 1}}, 'thoughtSignature': 'abc'},
                    ],
                  },
                },
              ],
            }
          ));
      final llm = GeminiLlm(apiKey: secret, model: 'gemini-test', dio: dioWith(a));
      final r = await llm.send(system: 'sys', turns: turns, tools: tools);
      final s = a.seen.single;
      expect(s.uri.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent');
      expect(s.uri.toString(), isNot(contains(secret)));
      expect(s.headers['x-goog-api-key'], secret);
      final decl = (s.body!['tools'] as List).single['functionDeclarations'][0];
      expect(decl['parameters']['properties']['limit'].containsKey('minimum'), isFalse);
      expect(decl['parameters']['properties']['limit']['type'], 'integer');
      final contents = s.body!['contents'] as List;
      expect(contents.map((c) => c['role']).toList(), ['user', 'model', 'user']);
      expect((contents.last['parts'] as List), hasLength(2));
      expect(contents.last['parts'][1]['functionResponse']['response'], {'error': '(no output)'});
      expect(r.text, '');
      expect(r.calls.single.name, 'app_devices');
      expect(r.raw, hasLength(2));
    });

    test('a bad model name is refused before any request', () async {
      final a = FakeAdapter((o) => (200, {}));
      final llm = GeminiLlm(apiKey: secret, model: '../x', dio: dioWith(a));
      await expectLater(llm.send(system: 's', turns: const [UserTurn('x')], tools: const []), throwsA(isA<LlmError>()));
      expect(a.seen, isEmpty);
    });

    test('model list keeps gemini models that can generate', () async {
      final a = FakeAdapter((o) => (
            200,
            {
              'models': [
                {'name': 'models/gemini-a', 'supportedGenerationMethods': ['generateContent']},
                {'name': 'models/gemini-embed', 'supportedGenerationMethods': ['embedContent']},
                {'name': 'models/other', 'supportedGenerationMethods': ['generateContent']},
              ],
            }
          ));
      expect(await GeminiLlm(apiKey: secret, model: '', dio: dioWith(a)).models(), ['gemini-a']);
    });
  });

  group('Ollama', () {
    test('request shape and parsing', () async {
      final a = FakeAdapter((o) => (
            200,
            {
              'message': {
                'content': '',
                'tool_calls': [
                  {'function': {'name': 'app_devices', 'arguments': {'limit': 4}}},
                ],
              },
              'done_reason': 'stop',
            }
          ));
      final llm = OllamaLlm(baseUrl: 'http://192.0.2.10:11434', model: 'qwen3:8b', dio: dioWith(a));
      final r = await llm.send(system: 'sys', turns: turns, tools: tools);
      final s = a.seen.single;
      expect(s.uri.toString(), 'http://192.0.2.10:11434/api/chat');
      expect(s.headers.containsKey('x-api-key'), isFalse);
      expect(s.body!['stream'], false);
      expect((s.body!['messages'] as List)[3], {'role': 'tool', 'tool_name': 'app_devices', 'content': '{"total":0}'});
      expect(r.calls.single.args, {'limit': 4});
      expect(r.calls.single.id, isNotEmpty);
    });

    test('check reports models, and none', () async {
      final some = FakeAdapter((o) => (200, {'models': [{'name': 'a'}, {'name': 'b'}]}));
      expect(await OllamaLlm(baseUrl: 'http://x', model: '', dio: dioWith(some)).check(), 'Ollama answers: 2 models');
      final none = FakeAdapter((o) => (200, {'models': []}));
      expect(await OllamaLlm(baseUrl: 'http://x', model: '', dio: dioWith(none)).check(), contains('no models yet'));
    });
  });

  test('normalizeOllamaUrl', () {
    expect(normalizeOllamaUrl('192.0.2.10'), 'http://192.0.2.10:11434');
    expect(normalizeOllamaUrl('http://192.0.2.10:9000/api/'), 'http://192.0.2.10:9000');
    expect(normalizeOllamaUrl('https://ollama.example.com'), 'https://ollama.example.com');
    expect(normalizeOllamaUrl('ftp://x'), isNull);
    expect(normalizeOllamaUrl('  '), isNull);
  });

  group('settings and keys', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('the key lives only in the key store', () async {
      final keys = MemKeys();
      final c = ProviderContainer(overrides: [assistantKeyStoreProvider.overrideWithValue(keys)]);
      addTearDown(c.dispose);
      final n = c.read(assistantSettingsProvider.notifier);
      await n.setKey(LlmKind.claude, '  $secret ');
      expect(keys.map['assistant.key.claude'], secret);
      expect(c.read(assistantSettingsProvider).hasKey, {LlmKind.claude});
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect('${prefs.get(k)}', isNot(contains(secret)), reason: k);
      }
      await n.removeKey(LlmKind.claude);
      expect(keys.map, isEmpty);
      expect(c.read(assistantSettingsProvider).hasKey, isEmpty);
    });

    test('a cloud provider needs a key, an acknowledgement and a model', () async {
      final keys = MemKeys();
      final c = ProviderContainer(overrides: [assistantKeyStoreProvider.overrideWithValue(keys)]);
      addTearDown(c.dispose);
      final n = c.read(assistantSettingsProvider.notifier);
      await n.setProvider(LlmKind.claude);
      expect(c.read(assistantSettingsProvider).ready, isFalse);
      await n.setKey(LlmKind.claude, secret);
      await n.setModel(LlmKind.claude, 'claude-test');
      expect(c.read(assistantSettingsProvider).ready, isFalse);
      await n.acknowledge(LlmKind.claude);
      expect(c.read(assistantSettingsProvider).ready, isTrue);
      final p = await buildProvider(c.read(assistantSettingsProvider), keys);
      expect(p, isA<AnthropicLlm>());
    });

    test('Ollama needs an address and a model but no key', () async {
      final c = ProviderContainer(overrides: [assistantKeyStoreProvider.overrideWithValue(MemKeys())]);
      addTearDown(c.dispose);
      final n = c.read(assistantSettingsProvider.notifier);
      await n.setProvider(LlmKind.ollama);
      await n.setOllamaUrl('192.0.2.10');
      await n.setModel(LlmKind.ollama, 'qwen3:8b');
      expect(c.read(assistantSettingsProvider).ready, isTrue);
      expect(await buildProvider(c.read(assistantSettingsProvider), MemKeys()), isA<OllamaLlm>());
    });

    test('nothing is chosen by default', () async {
      final c = ProviderContainer(overrides: [assistantKeyStoreProvider.overrideWithValue(MemKeys())]);
      addTearDown(c.dispose);
      expect(c.read(assistantSettingsProvider).provider, isNull);
      expect(c.read(assistantSettingsProvider).ready, isFalse);
    });
  });
}
