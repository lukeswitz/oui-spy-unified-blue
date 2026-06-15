import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FaaRegistration {
  const FaaRegistration({
    required this.status,
    required this.brand,
    required this.model,
    required this.manufacturerCode,
    required this.productType,
    required this.operationRules,
    required this.makeName,
    required this.modelName,
    required this.series,
    required this.trackingNumber,
    required this.complianceCategories,
    required this.updatedAt,
    required this.cachedAt,
  });

  final String status;
  final String brand;
  final String model;
  final String manufacturerCode;
  final String productType;
  final String operationRules;
  final String makeName;
  final String modelName;
  final String series;
  final String trackingNumber;
  final String complianceCategories;
  final String updatedAt;
  final DateTime cachedAt;

  factory FaaRegistration.fromItemsShape(Map<String, dynamic> item) =>
      FaaRegistration(
        status: (item['status'] as String?) ?? '',
        brand: (item['brand'] as String?) ?? '',
        model: (item['model'] as String?) ?? '',
        manufacturerCode: (item['manufacturerCode'] as String?) ?? '',
        productType: (item['productType'] as String?) ?? '',
        operationRules: (item['operationRules'] as String?) ?? '',
        makeName: (item['makeName'] as String?) ?? '',
        modelName: (item['modelName'] as String?) ?? '',
        series: (item['series'] as String?) ?? '',
        trackingNumber: (item['trackingNumber'] as String?) ?? '',
        complianceCategories:
            (item['complianceCategories'] as String?) ?? '',
        updatedAt: (item['updatedAt'] as String?) ?? '',
        cachedAt: DateTime.now(),
      );

  factory FaaRegistration.fromJson(Map<String, dynamic> json) =>
      FaaRegistration(
        status: (json['status'] as String?) ?? '',
        brand: (json['brand'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        manufacturerCode: (json['manufacturerCode'] as String?) ?? '',
        productType: (json['productType'] as String?) ?? '',
        operationRules: (json['operationRules'] as String?) ?? '',
        makeName: (json['makeName'] as String?) ?? '',
        modelName: (json['modelName'] as String?) ?? '',
        series: (json['series'] as String?) ?? '',
        trackingNumber: (json['trackingNumber'] as String?) ?? '',
        complianceCategories:
            (json['complianceCategories'] as String?) ?? '',
        updatedAt: (json['updatedAt'] as String?) ?? '',
        cachedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['_cachedAt'] as int?) ?? 0),
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        'brand': brand,
        'model': model,
        'manufacturerCode': manufacturerCode,
        'productType': productType,
        'operationRules': operationRules,
        'makeName': makeName,
        'modelName': modelName,
        'series': series,
        'trackingNumber': trackingNumber,
        'complianceCategories': complianceCategories,
        'updatedAt': updatedAt,
        '_cachedAt': cachedAt.millisecondsSinceEpoch,
      };

  String get displayName {
    if (brand.isNotEmpty && model.isNotEmpty) return '$brand $model';
    if (makeName.isNotEmpty && modelName.isNotEmpty) return '$makeName $modelName';
    if (brand.isNotEmpty) return brand;
    if (makeName.isNotEmpty) return makeName;
    return '';
  }
}

class FaaLookupException implements Exception {
  FaaLookupException(this.message);
  final String message;
  @override
  String toString() => 'FaaLookupException: $message';
}

class FaaService extends ChangeNotifier {
  static const _baseUrl = 'https://uasdoc.faa.gov';
  static const _homepagePath = '/listdocs';
  static const _apiPath = '/api/v1/serialNumbers';
  static const _cacheKeyPrefix = 'faa_cache_';
  static const _maxRetries = 3;

  late final Dio _dio;

  FaaService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.5',
        'Referer': '$_baseUrl$_homepagePath',
        'client': 'external',
      },
    ));
  }

  Future<void> _refreshCookie() async {
    try {
      await _dio.get<dynamic>(_homepagePath);
    } on DioException catch (e) {
      DebugLog.log('FAA: cookie refresh failed (${e.response?.statusCode}): ${e.message}');
    }
  }

  Future<FaaRegistration?> lookup(String uasId) async {
    if (uasId.isEmpty) return null;

    final cached = await _fromCache(uasId);
    if (cached != null) return cached;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _refreshCookie();
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final resp = await _dio.get<Map<String, dynamic>>(
          _apiPath,
          queryParameters: {
            'itemsPerPage': '8',
            'pageIndex': '0',
            'orderBy[0]': 'updatedAt',
            'orderBy[1]': 'DESC',
            'findBy': 'serialNumber',
            'serialNumber': uasId,
          },
        );

        final body = resp.data;
        if (body == null) return null;

        final reg = _parseResponse(body);
        if (reg != null) await _toCache(uasId, reg);
        return reg;
      } on DioException catch (e) {
        final code = e.response?.statusCode ?? 0;
        if (code == 502 && attempt < _maxRetries - 1) {
          DebugLog.log('FAA: 502, retry ${attempt + 1}/$_maxRetries');
          await Future<void>.delayed(
              Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        throw FaaLookupException(
            e.response?.statusMessage ?? e.message ?? 'Network error');
      }
    }
    return null;
  }

  FaaRegistration? _parseResponse(Map<String, dynamic> body) {
    final topItems = body['items'];
    if (topItems is List && topItems.isNotEmpty) {
      return FaaRegistration.fromItemsShape(
          topItems.first as Map<String, dynamic>);
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      final dataItems = data['items'];
      if (dataItems is List && dataItems.isNotEmpty) {
        return FaaRegistration.fromItemsShape(
            dataItems.first as Map<String, dynamic>);
      }
    }
    return null;
  }

  Future<FaaRegistration?> _fromCache(String uasId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cacheKeyPrefix$uasId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return FaaRegistration.fromJson(json);
    } on FormatException catch (e) {
      DebugLog.log('FAA: corrupt cache for $uasId: $e');
      await prefs.remove('$_cacheKeyPrefix$uasId');
      return null;
    }
  }

  Future<void> _toCache(String uasId, FaaRegistration reg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        '$_cacheKeyPrefix$uasId', jsonEncode(reg.toJson()));
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith(_cacheKeyPrefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }
}

final faaServiceProvider = ChangeNotifierProvider<FaaService>((ref) {
  return FaaService();
});
