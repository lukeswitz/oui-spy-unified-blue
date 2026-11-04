import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';

void main() {
  test('adding a board keeps others and replaces its own entry', () {
    var entries = BleManager.pairedEntriesWith(const [], 'A', 'OUI-SPY');
    entries = BleManager.pairedEntriesWith(entries, 'B', 'OUI-SPY-MGR');
    entries = BleManager.pairedEntriesWith(entries, 'A', 'OUI-SPY-MGR');
    expect(entries, ['B|OUI-SPY-MGR', 'A|OUI-SPY-MGR']);
  });

  test('forgetting removes only that board', () {
    final entries = BleManager.pairedEntriesWithout(['A|OUI-SPY', 'B|OUI-SPY'], 'A');
    expect(entries, ['B|OUI-SPY']);
  });

  test('parsing skips malformed entries', () {
    final boards = BleManager.parsePairedEntries(['A|OUI-SPY', 'broken', 'B|C|D']);
    expect(boards, [(id: 'A', name: 'OUI-SPY')]);
  });
}
