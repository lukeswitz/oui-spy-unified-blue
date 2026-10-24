import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart' show WdgwarsApiException;

class AdsbRecord {
  AdsbRecord({
    required this.icao,
    required this.lat,
    required this.lon,
    this.callsign = '',
    this.altFt = 0,
    this.speedKt = 0,
    this.heading = 0,
    DateTime? firstSeen,
  }) : firstSeen = (firstSeen ?? DateTime.now()).toUtc();

  final String icao;
  final String callsign;
  final double lat;
  final double lon;
  final int altFt;
  final int speedKt;
  final int heading;
  final DateTime firstSeen;

  bool get isValid =>
      RegExp(r'^[0-9A-F]{6}$').hasMatch(icao.toUpperCase().trim()) &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  Map<String, dynamic> toJson() => {
        'icao': icao.toUpperCase().trim(),
        'callsign': callsign.trim(),
        'lat': double.parse(lat.toStringAsFixed(6)),
        'lon': double.parse(lon.toStringAsFixed(6)),
        'alt_ft': altFt,
        'speed_kt': speedKt,
        'heading': heading,
        'first_seen': _fmt(firstSeen),
        'type': 'ADSB',
      };

  static String _fmt(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${p(t.month)}-${p(t.day)} '
        '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }
}

class WdgwarsAdsbResult {
  const WdgwarsAdsbResult({
    required this.sent,
    required this.imported,
    required this.alreadySeen,
  });
  final int sent;
  final int imported;
  final int alreadySeen;
}

class WdgwarsAdsbUploader {
  WdgwarsAdsbUploader({required String apiKey, Dio? dio})
      : _key = apiKey,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://wdgwars.pl',
              headers: {
                'X-API-Key': apiKey,
                HttpHeaders.userAgentHeader: 'oui-spy-companion/1.0',
                HttpHeaders.acceptHeader: 'application/json',
              },
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
              validateStatus: (s) => s != null && s < 500,
            ));

  static const endpoint = '/endpoint/upload/';
  static const batchSize = 1000;
  static const _maxAttempts = 3;
  static const _chunkCooldown = Duration(seconds: 1);

  final String _key;
  final Dio _dio;

  static const _counters = [
    'aircraft_imported',
    'aircraft_already_seen',
    'imported',
    'captured',
    'updated',
    'duplicates',
    'merged_samples',
    'already_seen',
    'no_gps',
    'bad_rows',
  ];
  static const _skipMarkers = ['already uploaded recently', 'no new processing'];

  Map<String, dynamic> buildEnvelope(List<AdsbRecord> chunk, {String? nonce}) {
    final payload = {
      'networks': <dynamic>[],
      'aircraft': chunk.map((r) => r.toJson()).toList(),
      'meshcore_nodes': <dynamic>[],
    };
    final dataB64 = base64.encode(utf8.encode(jsonEncode(payload)));
    final n = nonce ?? _nonce();
    final sig = Hmac(sha256, utf8.encode(_key))
        .convert(utf8.encode(n + dataB64))
        .toString();
    return {'data': dataB64, 'nonce': n, 'sig': sig};
  }

  static String _nonce() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<WdgwarsAdsbResult> upload(List<AdsbRecord> records) async {
    final valid = records.where((r) => r.isValid).toList();
    var sent = 0, imported = 0, seen = 0;
    for (var i = 0; i < valid.length; i += batchSize) {
      final chunk = valid.sublist(i, min(i + batchSize, valid.length));
      final data = await _sendChunk(chunk);
      sent += chunk.length;
      imported += _int(data['aircraft_imported'] ?? data['imported']);
      seen += _int(data['aircraft_already_seen'] ?? data['already_seen']);
      if (i + batchSize < valid.length) await Future.delayed(_chunkCooldown);
    }
    return WdgwarsAdsbResult(sent: sent, imported: imported, alreadySeen: seen);
  }

  Future<Map<String, dynamic>> _sendChunk(List<AdsbRecord> chunk) async {
    final body = jsonEncode(buildEnvelope(chunk));
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      Response<dynamic> resp;
      try {
        resp = await _dio.post(
          endpoint,
          data: body,
          options: Options(contentType: Headers.jsonContentType),
        );
      } on DioException catch (e) {
        if (attempt < _maxAttempts) {
          await Future.delayed(Duration(seconds: 2 * (1 << (attempt - 1))));
          continue;
        }
        throw WdgwarsApiException('Network error: ${e.message}');
      }
      final code = resp.statusCode ?? 0;
      final data = resp.data is Map<String, dynamic>
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      if (code == 200) {
        if (data['ok'] == false) {
          throw WdgwarsApiException(
              (data['error'] as String?) ?? 'Upload rejected');
        }
        if (_isSkip(data)) return data;
        if (data['ok'] == true && !_counters.any((k) => _truthy(data[k]))) {
          throw WdgwarsApiException(
              'Server returned ok but accepted nothing (silent drop)');
        }
        return data;
      }
      if (code == 429) {
        throw WdgwarsApiException(
            'Rate limited, retry in ${data['retry_after'] ?? 60}s');
      }
      if (code == 413) {
        throw WdgwarsApiException(
            'Payload too large (max ${data['max_bytes']}, got ${data['received']})');
      }
      throw WdgwarsApiException(
          'HTTP $code: ${data['error'] ?? data['message'] ?? ''}');
    }
    throw WdgwarsApiException('Upload failed');
  }

  static bool _isSkip(Map<String, dynamic> d) {
    for (final f in const ['info', 'message', 'note']) {
      final t = d[f];
      if (t is String &&
          _skipMarkers.any((m) => t.toLowerCase().contains(m))) {
        return true;
      }
    }
    return false;
  }

  static bool _truthy(dynamic v) =>
      v != null && v != 0 && v != false && v != '';

  static int _int(dynamic v) => v is num ? v.toInt() : 0;
}
