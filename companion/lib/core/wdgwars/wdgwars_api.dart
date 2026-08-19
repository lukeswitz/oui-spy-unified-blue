import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart' show Color;
import 'package:latlong2/latlong.dart';

enum WdgwarsUploadPhase { sending, queued }

class WdgwarsApi {
  WdgwarsApi({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://wdgwars.pl',
          headers: {
            'X-API-Key': apiKey,
            HttpHeaders.userAgentHeader: 'oui-spy-companion/1.0',
          },
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ));

  final Dio _dio;

  /// Validate the API key and fetch the account's stats (GET /api/me).
  Future<WdgwarsUserStats> getUserStats() async {
    final resp = await _dio.get('/api/me');
    final data = _asMap(resp.data);
    if (resp.statusCode == 401 || data['ok'] == false) {
      throw WdgwarsApiException(
          (data['error'] as String?) ?? 'Invalid API key');
    }
    if (resp.statusCode != 200) {
      throw WdgwarsApiException('HTTP ${resp.statusCode}');
    }
    return WdgwarsUserStats.fromJson(data);
  }

  /// Gang territory hulls for the wardrive map (GET /api/territories).
  Future<List<WdgwarsTerritory>> getTerritories() async {
    final resp = await _dio.get<String>(
      '/api/territories',
      options: Options(
        followRedirects: false,
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final code = resp.statusCode ?? 0;
    if (code >= 300 && code < 400) {
      throw WdgwarsApiException(
          'Territories redirected to ${resp.headers.value('location') ?? 'login'} '
          '(HTTP $code)');
    }
    final body = resp.data;
    if (code != 200) {
      throw WdgwarsApiException('Territories unavailable (HTTP $code)');
    }
    if (body == null || body.isEmpty) {
      throw WdgwarsApiException('Territories returned an empty body');
    }
    return compute(_parseTerritories, body);
  }

  /// Upload a CSV via the documented async endpoint (POST /api/v2/upload-csv),
  /// gzipped — the API accepts .gz and it cuts a wardrive CSV ~20x.
  Future<WdgwarsUploadResult> uploadCsv(
    File csvFile, {
    void Function(int sent, int total)? onProgress,
    void Function(WdgwarsUploadPhase phase)? onPhase,
  }) async {
    final raw = await csvFile.readAsBytes();
    if (raw.isEmpty) throw WdgwarsApiException('CSV is empty — nothing to upload');
    final csv = Uint8List.fromList(GZipCodec(level: 9).encode(raw));

    const retryDelays = [Duration(seconds: 2), Duration(seconds: 8)];
    Response<dynamic>? resp;
    Object? lastTransportError;
    final attemptLog = <String>[];

    for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
      try {
        resp = await _postCsv(
            '${csvFile.uri.pathSegments.last}.gz', csv, onProgress);
        break;
      } on DioException catch (e) {
        if (!_isTransient(e)) throw WdgwarsApiException(_dioMessage(e));
        lastTransportError = e.error ?? e;
        attemptLog.add('#${attempt + 1} ${e.type.name}/'
            '${(e.error ?? e).runtimeType}: ${e.error ?? e.message}');
        if (attempt == retryDelays.length) break;
        _resetConnection();
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
    if (resp == null) {
      throw WdgwarsApiException(
          '${_transportMessage(lastTransportError)} [${attemptLog.join(' | ')}]');
    }

    final code = resp.statusCode ?? 0;
    final data = _asMap(resp.data);
    if (code == 401) {
      throw WdgwarsApiException(
          (data['error'] as String?) ?? 'Invalid API key');
    }
    if (code == 413) {
      throw WdgwarsApiException('File too large — split the session');
    }
    if (code == 429) {
      final retry = resp.headers.value('retry-after');
      final wait = retry != null ? ' — retry in ${retry}s' : ' — try again shortly';
      throw WdgwarsApiException('Rate limited (30/min)$wait');
    }
    if (code == 202 || (code >= 200 && code < 300 && data['ok'] != false)) {
      final jobId = data['job_id']?.toString();
      if (jobId != null && jobId.isNotEmpty) {
        onPhase?.call(WdgwarsUploadPhase.queued);
        return _awaitJob(jobId, data);
      }
      return WdgwarsUploadResult.fromJson(data);
    }
    throw WdgwarsApiException(
        (data['error'] as String?) ?? 'Upload failed (HTTP $code)');
  }

  /// Poll `/api/v2/upload-job/{id}` until terminal; falls back to the queued
  /// receipt if the parser is still busy when we give up waiting.
  Future<WdgwarsUploadResult> _awaitJob(
      String jobId, Map<String, dynamic> queued) async {
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    var delay = const Duration(seconds: 2);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(delay);
      if (delay < const Duration(seconds: 6)) delay += const Duration(seconds: 1);
      Map<String, dynamic> job;
      try {
        final r = await _dio.get('/api/v2/upload-job/$jobId');
        job = _asMap(r.data);
      } on DioException {
        continue;
      }
      switch (job['status']) {
        case 'done':
          return WdgwarsUploadResult.fromJson(
              {..._asMap(job['result']), 'job_id': jobId});
        case 'failed':
          throw WdgwarsApiException(
              (job['error'] as String?) ?? 'WDGWars rejected the file');
      }
    }
    return WdgwarsUploadResult.fromJson(queued);
  }

  Future<Response<dynamic>> _postCsv(
    String filename,
    Uint8List csv,
    void Function(int sent, int total)? onProgress,
  ) {
    final boundary =
        '----ouispy${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final head = utf8.encode('--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
        'Content-Type: application/gzip\r\n\r\n');
    final tail = utf8.encode('\r\n--$boundary--\r\n');

    final body = Uint8List(head.length + csv.length + tail.length);
    body.setRange(0, head.length, head);
    body.setRange(head.length, head.length + csv.length, csv);
    body.setRange(head.length + csv.length, body.length, tail);

    return _dio.post(
      '/api/v2/upload-csv',
      data: Stream.value(body),
      onSendProgress: onProgress,
      options: Options(
        headers: {
          Headers.contentTypeHeader:
              'multipart/form-data; boundary=$boundary',
          Headers.contentLengthHeader: body.length,
        },
        sendTimeout: _sendTimeoutFor(body.length),
        receiveTimeout: const Duration(seconds: 180),
      ),
    );
  }

  /// dio applies sendTimeout to the whole body transfer, not per-chunk, so it
  /// has to scale with size: 60s of headroom + 12s per MB (~700 kbit/s floor).
  static Duration _sendTimeoutFor(int bytes) {
    final mb = bytes / (1024 * 1024);
    final secs = 60 + (mb * 12).ceil();
    return Duration(seconds: secs.clamp(60, 900));
  }

  /// Reference client treats 400/401/403/413/415 as final, everything else retryable.
  static bool _isTransient(DioException e) {
    final code = e.response?.statusCode;
    if (code != null) {
      return !(code == 400 || code == 401 || code == 403 ||
          code == 413 || code == 415);
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    final inner = e.error;
    return inner is TlsException ||
        inner is HandshakeException ||
        inner is SocketException ||
        inner is HttpException;
  }

  static String _dioMessage(DioException e) {
    final data = _asMap(e.response?.data);
    final serverMsg = data['error'] as String?;
    if (serverMsg != null && serverMsg.isNotEmpty) return serverMsg;
    final code = e.response?.statusCode;
    if (code != null) return 'Server rejected the upload (HTTP $code)';
    return e.message ?? 'Upload failed (${e.type.name})';
  }

  static String _transportMessage(Object? err) =>
      'Upload aborted: ${err ?? 'connection closed by server'}';

  void _resetConnection() {
    _dio.httpClientAdapter.close(force: true);
    _dio.httpClientAdapter = IOHttpClientAdapter();
  }

  static Map<String, dynamic> _asMap(dynamic raw) =>
      raw is Map<String, dynamic> ? raw : <String, dynamic>{};

  void dispose() => _dio.close();
}

/// One gang's claimed area — convex hull of its captures.
List<WdgwarsTerritory> _parseTerritories(String body) {
  final raw = jsonDecode(body);
  if (raw is! List) {
    throw WdgwarsApiException(
        'Territories returned ${raw.runtimeType}, expected a list');
  }
  return raw
      .whereType<Map>()
      .map((e) => WdgwarsTerritory.fromJson(e.cast<String, dynamic>()))
      .where((t) => t.hull.length >= 3)
      .toList();
}

class WdgwarsTerritory {
  const WdgwarsTerritory({
    required this.gangId,
    required this.name,
    required this.color,
    required this.members,
    required this.points,
    required this.rank,
    required this.hull,
  });

  final int gangId;
  final String name;
  final Color color;
  final int members;
  final int points;
  final int rank;
  final List<LatLng> hull;

  ({double minLat, double maxLat, double minLon, double maxLon}) get bounds {
    var minLat = hull.first.latitude, maxLat = minLat;
    var minLon = hull.first.longitude, maxLon = minLon;
    for (final p in hull) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
  }

  factory WdgwarsTerritory.fromJson(Map<String, dynamic> json) {
    final hull = <LatLng>[];
    final raw = json['hull'];
    if (raw is List) {
      for (final p in raw) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          hull.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
    }
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    return WdgwarsTerritory(
      gangId: asInt(json['gang_id']),
      name: (json['name'] as String?) ?? '',
      color: _parseHexColor(json['color'] as String?),
      members: asInt(json['members']),
      points: asInt(json['points']),
      rank: asInt(json['rank']),
      hull: hull,
    );
  }

  static Color _parseHexColor(String? hex) {
    if (hex == null) return const Color(0xFF8B5CF6);
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return const Color(0xFF8B5CF6);
    return Color(h.length <= 6 ? (0xFF000000 | v) : v);
  }
}

class WdgwarsApiException implements Exception {
  WdgwarsApiException(this.message);
  final String message;

  @override
  String toString() => 'WdgwarsApiException: $message';
}

class WdgwarsUserStats {
  WdgwarsUserStats({
    required this.username,
    required this.wifi,
    required this.ble,
    required this.aircraft,
    required this.mesh,
    required this.total,
    required this.badges,
    required this.gang,
    required this.rank,
    required this.dailyUsed,
    required this.dailyRemaining,
    required this.dailyCap,
    this.gangRole = '',
    this.country = '',
    this.joined = '',
    this.recentToday = 0,
    this.recent7d = 0,
    this.reinforced = 0,
    this.notes = 0,
    this.cracked = 0,
    this.credits = 0,
    this.creditsLifetime = 0,
    this.bountiesCompleted = 0,
  });

  final String username;
  final int wifi;
  final int ble;
  final int aircraft;
  final int mesh;
  final int total;
  final List<String> badges;
  final String gang;

  /// All-time leaderboard rank; null when unranked.
  final int? rank;

  /// 24h-rolling new-AP quota (server-enforced 500k/day cap).
  final int dailyUsed;
  final int dailyRemaining;
  final int dailyCap;

  final String gangRole;
  final String country;
  final String joined;
  final int recentToday;
  final int recent7d;
  final int reinforced;
  final int notes;
  final int cracked;
  final int credits;
  final int creditsLifetime;
  final int bountiesCompleted;

  factory WdgwarsUserStats.fromJson(Map<String, dynamic> json) {
    final rankMap = json['your_rank'];
    final limitMap = json['new_ap_limit'];
    final creditMap = json['credits'];
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    int credit(String k) =>
        creditMap is Map ? (asInt(creditMap[k]) ?? 0) : 0;
    return WdgwarsUserStats(
      username: (json['username'] as String?) ?? '',
      wifi: asInt(json['wifi']) ?? 0,
      ble: asInt(json['ble']) ?? 0,
      aircraft: asInt(json['aircraft']) ?? 0,
      mesh: asInt(json['mesh']) ?? 0,
      total: asInt(json['total']) ?? 0,
      badges: (json['badges'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      gang: (json['gang'] as String?) ?? '',
      rank: rankMap is Map ? asInt(rankMap['all_time']) : null,
      dailyUsed: limitMap is Map ? (asInt(limitMap['used']) ?? 0) : 0,
      dailyRemaining: limitMap is Map ? (asInt(limitMap['remaining']) ?? 0) : 0,
      dailyCap: limitMap is Map ? (asInt(limitMap['cap']) ?? 0) : 0,
      gangRole: (json['gang_role'] as String?) ?? '',
      country: (json['country'] as String?) ?? '',
      joined: (json['joined'] as String?) ?? '',
      recentToday: asInt(json['recent_today']) ?? 0,
      recent7d: asInt(json['recent_7d']) ?? 0,
      reinforced: asInt(json['reinforce_total']) ?? 0,
      notes: asInt(json['notes']) ?? 0,
      cracked: asInt(json['cracked']) ?? 0,
      credits: credit('balance'),
      creditsLifetime: credit('lifetime_earned'),
      bountiesCompleted: credit('bounties_completed'),
    );
  }
}

class WdgwarsUploadResult {
  WdgwarsUploadResult({
    required this.accepted,
    required this.newNetworks,
    required this.mergedSamples,
    required this.async,
    required this.jobId,
  });

  final int? accepted;
  final int? newNetworks;
  final int? mergedSamples;
  final bool async;
  final String? jobId;

  String get summary {
    final parts = <String>[];
    if (accepted != null) parts.add('$accepted imported');
    if (newNetworks != null && newNetworks! > 0) parts.add('$newNetworks new');
    if (mergedSamples != null && mergedSamples! > 0) {
      parts.add('$mergedSamples merged');
    }
    if (parts.isEmpty) {
      return async ? 'Queued for WDGWars processing' : 'Uploaded to WDGWars';
    }
    return parts.join(' · ');
  }

  factory WdgwarsUploadResult.fromJson(Map<String, dynamic> json) {
    int? pick(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v.toInt();
      }
      return null;
    }

    final jobId = json['job_id']?.toString();
    final imported = pick(['imported', 'accepted', 'networks', 'total', 'count']);
    return WdgwarsUploadResult(
      accepted: imported,
      newNetworks: pick(['captured', 'new', 'new_networks', 'newNetworks']),
      mergedSamples: pick(['merged_samples', 'merged', 'mergedSamples']),
      async: imported == null && jobId != null && jobId.isNotEmpty,
      jobId: jobId,
    );
  }
}
