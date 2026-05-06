import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// WiGLE API v2 client.
/// Auth: Basic Auth with API Name (username) + API Token (password).
/// Docs: https://api.wigle.net
class WigleApi {
  WigleApi({required String apiName, required String apiToken})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.wigle.net/api/v2',
          headers: {
            'Authorization':
                'Basic ${base64Encode(utf8.encode('$apiName:$apiToken'))}',
          },
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  final Dio _dio;

  /// Verify credentials by fetching user stats.
  Future<WigleUserStats> getUserStats() async {
    final resp = await _dio.get('/stats/user');
    final data = resp.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw WigleApiException(data['message']?.toString() ?? 'Unknown error');
    }
    return WigleUserStats.fromJson(data);
  }

  /// Upload a WiGLE CSV file.
  Future<WigleUploadResult> uploadCsv(File csvFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        csvFile.path,
        filename: csvFile.uri.pathSegments.last,
        contentType: DioMediaType('text', 'csv'),
      ),
      'donate': 'on',
    });

    final resp = await _dio.post(
      '/file/upload',
      data: formData,
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw WigleApiException(data['message']?.toString() ?? 'Upload failed');
    }
    return WigleUploadResult.fromJson(data);
  }

  /// Get user's rank / standings.
  Future<WigleRanking> getRanking() async {
    final resp = await _dio.get('/stats/user');
    final data = resp.data as Map<String, dynamic>;
    if (data['success'] != true) {
      throw WigleApiException(data['message']?.toString() ?? 'Unknown error');
    }
    return WigleRanking.fromJson(data);
  }

  void dispose() {
    _dio.close();
  }
}

class WigleApiException implements Exception {
  WigleApiException(this.message);
  final String message;

  @override
  String toString() => 'WigleApiException: $message';
}

class WigleUserStats {
  WigleUserStats({
    required this.userName,
    required this.rank,
    required this.monthRank,
    required this.discoveredWiFi,
    required this.discoveredWiFiGps,
    required this.discoveredBt,
    required this.discoveredBtGps,
    required this.discoveredCell,
    required this.totalWiFi,
    required this.totalBt,
    required this.totalCell,
    required this.last,
    required this.first,
  });

  final String userName;
  final int rank;
  final int monthRank;
  final int discoveredWiFi;
  final int discoveredWiFiGps;
  final int discoveredBt;
  final int discoveredBtGps;
  final int discoveredCell;
  final int totalWiFi;
  final int totalBt;
  final int totalCell;
  final String last;
  final String first;

  int get totalDiscovered => discoveredWiFi + discoveredBt + discoveredCell;
  int get totalNetworks => totalWiFi + totalBt + totalCell;

  factory WigleUserStats.fromJson(Map<String, dynamic> json) {
    final stats = json['statistics'] as Map<String, dynamic>? ?? json;
    return WigleUserStats(
      userName: (json['user'] as String?) ?? (stats['userName'] as String?) ?? '',
      rank: (stats['rank'] as int?) ?? 0,
      monthRank: (stats['monthRank'] as int?) ?? 0,
      discoveredWiFi: (stats['discoveredWiFi'] as int?) ?? 0,
      discoveredWiFiGps: (stats['discoveredWiFiGPS'] as int?) ?? 0,
      discoveredBt: (stats['discoveredBt'] as int?) ?? 0,
      discoveredBtGps: (stats['discoveredBtGPS'] as int?) ?? 0,
      discoveredCell: (stats['discoveredCell'] as int?) ?? 0,
      totalWiFi: (stats['totalWiFiLocations'] as int?) ?? 0,
      totalBt: (stats['totalBtLocations'] as int?) ?? 0,
      totalCell: (stats['totalCellLocations'] as int?) ?? 0,
      last: (stats['last'] as String?) ?? '',
      first: (stats['first'] as String?) ?? '',
    );
  }
}

class WigleUploadResult {
  WigleUploadResult({
    required this.transactionId,
    required this.observer,
    required this.fileSize,
    required this.fileName,
    required this.totalGpsChunks,
    required this.totalGpsLocations,
    required this.totalNetworks,
    required this.totalNewNetworks,
    required this.percentDone,
  });

  final String transactionId;
  final String observer;
  final int fileSize;
  final String fileName;
  final int totalGpsChunks;
  final int totalGpsLocations;
  final int totalNetworks;
  final int totalNewNetworks;
  final double percentDone;

  factory WigleUploadResult.fromJson(Map<String, dynamic> json) {
    final results = json['results'] as Map<String, dynamic>? ?? json;
    return WigleUploadResult(
      transactionId: (results['transid'] as String?) ?? '',
      observer: (results['observer'] as String?) ?? '',
      fileSize: (results['filesize'] as int?) ?? 0,
      fileName: (results['filename'] as String?) ?? '',
      totalGpsChunks: (results['totalGpsChunks'] as int?) ?? 0,
      totalGpsLocations: (results['totalGpsLocations'] as int?) ?? 0,
      totalNetworks: (results['totalNetworks'] as int?) ?? 0,
      totalNewNetworks: (results['totalNewNetworks'] as int?) ?? 0,
      percentDone: ((results['percentDone'] as num?) ?? 0).toDouble(),
    );
  }
}

class WigleRanking {
  WigleRanking({
    required this.rank,
    required this.monthRank,
    required this.userName,
    required this.discoveredWiFi,
    required this.discoveredBt,
    required this.discoveredCell,
  });

  final int rank;
  final int monthRank;
  final String userName;
  final int discoveredWiFi;
  final int discoveredBt;
  final int discoveredCell;

  int get totalDiscovered => discoveredWiFi + discoveredBt + discoveredCell;

  factory WigleRanking.fromJson(Map<String, dynamic> json) {
    final stats = json['statistics'] as Map<String, dynamic>? ?? json;
    return WigleRanking(
      rank: (stats['rank'] as int?) ?? 0,
      monthRank: (stats['monthRank'] as int?) ?? 0,
      userName: (json['user'] as String?) ?? (stats['userName'] as String?) ?? '',
      discoveredWiFi: (stats['discoveredWiFi'] as int?) ?? 0,
      discoveredBt: (stats['discoveredBt'] as int?) ?? 0,
      discoveredCell: (stats['discoveredCell'] as int?) ?? 0,
    );
  }
}
