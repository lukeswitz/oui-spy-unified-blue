// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';

void main() {
  group('DashboardEndpoint.parse', () {
    test('accepts names, ports, urls and IPv6', () {
      expect(DashboardEndpoint.parse('192.0.2.5'), const DashboardEndpoint('192.0.2.5', 5077));
      expect(DashboardEndpoint.parse(' mac.local:8080 '), const DashboardEndpoint('mac.local', 8080));
      expect(DashboardEndpoint.parse('http://192.0.2.5:5077/'), const DashboardEndpoint('192.0.2.5', 5077));
      expect(DashboardEndpoint.parse('[::1]:6000'), const DashboardEndpoint('::1', 6000));
      expect(DashboardEndpoint.parse('[::1]'), const DashboardEndpoint('::1', 5077));
      expect(const DashboardEndpoint('::1', 6000).label, '[::1]:6000');
    });

    test('refuses anything else', () {
      for (final bad in ['', '  ', 'a b', 'host:0', 'host:70000', 'host:x', '[::1', '[::1]x', r'ho$t']) {
        expect(DashboardEndpoint.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('HttpDashboardApi', () {
    late HttpServer server;
    late DashboardEndpoint ep;
    final seen = <HttpRequest>[];
    final bodies = <String>[];

    setUp(() async {
      seen.clear();
      bodies.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ep = DashboardEndpoint('127.0.0.1', server.port);
      server.listen((req) async {
        seen.add(req);
        bodies.add(await utf8.decoder.bind(req).join());
        final res = req.response;
        void json(int code, Object body) {
          res.statusCode = code;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(body));
        }

        switch (req.uri.path) {
          case '/api/link':
            if (req.headers.value(HttpHeaders.cookieHeader) != 'ouispy_token=abc') {
              res.statusCode = 401;
              res.write('token please');
            } else {
              json(200, {'home': {'alive': true}});
            }
          case '/api/settings':
            json(400, {'ok': false, 'error': 'a TAK server address is needed'});
          case '/api/detections/clear':
            json(200, {'ok': true, 'n': 7});
          default:
            res.write('<html>not json</html>');
        }
        await res.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('sends the token as the dashboard cookie and reads JSON', () async {
      final r = await HttpDashboardApi().get(ep, '/api/link', token: 'abc');
      expect(r['home'], {'alive': true});
      expect(seen.single.headers.value(HttpHeaders.cookieHeader), 'ouispy_token=abc');
    });

    test('a 401 is a refusal', () async {
      await expectLater(
        HttpDashboardApi().get(ep, '/api/link', token: 'wrong'),
        throwsA(isA<DashboardError>().having((e) => e.fault, 'fault', DashboardFault.refused)),
      );
      await expectLater(
        HttpDashboardApi().get(ep, '/api/link'),
        throwsA(isA<DashboardError>().having((e) => e.fault, 'fault', DashboardFault.refused)),
      );
    });

    test('a rejected change carries the dashboard reason, and the body goes as JSON', () async {
      await expectLater(
        HttpDashboardApi().post(ep, '/api/settings', {'tak': {'enabled': true}}, token: 'abc'),
        throwsA(isA<DashboardError>()
            .having((e) => e.fault, 'fault', DashboardFault.rejected)
            .having((e) => e.message, 'message', 'a TAK server address is needed')),
      );
      expect(seen.single.method, 'POST');
      expect(seen.single.headers.contentType?.mimeType, 'application/json');
      expect(jsonDecode(bodies.single), {'tak': {'enabled': true}});
    });

    test('a page that is not JSON is not a dashboard', () async {
      await expectLater(
        HttpDashboardApi().get(ep, '/nothing'),
        throwsA(isA<DashboardError>().having((e) => e.fault, 'fault', DashboardFault.badReply)),
      );
    });

    test('a closed port is unreachable', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        HttpDashboardApi(timeout: const Duration(seconds: 2)).get(DashboardEndpoint('127.0.0.1', port), '/api/link'),
        throwsA(isA<DashboardError>().having((e) => e.fault, 'fault', DashboardFault.unreachable)),
      );
    });
  });
}
