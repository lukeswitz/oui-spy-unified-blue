import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/privacy.dart';

void main() {
  test('MAC keeps the first two bytes only when on', () {
    expect(maskMac('AA:BB:CC:DD:EE:FF', true), 'AA:BB:XX:XX:XX:XX');
    expect(maskMac('aabbccddeeff', true), 'AA:BB:XX:XX:XX:XX');
    expect(maskMac('AA:BB:CC:DD:EE:FF', false), 'AA:BB:CC:DD:EE:FF');
    expect(maskMac('not-a-mac', true), 'XX:XX:XX:XX:XX:XX');
  });

  test('names keep three characters when on', () {
    expect(maskName('MyNetwork', true), 'MyN••••••');
    expect(maskName('abc', true), 'abc');
    expect(maskName('MyNetwork', false), 'MyNetwork');
  });
}
