import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:drift/drift.dart' as drift;

/// Manages WiGLE credentials, API calls, and upload state.
class WigleProvider extends ChangeNotifier {
  WigleProvider(this._db) {
    _loadCredentials();
  }

  final AppDatabase _db;
  static const _storage = FlutterSecureStorage();
  static const _keyApiName = 'wigle_api_name';
  static const _keyApiToken = 'wigle_api_token';

  WigleApi? _api;
  String _apiName = '';
  String _apiToken = '';
  bool _isLoggedIn = false;
  bool _isLoading = false;
  WigleUserStats? _stats;
  String? _error;
  final Set<String> _uploadedSessions = {};
  final Map<String, bool> _uploadingMap = {};

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  WigleUserStats? get stats => _stats;
  String? get error => _error;
  String get apiName => _apiName;

  bool isUploaded(String sessionId) => _uploadedSessions.contains(sessionId);
  bool isUploading(String sessionId) => _uploadingMap[sessionId] == true;

  Future<void> _loadCredentials() async {
    _apiName = await _storage.read(key: _keyApiName) ?? '';
    _apiToken = await _storage.read(key: _keyApiToken) ?? '';
    if (_apiName.isNotEmpty && _apiToken.isNotEmpty) {
      _api = WigleApi(apiName: _apiName, apiToken: _apiToken);
      _isLoggedIn = true;
      notifyListeners();
      // Fetch stats in background
      refreshStats();
      _loadUploadHistory();
    }
  }

  Future<void> _loadUploadHistory() async {
    try {
      final uploads = await _db.getWigleUploads();
      for (final u in uploads) {
        if (u.sessionId != null) _uploadedSessions.add(u.sessionId!);
      }
      notifyListeners();
    } catch (e) {
      DebugLog.log('WIGLE: failed to load upload history: $e');
    }
  }

  /// Login with WiGLE API Name + Token.
  Future<bool> login(String apiName, String apiToken) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final api = WigleApi(apiName: apiName, apiToken: apiToken);
      final stats = await api.getUserStats();
      _api?.dispose();
      _api = api;
      _apiName = apiName;
      _apiToken = apiToken;
      _stats = stats;
      _isLoggedIn = true;

      await _storage.write(key: _keyApiName, value: apiName);
      await _storage.write(key: _keyApiToken, value: apiToken);

      _loadUploadHistory();

      DebugLog.log('WIGLE: logged in as ${stats.userName} (rank #${stats.rank})');
    } on WigleApiException catch (e) {
      _error = e.message;
      _isLoggedIn = false;
      DebugLog.log('WIGLE: login failed: $e');
    } catch (e) {
      _error = 'Connection failed: $e';
      _isLoggedIn = false;
      DebugLog.log('WIGLE: login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return _isLoggedIn;
  }

  Future<void> logout() async {
    _api?.dispose();
    _api = null;
    _apiName = '';
    _apiToken = '';
    _isLoggedIn = false;
    _stats = null;
    _uploadedSessions.clear();
    await _storage.delete(key: _keyApiName);
    await _storage.delete(key: _keyApiToken);
    notifyListeners();
    DebugLog.log('WIGLE: logged out');
  }

  Future<void> refreshStats() async {
    if (_api == null) return;
    try {
      _stats = await _api!.getUserStats();
      notifyListeners();
    } catch (e) {
      DebugLog.log('WIGLE: stats refresh failed: $e');
    }
  }

  /// Upload a session CSV to WiGLE.
  Future<WigleUploadResult?> uploadSession(
    String sessionId,
    WardriveController wd,
  ) async {
    if (_api == null || _uploadedSessions.contains(sessionId)) return null;

    _uploadingMap[sessionId] = true;
    notifyListeners();

    try {
      final file = await wd.getCsvFile(sessionId);
      if (file == null) {
        _error = 'No CSV data for this session';
        _uploadingMap.remove(sessionId);
        notifyListeners();
        return null;
      }

      final result = await _api!.uploadCsv(file);

      _uploadedSessions.add(sessionId);
      _db.insertWigleUpload(WigleUploadsCompanion(
        sessionId: drift.Value(sessionId),
        uploadedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
        transactionId: drift.Value(result.transactionId),
        networksAccepted: drift.Value(result.totalNetworks),
        networksNew: drift.Value(result.totalNewNetworks),
        status: const drift.Value('completed'),
      ));

      // Refresh stats after upload
      refreshStats();

      DebugLog.log('WIGLE: uploaded $sessionId — ${result.totalNetworks} networks, ${result.totalNewNetworks} new');
      _uploadingMap.remove(sessionId);
      notifyListeners();
      return result;
    } on WigleApiException catch (e) {
      _error = e.message;
      DebugLog.log('WIGLE: upload failed: $e');
    } catch (e) {
      _error = 'Upload failed: $e';
      DebugLog.log('WIGLE: upload error: $e');
    }

    _uploadingMap.remove(sessionId);
    notifyListeners();
    return null;
  }
}

final wigleProvider = ChangeNotifierProvider<WigleProvider>((ref) {
  final db = ref.watch(databaseProvider);
  return WigleProvider(db);
});
