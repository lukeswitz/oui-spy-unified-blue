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

  test('Wireshark manuf rows use the long name column', () {
    final db = OuiLookupService.parseEntries(const [
      '54:E0:19         \tRing        \tRing LLC',
      '64:33:B5:40/28   \tEagleEyeNetw\tEagle Eye Networks, Inc',
    ]);
    expect(db['54E019'], 'Ring LLC');
    expect(db['6433B54'], 'Eagle Eye Networks, Inc');
  });

  test('bundled asset carries MA-L, MA-M and MA-S with full vendor names', () {
    final lines = const LineSplitter().convert(utf8.decode(gzip.decode(File('assets/oui_vendors.tsv.gz').readAsBytesSync())));
    final db = OuiLookupService.parseEntries(lines);
    expect(db.keys.where((k) => k.length == 6).length, greaterThan(40000));
    expect(db.keys.where((k) => k.length == 7).length, greaterThan(6000));
    expect(db.keys.where((k) => k.length == 9).length, greaterThan(11000));
    expect(OuiLookupService.longestMatch(db, '54:E0:19:00:00:01'), 'Ring LLC');
    expect(OuiLookupService.longestMatch(db, 'C8:19:D8:00:00:01'), 'Blink by Amazon');
    expect(OuiLookupService.longestMatch(db, '64:33:B5:40:00:01'), 'Eagle Eye Networks, Inc');
  });
}
