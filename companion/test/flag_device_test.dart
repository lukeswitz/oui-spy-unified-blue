// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/features/feed/device_notes_sheet.dart';

void main() {
  test('MAC keys normalize to the watchlist form; platform ids are refused', () {
    expect(watchMacKey('aa-bb-cc-dd-ee-ff'), 'AA:BB:CC:DD:EE:FF');
    expect(watchMacKey('AABBCCDDEEFF'), 'AA:BB:CC:DD:EE:FF');
    expect(watchMacKey('00000000-0000-0000-0000-000000000001'), '');
  });

  test('a device counts as watched only by an exact-MAC entry', () {
    final entries = [
      WatchlistEntry(identifier: 'AA:BB:CC', matchType: WatchlistMatchType.oui),
      WatchlistEntry(identifier: 'aa:bb:cc:dd:ee:01', matchType: WatchlistMatchType.fullMac),
    ];
    expect(isWatchedMac(entries, 'AA:BB:CC:DD:EE:01'), isTrue);
    expect(isWatchedMac(entries, 'AA:BB:CC:DD:EE:02'), isFalse);
  });
}
