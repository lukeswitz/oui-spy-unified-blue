import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

/// Provides manufacturer name lookup from MAC address OUI prefix.
/// Loads 39k+ unique OUIs from bundled asset (gzipped TSV).
/// Supports runtime updates from Ringmast4r GitHub repo.
final ouiLookupProvider = Provider<OuiLookupService>((ref) {
  return OuiLookupService();
});

class OuiLookupService {
  static const _assetPath = 'assets/oui_vendors.tsv.gz';
  static const _updateUrl =
      'https://raw.githubusercontent.com/Ringmast4r/OUI-Master-Database/master/LISTS/master_oui.txt';
  static const _localFileName = 'oui_vendors.tsv';

  /// Known device overrides — these OUIs are registered to chip vendors
  /// (Silicon Labs, Liteon, UGS, Espressif) but are actually used by
  /// specific surveillance hardware. Matches flock_oui.h in firmware.
  static const Map<String, String> _overrides = {
    // Flock Safety — FS Ext Battery (BLE, Silicon Labs EFR32)
    '588E81': 'Flock Safety (Battery)',
    'CCCCCC': 'Flock Safety (Battery)',
    'EC1BBD': 'Flock Safety (Battery)',
    '9035EA': 'Flock Safety (Battery)',
    '040D84': 'Flock Safety (Battery)',
    'F082C0': 'Flock Safety (Battery)',
    '1C34F1': 'Flock Safety (Battery)',
    '385B44': 'Flock Safety (Battery)',
    '943469': 'Flock Safety (Battery)',
    'B4E3F9': 'Flock Safety (Battery)',
    // Flock Safety — WiFi cameras (Liteon/UGS modules)
    '70C94E': 'Flock Safety (Falcon)',
    '3C9180': 'Flock Safety (Falcon)',
    'D8F3BC': 'Flock Safety (Falcon)',
    '803049': 'Flock Safety (Falcon)',
    '145AFC': 'Flock Safety (Falcon)',
    '744CA1': 'Flock Safety (Falcon)',
    '083A88': 'Flock Safety (Falcon)',
    '9C2F9D': 'Flock Safety (Falcon)',
    '940853': 'Flock Safety (Falcon)',
    'E4AAEA': 'Flock Safety (Falcon)',
    // Flock Safety — official IEEE registration
    'B41E52': 'Flock Safety',
    // Flock Safety — Raven gunshot detector (Espressif)
    'EC6260': 'Flock Safety (Raven)',
  };

  final Map<String, String> _db = {};
  bool _loaded = false;
  DateTime? _lastUpdated;

  bool get isLoaded => _loaded;
  int get entryCount => _db.length;
  DateTime? get lastUpdated => _lastUpdated;

  /// Initialize from local cache or bundled asset.
  Future<void> init() async {
    if (_loaded) return;

    // Try local (updated) file first
    final localFile = await _localFile;
    if (localFile.existsSync()) {
      final content = await localFile.readAsString();
      _parseRaw(content);
      _lastUpdated = localFile.lastModifiedSync();
    } else {
      // Fall back to bundled asset
      final compressed = await rootBundle.load(_assetPath);
      final bytes = compressed.buffer.asUint8List();
      final decompressed = gzip.decode(bytes);
      final content = utf8.decode(decompressed);
      _parseRaw(content);
    }

    // Apply overrides so known devices always show correct name
    _db.addAll(_overrides);
    _loaded = true;
  }

  /// Look up manufacturer by MAC address string.
  /// Accepts formats: "AA:BB:CC:DD:EE:FF", "AA-BB-CC-DD-EE-FF", "AABBCCDDEEFF"
  /// Checks hardcoded overrides first (Flock Safety devices use OEM chip
  /// vendor OUIs that would otherwise show as Silicon Labs / Liteon / etc).
  String? lookup(String macAddress) {
    final prefix = _extractPrefix(macAddress);
    if (prefix == null) return null;
    // Overrides always work, even before DB loads
    final override = _overrides[prefix];
    if (override != null) return override;
    if (!_loaded) return null;
    return _db[prefix];
  }

  /// Check if an OUI DB update is available and download it.
  /// Returns true if database was updated.
  Future<bool> checkForUpdate() async {
    try {
      final dio = Dio();
      final response = await dio.get<String>(
        _updateUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data!;
        final lines = content.split('\n');
        // Validate it looks like valid OUI data
        if (lines.length < 1000) return false;

        // Parse raw master_oui.txt format (with comments, dupes)
        final newDb = <String, String>{};
        for (final line in lines) {
          if (line.startsWith('#') || !line.contains('\t')) continue;
          final parts = line.split('\t');
          if (parts.length >= 2) {
            final prefix = parts[0].trim().toUpperCase();
            if (prefix.length == 6 && !newDb.containsKey(prefix)) {
              newDb[prefix] = parts[1].trim();
            }
          }
        }

        if (newDb.length < 30000) return false; // sanity check

        // Write deduplicated TSV locally
        final localFile = await _localFile;
        final buffer = StringBuffer();
        for (final entry in newDb.entries) {
          buffer.write(entry.key);
          buffer.write('\t');
          buffer.writeln(entry.value);
        }
        await localFile.writeAsString(buffer.toString());

        // Reload with overrides applied on top
        _db.clear();
        _db.addAll(newDb);
        _db.addAll(_overrides);
        _lastUpdated = DateTime.now();
        return true;
      }
    } catch (_) {
      // Network error — keep using existing data
    }
    return false;
  }

  void _parseRaw(String content) {
    _db.clear();
    for (final line in content.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final tabIdx = line.indexOf('\t');
      if (tabIdx == -1) continue;
      final prefix = line.substring(0, tabIdx).trim().toUpperCase();
      if (prefix.length == 6) {
        _db.putIfAbsent(prefix, () => line.substring(tabIdx + 1).trim());
      }
    }
  }

  /// Extract 6-char hex prefix from MAC string.
  String? _extractPrefix(String mac) {
    // Strip separators
    final clean = mac.replaceAll(RegExp(r'[:\-.]'), '').toUpperCase();
    if (clean.length < 6) return null;
    return clean.substring(0, 6);
  }

  Future<File> get _localFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_localFileName');
  }
}
