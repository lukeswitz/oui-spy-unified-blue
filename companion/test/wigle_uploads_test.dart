import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'results': [
          {'transid': '20261103-00001', 'fileName': 'ouispy_wardrive_20261103_093505.csv', 'status': 'D'},
          {'transid': '20261102-00007', 'fileName': 'WigleWifi_20261102.csv.gz'},
          'garbage',
        ],
      }),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('upload list reads transid and fileName from /file/transactions', () async {
    final a = _Adapter();
    final api = WigleApi(apiName: 'a', apiToken: 'b', adapter: a);
    final files = await api.uploadedFiles();
    expect(a.last!.path, '/file/transactions');
    expect(a.last!.queryParameters['pagestart'], 0);
    expect(files.length, 2);
    expect(files.first.transId, '20261103-00001');
    expect(files.first.fileName.contains('ouispy_wardrive_20261103_093505'), isTrue);
  });
}
