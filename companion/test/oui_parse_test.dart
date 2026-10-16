import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';

void main() {
  test('parses bare, colon, MA-M and MA-S notation; longest prefix wins', () {
    final db = OuiLookupService.parseEntries(const [
      '# header',
      'AA0001\tVendor Bare',
      'AA:00:02\tIEEE Registration Authority',
      'AA:00:02:70/28\tVendor Medium',
      'AA:00:03:90/28\tPrivate (undisclosed IEEE registrant)',
      'AA:00:02:AF:A0/36\tVendor Small',
      'AA0002A\tVendor Medium Bare',
      'ZZ:ZZ:ZZ\tbad',
    ]);
    expect(db['AA0001'], 'Vendor Bare');
    expect(db['AA00027'], 'Vendor Medium');
    expect(db['AA0002AFA'], 'Vendor Small');
    expect(db.containsKey('AA00039'), isFalse);
    expect(db.length, 5);
    expect(OuiLookupService.longestMatch(db, 'AA:00:02:AF:A1:23'), 'Vendor Small');
    expect(OuiLookupService.longestMatch(db, 'AA:00:02:7F:00:01'), 'Vendor Medium');
    expect(OuiLookupService.longestMatch(db, 'AA:00:02:A0:00:01'), 'Vendor Medium Bare');
    expect(OuiLookupService.longestMatch(db, 'AA:00:02:B0:00:01'), 'IEEE Registration Authority');
    expect(OuiLookupService.longestMatch(db, 'AA:00:01:00:00:01'), 'Vendor Bare');
  });

  test('bundled asset still parses to the same MA-L set', () {
    final lines = const LineSplitter().convert(utf8.decode(gzip.decode(File('assets/oui_vendors.tsv.gz').readAsBytesSync())));
    final db = OuiLookupService.parseEntries(lines);
    expect(db.length, greaterThan(39000));
    expect(db.keys.every((k) => k.length == 6), isTrue);
  });
}
