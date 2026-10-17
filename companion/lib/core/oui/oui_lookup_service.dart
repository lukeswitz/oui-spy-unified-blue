import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

final ouiLookupProvider = ChangeNotifierProvider<OuiLookupService>((ref) {
  return OuiLookupService();
});

class OuiLookupService extends ChangeNotifier {
  static const _assetPath = 'assets/oui_vendors.tsv.gz';
  static const _updateUrl = 'https://www.wireshark.org/download/automated/data/manuf.gz';
  static const _localFileName = 'oui_vendors_manuf.tsv';
  static const _legacyLocalFileName = 'oui_vendors.tsv';

  static const Map<String, String> _overrides = {
    // Flock Safety — FS Ext Battery (BLE, Silicon Labs EFR32)
    '588E81': 'Flock Safety (Battery)',
    'EC1BBD': 'Flock Safety (Battery)',
    '9035EA': 'Flock Safety (Battery)',
    '040D84': 'Flock Safety (Battery)',
    'F082C0': 'Flock Safety (Battery)',
    '1C34F1': 'Flock Safety (Battery)',
    '385B44': 'Flock Safety (Battery)',
    '943469': 'Flock Safety (Battery)',
    'B4E3F9': 'Flock Safety (Battery)',
    // @NitekryDPaul / OrdoOuroborous — original promiscuous-mode set
    '70C94E': 'Flock Safety (Falcon)',
    '3C9180': 'Flock Safety (Falcon)',
    'D8F3BC': 'Flock Safety (Falcon)',
    '803049': 'Flock Safety (Falcon)',
    'B83532': 'Flock Safety (Falcon)',
    '145AFC': 'Flock Safety (Falcon)',
    '744CA1': 'Flock Safety (Falcon)',
    '083A88': 'Flock Safety (Falcon)',
    '9C2F9D': 'Flock Safety (Falcon)',
    'C03532': 'Flock Safety (Falcon)',
    '940853': 'Flock Safety (Falcon)',
    'E4AAEA': 'Flock Safety (Falcon)',
    'F46ADD': 'Flock Safety (Falcon)',
    '24B2B9': 'Flock Safety (Falcon)',
    '00F48D': 'Flock Safety (Falcon)',
    'D03957': 'Flock Safety (Falcon)',
    'E8D0FC': 'Flock Safety (Falcon)',
    'E04F43': 'Flock Safety (Falcon)',
    'B81EA4': 'Flock Safety (Falcon)',
    '700894': 'Flock Safety (Falcon)',
    '3C71BF': 'Flock Safety (Falcon)',
    '5800E3': 'Flock Safety (Falcon)',
    '5C93A2': 'Flock Safety (Falcon)',
    '646E69': 'Flock Safety (Falcon)',
    '4827EA': 'Flock Safety (Falcon)',
    'A4CF12': 'Flock Safety (Falcon)',
    // @NitekryDPaul April 2026 additions
    'B41E52': 'Flock Safety',
    '14B5CD': 'Flock Safety (Falcon)',
    'D411D6': 'Flock Safety (Falcon)',
    'E00AF6': 'Flock Safety (Falcon)',
    // DeFlockJoplin — wildcard-probe field research
    '826BF2': 'Flock Safety (Falcon)',
    // Flock Safety BLE — @NitekryDPaul Jul 2026 LE CSV
    '00408C': 'Flock Safety',
    'ACCC8E': 'Flock Safety',
    // Flock Safety — Raven gunshot detector (Espressif)
    'EC6260': 'Flock Safety (Raven)',
  };

  static const Map<String, String> lawEnforcementOuis = {
    '0025DF': 'Axon (Law Enforcement)',
  };

  final Map<String, String> _db = {};
  bool _loaded = false;
  DateTime? _lastUpdated;

  static String? _prefixOf(String mac) {
    final clean = mac.replaceAll(RegExp(r'[:\-.]'), '').toUpperCase();
    if (clean.length < 6) return null;
    return clean.substring(0, 6);
  }

  static bool isLawEnforcement(String mac) {
    final prefix = _prefixOf(mac);
    return prefix != null && lawEnforcementOuis.containsKey(prefix);
  }

  bool get isLoaded => _loaded;
  int get entryCount => _db.length;
  DateTime? get lastUpdated => _lastUpdated;

  /// Initialize from local cache or bundled asset.
  Future<void> init() async {
    if (_loaded) return;

    final legacy = File('${(await _localFile).parent.path}/$_legacyLocalFileName');
    if (legacy.existsSync()) await legacy.delete();

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

    _loaded = true;
    notifyListeners();
  }

  String? lookup(String macAddress) {
    final prefix = _extractPrefix(macAddress);
    if (prefix == null) return null;
    final le = lawEnforcementOuis[prefix];
    if (le != null) return le;
    final override = _overrides[prefix];
    final dbVendor = _loaded ? longestMatch(_db, macAddress) : null;
    if (override != null) {
      if (dbVendor != null && !dbVendor.startsWith('Flock')) {
        return '$override · $dbVendor';
      }
      return override;
    }
    return dbVendor;
  }

  Future<bool> checkForUpdate() async {
    try {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        _updateUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = utf8.decode(gzip.decode(response.data!));
        final lines = content.split('\n');
        // Validate it looks like valid OUI data
        if (lines.length < 1000) return false;

        final newDb = parseEntries(lines);

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

        // Reload — overrides are applied at lookup time, not in _db
        _db.clear();
        _db.addAll(newDb);
        _lastUpdated = DateTime.now();
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Network error — keep using existing data
    }
    return false;
  }

  void _parseRaw(String content) {
    _db
      ..clear()
      ..addAll(parseEntries(content.split('\n')));
  }

  static String? entryKey(String raw) {
    final slash = raw.indexOf('/');
    final hex = raw.substring(0, slash < 0 ? raw.length : slash).replaceAll(RegExp(r'[:\-.\s]'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return null;
    final bits = slash < 0 ? hex.length * 4 : int.tryParse(raw.substring(slash + 1).trim());
    return switch (bits) {
      24 when hex.length >= 6 => hex.substring(0, 6),
      28 when hex.length >= 7 => hex.substring(0, 7),
      36 when hex.length >= 9 => hex.substring(0, 9),
      _ => null,
    };
  }

  static Map<String, String> parseEntries(Iterable<String> lines) {
    final out = <String, String>{};
    for (final line in lines) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final tabIdx = line.indexOf('\t');
      if (tabIdx == -1) continue;
      final key = entryKey(line.substring(0, tabIdx).trim());
      final vendor = line.substring(line.lastIndexOf('\t') + 1).trim();
      if (key == null || vendor.isEmpty || (key.length > 6 && vendor.startsWith('Private'))) continue;
      out.putIfAbsent(key, () => vendor);
    }
    return out;
  }

  static String? longestMatch(Map<String, String> db, String mac) {
    final hex = mac.replaceAll(RegExp(r'[:\-.]'), '').toUpperCase();
    for (final n in const [9, 7, 6]) {
      if (hex.length < n) continue;
      final v = db[hex.substring(0, n)];
      if (v != null) return v;
    }
    return null;
  }

  /// Extract 6-char hex prefix from MAC string.
  String? _extractPrefix(String mac) => _prefixOf(mac);

  Future<File> get _localFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_localFileName');
  }
}
