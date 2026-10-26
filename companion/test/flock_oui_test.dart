import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/oui/flock_oui.dart';

void main() {
  test('table is the upstream flock-you set', () {
    expect(FlockOui.table.length, 34);
    expect(FlockOui.table.toSet().length, 34);
  });

  test('matches upstream OUIs including the locally-administered one', () {
    expect(FlockOui.match('B4:1E:52:00:00:01'), isTrue);
    expect(FlockOui.match('00:03:7f:00:00:01'), isTrue);
    expect(FlockOui.match('82:6B:F2:00:00:01'), isTrue);
  });

  test('rejects extended-set and unrelated OUIs', () {
    expect(FlockOui.match('24:0A:C4:00:00:01'), isFalse);
    expect(FlockOui.match('AC:CC:8E:00:00:01'), isFalse);
    expect(FlockOui.match('02:00:00:00:00:01'), isFalse);
    expect(FlockOui.match('B4:1E'), isFalse);
  });
}
