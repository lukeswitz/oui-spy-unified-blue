import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/deflock/deflock_api.dart';
import 'package:oui_spy/core/deflock/deflock_provider.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status, this.headers);
  final int status;
  final Map<String, List<String>> headers;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString('{}', status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });
  }

  @override
  void close({bool force = false}) {}
}

class _ThrottledApi extends DeflockApi {
  int calls = 0;

  @override
  Future<List<AlprNode>> fetchBounds(GeoBounds bounds, {CancelToken? cancel}) async {
    calls++;
    throw DeflockApiException('limited', retryAfter: const Duration(minutes: 1));
  }
}

const _box = GeoBounds(south: -0.01, west: -0.01, north: 0.01, east: 0.01);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Overpass 429 carries the longest Retry-After, floor 30s', () async {
    final adapter = _StatusAdapter(429, {'retry-after': ['90']});
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    await expectLater(
        DeflockApi(dio: dio).fetchBounds(_box),
        throwsA(isA<DeflockApiException>().having(
            (e) => e.retryAfter, 'retryAfter', const Duration(seconds: 90))));
    expect(adapter.calls, DeflockApi.endpoints.length);

    final short = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = _StatusAdapter(429, {'retry-after': ['5']});
    await expectLater(
        DeflockApi(dio: short).fetchBounds(_box),
        throwsA(isA<DeflockApiException>().having(
            (e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))));
  });

  test('provider sends nothing to Overpass during a rate-limit pause', () async {
    final prefs = await SharedPreferences.getInstance();
    final api = _ThrottledApi();
    final p = DeflockProvider(prefs, api: api);
    await p.ensureBounds(_box);
    await p.ensureBounds(_box);
    expect(api.calls, 1);
  });

  test('GitHub rate-limit headers set the retry time', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(
        OtaService.githubRetryAt(403,
            Headers.fromMap({'x-ratelimit-remaining': ['0'], 'x-ratelimit-reset': ['1800000000']}), now),
        DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000));
    expect(OtaService.githubRetryAt(429, Headers.fromMap({'retry-after': ['120']}), now),
        now.add(const Duration(seconds: 120)));
    expect(
        OtaService.githubRetryAt(403, Headers.fromMap({'x-ratelimit-remaining': ['12']}), now),
        isNull);
    expect(OtaService.githubRetryAt(500, Headers.fromMap({'retry-after': ['5']}), now), isNull);
  });

  test('tile cache serves fresh tiles, refetches stale ones, falls back offline',
      () async {
    final dir = await Directory.systemTemp.createTemp('tiles');
    addTearDown(() => dir.delete(recursive: true));
    var fetches = 0;
    var fail = false;
    Future<Uint8List> fetch(String url, Map<String, String> h) async {
      fetches++;
      if (fail) throw Exception('offline');
      return Uint8List.fromList([fetches]);
    }

    const url = 'https://tile.openstreetmap.org/1/0/0.png';
    expect(await cachedTileBytes(dir, url, const {}, fetch: fetch), [1]);
    expect(await cachedTileBytes(dir, url, const {}, fetch: fetch), [1]);
    expect(fetches, 1);

    final file = dir.listSync().whereType<File>().single;
    await file.setLastModified(
        DateTime.now().subtract(tileCacheTtl + const Duration(hours: 1)));
    expect(await cachedTileBytes(dir, url, const {}, fetch: fetch), [2]);
    expect(fetches, 2);

    await file.setLastModified(
        DateTime.now().subtract(tileCacheTtl + const Duration(hours: 1)));
    fail = true;
    expect(await cachedTileBytes(dir, url, const {}, fetch: fetch), [2]);
    await expectLater(
        cachedTileBytes(dir, 'https://tile.openstreetmap.org/2/0/0.png', const {},
            fetch: fetch),
        throwsException);
  });

  test('tile cache prune drops old files and the oldest over the size cap',
      () async {
    final dir = await Directory.systemTemp.createTemp('tiles');
    addTearDown(() => dir.delete(recursive: true));
    final now = DateTime.now();
    Future<File> put(String name, int size, Duration age) async {
      final f = File('${dir.path}/$name')..writeAsBytesSync(List.filled(size, 0));
      await f.setLastModified(now.subtract(age));
      return f;
    }

    final fresh = await put('a', 100, const Duration(minutes: 1));
    final older = await put('b', 100, const Duration(days: 2));
    final expired = await put('c', 10, const Duration(days: 31));
    await pruneTileCache(dir, now, maxBytes: 150);
    expect(fresh.existsSync(), isTrue);
    expect(older.existsSync(), isFalse);
    expect(expired.existsSync(), isFalse);
  });
}
