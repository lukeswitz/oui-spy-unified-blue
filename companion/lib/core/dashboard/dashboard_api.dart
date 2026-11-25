// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Where the home dashboard (tools/home-dashboard) listens.
class DashboardEndpoint {
  const DashboardEndpoint(this.host, [this.port = defaultPort]);

  static const defaultPort = 5077;

  final String host;
  final int port;

  /// Accepts `host`, `host:port`, `[::1]:port` and `http://host:port/`; null when it is not an address.
  static DashboardEndpoint? parse(String text) {
    var s = text.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'/.*$'), '');
    if (s.isEmpty) return null;
    String host;
    String? portText;
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end < 0) return null;
      host = s.substring(1, end);
      final rest = s.substring(end + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) return null;
        portText = rest.substring(1);
      }
    } else {
      final i = s.lastIndexOf(':');
      if (i >= 0 && s.indexOf(':') == i) {
        host = s.substring(0, i);
        portText = s.substring(i + 1);
      } else {
        host = s;
      }
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(host)) return null;
    final port = portText == null ? defaultPort : int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) return null;
    return DashboardEndpoint(host, port);
  }

  String get label => host.contains(':') ? '[$host]:$port' : '$host:$port';

  @override
  bool operator ==(Object other) => other is DashboardEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

enum DashboardFault { refused, unreachable, badReply, rejected }

class DashboardError implements Exception {
  const DashboardError(this.fault, this.message);

  final DashboardFault fault;
  final String message;

  @override
  String toString() => message;
}

abstract class DashboardApi {
  Future<Map<String, dynamic>> get(DashboardEndpoint e, String path, {String? token});

  Future<Map<String, dynamic>> post(DashboardEndpoint e, String path, Map<String, dynamic> body, {String? token});
}

/// Talks to the dashboard over plain HTTP. The access token, when there is one, goes in the cookie the
/// dashboard sets for browsers (`ouispy_token`).
class HttpDashboardApi implements DashboardApi {
  HttpDashboardApi({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  @override
  Future<Map<String, dynamic>> get(DashboardEndpoint e, String path, {String? token}) =>
      _send('GET', e, path, null, token);

  @override
  Future<Map<String, dynamic>> post(DashboardEndpoint e, String path, Map<String, dynamic> body, {String? token}) =>
      _send('POST', e, path, body, token);

  Future<Map<String, dynamic>> _send(
      String method, DashboardEndpoint e, String path, Map<String, dynamic>? body, String? token) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, Uri(scheme: 'http', host: e.host, port: e.port, path: path));
      req.headers.set(HttpHeaders.userAgentHeader, 'OUI-APEX-app');
      if (token != null && token.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, 'ouispy_token=$token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const DashboardError(DashboardFault.refused, 'the dashboard wants the access token');
      }
      Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
      final map = json is Map<String, dynamic> ? json : null;
      if (res.statusCode >= 400 || (map != null && map['ok'] == false)) {
        final why = map?['error'];
        throw DashboardError(DashboardFault.rejected, why is String ? why : 'HTTP ${res.statusCode} on $path');
      }
      if (map == null) throw DashboardError(DashboardFault.badReply, 'not an OUI-APEX dashboard (no JSON on $path)');
      return map;
    } on DashboardError {
      rethrow;
    } on TimeoutException {
      throw DashboardError(DashboardFault.unreachable, 'no reply from ${e.label}');
    } on SocketException catch (x) {
      throw DashboardError(DashboardFault.unreachable, 'could not reach ${e.label}: ${x.message}');
    } on HttpException catch (x) {
      throw DashboardError(DashboardFault.unreachable, 'could not reach ${e.label}: ${x.message}');
    } finally {
      client.close(force: true);
    }
  }
}
