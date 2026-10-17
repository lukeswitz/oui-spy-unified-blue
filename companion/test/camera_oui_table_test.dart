import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/vendor_class.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';

void main() {
  test('firmware camera OUI table matches classifier camera vendors and brand names', () {
    VendorClass.loadTable([for (final p in VendorClass.tableAssets) File(p).readAsStringSync()]);
    final src = File('../src/engines/camera_oui.h').readAsStringSync();
    final brands = RegExp(r'"([^"]+)"')
        .allMatches(src.substring(src.indexOf('CAMERA_BRANDS[]'), src.indexOf('};')))
        .map((m) => m[1]!)
        .toList();
    final entries = RegExp(r'0x([0-9A-F]{8})')
        .allMatches(src.substring(src.indexOf('CAMERA_OUI_TABLE[]'), src.indexOf('CAMERA_OUI_COUNT')))
        .map((m) => int.parse(m[1]!, radix: 16))
        .toList();
    final blocks = RegExp(r'\{ \{0x(..), 0x(..), 0x(..), 0x(..), 0x(..)\}, (28|36), (\d+) \}')
        .allMatches(src)
        .map((m) => ([for (var i = 1; i <= 5; i++) m[i]!].join().substring(0, int.parse(m[6]!) ~/ 4), int.parse(m[7]!)))
        .toList();
    final db = OuiLookupService.parseEntries(
      utf8.decode(gzip.decode(File('assets/oui_vendors.tsv.gz').readAsBytesSync())).split('\n'),
    );
    expect(entries, isNotEmpty);
    for (var i = 1; i < entries.length; i++) {
      expect(entries[i] >> 8, greaterThan(entries[i - 1] >> 8));
    }
    for (final e in entries) {
      final oui = (e >> 8).toRadixString(16).toUpperCase().padLeft(6, '0');
      expect(e & 0xFF, lessThan(brands.length));
      final vendor = db[oui];
      expect(vendor, isNotNull, reason: oui);
      if (vendor!.toLowerCase().contains('nest labs')) {
        expect(brands[e & 0xFF], 'Nest');
        continue;
      }
      final bucket = VendorClass.ruleForKind(vendor, RadioKind.wifi)?.bucket;
      expect({'camera', 'bodyworn'}, contains(bucket), reason: '$oui $vendor');
    }
    expect(blocks.length, greaterThan(40));
    for (final (key, brand) in blocks) {
      expect(brand, lessThan(brands.length));
      final vendor = db[key];
      expect(vendor, isNotNull, reason: key);
      final bucket = VendorClass.ruleForKind(vendor!, RadioKind.wifi)?.bucket;
      expect({'camera', 'bodyworn'}, contains(bucket), reason: '$key $vendor');
      expect(vendor.toLowerCase().replaceAll(' ', ''), contains(brands[brand].toLowerCase().replaceAll(' ', '').substring(0, 3)),
          reason: '$key $vendor ${brands[brand]}');
    }
    expect(brands[entries.firstWhere((e) => e >> 8 == 0x54E019) & 0xFF], 'Ring');
    expect(brands[entries.firstWhere((e) => e >> 8 == 0xC819D8) & 0xFF], 'Blink');
    expect(brands[entries.firstWhere((e) => e >> 8 == 0x308CFB) & 0xFF], 'Nest');
  });
}
