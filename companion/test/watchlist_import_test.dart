// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/export/detections_csv.dart' show csvCell;
import 'package:oui_spy/core/watchlist_state.dart';

void main() {
  test('csvCell neutralizes formula prefixes, keeps numbers', () {
    expect(csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
    expect(csvCell('@sum'), "'@sum");
    expect(csvCell('-cmd'), "'-cmd");
    expect(csvCell('-71'), '-71');
    expect(csvCell('-33.5'), '-33.5');
    expect(csvCell('a,b'), '"a,b"');
  });

  test('csv: infers type, normalizes, keeps commas in description', () {
    final r = parseWatchlistImport('identifier,description\n'
        'b4-1e-52,Flock, Inc\n'
        'aabbccddeeff,My tag\n'
        'fd5f,Meta,UUID\n'
        'zz:zz:zz,bad\n'
        '# comment\n');
    expect(r.invalid, 1);
    expect(r.entries.map((e) => '${e.matchType.name} ${e.identifier} ${e.description}'), [
      'oui B4:1E:52 Flock, Inc',
      'fullMac AA:BB:CC:DD:EE:FF My tag',
      'serviceUuid FD5F Meta',
    ]);
  });

  test('json round-trip and description sanitized + capped', () {
    final r = parseWatchlistImport(
        '[{"identifier":"00:25:df","description":"Axon\\u202e\\u0007${'x' * 60}","matchType":"oui","enabled":false},'
        '{"identifier":5},"junk"]');
    expect(r.invalid, 2);
    final e = r.entries.single;
    expect(e.identifier, '00:25:DF');
    expect(e.enabled, false);
    expect(e.description.startsWith('Axonx'), true);
    expect(e.description.length, 31);
  });
}
