import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status);
  int status;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'user': 'u', 'statistics': {'rank': 7}}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('429 shows message and blocks every call for 24h', () async {
    final fake = _FakeAdapter(429);
    final api = WigleApi(apiName: 'a', apiToken: 'b', adapter: fake);

    await expectLater(
        api.getUserStats(),
        throwsA(isA<WigleApiException>().having(
            (e) => e.message, 'message', WigleApi.rateLimitMessage)));
    expect(fake.calls, 1);

    fake.status = 200;
    await expectLater(api.getUserStats(), throwsA(isA<WigleApiException>()));
    await expectLater(api.getRanking(), throwsA(isA<WigleApiException>()));
    final other = WigleApi(apiName: 'c', apiToken: 'd', adapter: fake);
    await expectLater(other.getUserStats(), throwsA(isA<WigleApiException>()));
    expect(fake.calls, 1);

    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt('wigle_429_locked_until')!;
    final hours = Duration(
            milliseconds: until - DateTime.now().millisecondsSinceEpoch)
        .inMinutes;
    expect(hours, inInclusiveRange(24 * 60 - 1, 24 * 60));

    await prefs.setInt('wigle_429_locked_until',
        DateTime.now().millisecondsSinceEpoch - 1);
    final stats = await api.getUserStats();
    expect(stats.rank, 7);
    expect(fake.calls, 2);
  });

  test('non-429 error does not lock out', () async {
    final fake = _FakeAdapter(500);
    final api = WigleApi(apiName: 'a', apiToken: 'b', adapter: fake);
    await expectLater(api.getUserStats(), throwsA(isA<DioException>()));
    fake.status = 200;
    expect((await api.getUserStats()).rank, 7);
    expect(fake.calls, 2);
  });
}
