import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/cta2063.dart';

void main() {
  test('published manufacturer prefixes name the maker', () {
    expect(cta2063Maker('1581F4XFC0000000000A'), 'DJI');
    expect(cta2063Maker(' 1748c00000000000 '), 'Autel Robotics');
    expect(cta2063Maker('1701A0000000'), 'Percepto');
    expect(cta2063Maker('1587A0000000'), 'AgEagle');
    expect(cta2063Maker('1785C000000000000'), 'Watts Innovations');
  });

  test('unknown prefixes and non-serial ID types give no maker', () {
    expect(cta2063Maker('9999A0000000'), isNull);
    expect(cta2063Maker('1581A0000000'), isNull);
    expect(cta2063Maker('1581F4XFC0000000000A', idType: 2), isNull);
    expect(cta2063Maker('1581F4XFC0000000000A', idType: 1), 'DJI');
    expect(cta2063Maker(''), isNull);
  });
}
