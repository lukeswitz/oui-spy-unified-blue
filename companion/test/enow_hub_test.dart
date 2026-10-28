import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';

void main() {
  test('hub node MAC maps to the firmware source id E%03X of its last 12 bits', () {
    expect(BleManager.enowSourceId('02:00:00:00:10:01'), 'E001');
    expect(BleManager.enowSourceId('02:00:00:00:A7:1C'), 'E71C');
    expect(BleManager.enowSourceId('not-a-mac'), '');
  });
}
