import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart';

/// Manages WDGWars credentials, API calls, and per-session upload state.
class WdgwarsProvider extends ChangeNotifier {
  WdgwarsProvider(this._prefs) {
    _uploadedSessions.addAll(_prefs.getStringList(_keyUploaded) ?? const []);
    _showTerritories = _prefs.getBool(_keyTerritories) ?? false;
    _loadCredentials();
  }

  final SharedPreferences _prefs;
  static const _storage = FlutterSecureStorage();
  static const _keyApiKey = 'wdgwars_api_key';
  static const _keyUploaded = 'wdgwars_uploaded_sessions';
  static const _keyTerritories = 'wdgwars_show_territories';
  static const _territoryTtl = Duration(minutes: 5);

  WdgwarsApi? _api;
  String _apiKey = '';
  bool _isLoggedIn = false;
  bool _isLoading = false;
  WdgwarsUserStats? _stats;
  String? _error;
  final Set<String> _uploadedSessions = {};
  final Map<String, bool> _uploadingMap = {};
  final Map<String, WdgwarsUploadPhase> _phaseMap = {};

  List<WdgwarsTerritory> _territories = const [];
  DateTime? _territoriesAt;
  bool _territoriesLoading = false;
  bool _showTerritories = false;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  WdgwarsUserStats? get stats => _stats;
  String? get error => _error;

  List<WdgwarsTerritory> get territories => _territories;
  bool get territoriesLoading => _territoriesLoading;
  bool get showTerritories => _showTerritories && _isLoggedIn;

  Future<void> setShowTerritories(bool on) async {
    _showTerritories = on;
    await _prefs.setBool(_keyTerritories, on);
    notifyListeners();
    if (on) await loadTerritories();
  }

  /// Gang hulls for the wardrive map. Server snapshot refreshes every 5 min.
  Future<void> loadTerritories({bool force = false}) async {
    if (_api == null || _territoriesLoading) return;
    final at = _territoriesAt;
    if (!force && at != null && DateTime.now().difference(at) < _territoryTtl) {
      return;
    }
    _territoriesLoading = true;
    notifyListeners();
    try {
      _territories = await _api!.getTerritories();
      _territoriesAt = DateTime.now();
      DebugLog.log('WDGWARS: ${_territories.length} territories loaded');
    } catch (e) {
      DebugLog.log('WDGWARS: territory load failed: $e');
    }
    _territoriesLoading = false;
    notifyListeners();
  }

  bool isUploaded(String sessionId) => _uploadedSessions.contains(sessionId);
  bool isUploading(String sessionId) => _uploadingMap[sessionId] == true;
  bool isQueued(String sessionId) =>
      _phaseMap[sessionId] == WdgwarsUploadPhase.queued;

  Future<void> _loadCredentials() async {
    _apiKey = await _storage.read(key: _keyApiKey) ?? '';
    if (_apiKey.isNotEmpty) {
      _api = WdgwarsApi(apiKey: _apiKey);
      _isLoggedIn = true;
      notifyListeners();
      refreshStats();
      if (_showTerritories) loadTerritories();
    }
  }

  /// Validate and store a WDGWars API key.
  Future<bool> login(String apiKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final api = WdgwarsApi(apiKey: apiKey);
      final stats = await api.getUserStats();
      _api?.dispose();
      _api = api;
      _apiKey = apiKey;
      _stats = stats;
      _isLoggedIn = true;
      await _storage.write(key: _keyApiKey, value: apiKey);
      DebugLog.log('WDGWARS: linked as ${stats.username} (${stats.total} total)');
    } on WdgwarsApiException catch (e) {
      _error = e.message;
      _isLoggedIn = false;
      DebugLog.log('WDGWARS: login failed: $e');
    } catch (e) {
      _error = 'Connection failed: $e';
      _isLoggedIn = false;
      DebugLog.log('WDGWARS: login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return _isLoggedIn;
  }

  Future<void> logout() async {
    _api?.dispose();
    _api = null;
    _apiKey = '';
    _isLoggedIn = false;
    _stats = null;
    _territories = const [];
    _territoriesAt = null;
    await _storage.delete(key: _keyApiKey);
    notifyListeners();
    DebugLog.log('WDGWARS: unlinked');
  }

  Future<void> refreshStats() async {
    if (_api == null) return;
    try {
      _stats = await _api!.getUserStats();
      notifyListeners();
    } catch (e) {
      DebugLog.log('WDGWARS: stats refresh failed: $e');
    }
  }

  /// Upload a session CSV to WDGWars.
  Future<WdgwarsUploadResult?> uploadSession(
    String sessionId,
    WardriveController wd,
  ) async {
    if (_api == null || _uploadedSessions.contains(sessionId)) return null;

    _error = null;
    _uploadingMap[sessionId] = true;
    _phaseMap[sessionId] = WdgwarsUploadPhase.sending;
    notifyListeners();

    var sent = 0;
    var total = 0;
    try {
      final file = await wd.getCsvFile(sessionId);
      if (file == null) {
        _error = 'No CSV data for this session';
        _uploadingMap.remove(sessionId);
        _phaseMap.remove(sessionId);
        notifyListeners();
        return null;
      }

      final result = await _api!.uploadCsv(
        file,
        onProgress: (s, t) {
          sent = s;
          total = t;
        },
        onPhase: (phase) {
          _phaseMap[sessionId] = phase;
          notifyListeners();
        },
      );

      _error = null;
      _uploadedSessions.add(sessionId);
      _prefs.setStringList(_keyUploaded, _uploadedSessions.toList());
      refreshStats();

      DebugLog.log('WDGWARS: uploaded $sessionId ($total B) — ${result.summary}');
      _uploadingMap.remove(sessionId);
      _phaseMap.remove(sessionId);
      notifyListeners();
      return result;
    } on WdgwarsApiException catch (e) {
      _error = e.message;
      DebugLog.log('WDGWARS: upload failed at $sent/$total B: ${e.message}');
    } catch (e) {
      _error = e.toString();
      DebugLog.log('WDGWARS: upload error at $sent/$total B: '
          '${e.runtimeType} $e');
    }

    _uploadingMap.remove(sessionId);
    _phaseMap.remove(sessionId);
    notifyListeners();
    return null;
  }
}

final wdgwarsProvider = ChangeNotifierProvider<WdgwarsProvider>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return WdgwarsProvider(prefs);
});
