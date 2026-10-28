import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/features/sdr/sdr433_classify.dart';

void main() {
  test('SilverSpring-Mesh classifies as meter despite separator/case', () {
    expect(classify433('SilverSpring-Mesh', const ['tlvs', 'seed', 'data']),
        Sdr433Category.meter);
    expect(classify433('silverspring', const []), Sdr433Category.meter);
    expect(classify433('SILVER_SPRING', const []), Sdr433Category.meter);
  });

  test('hyphen/case variants still match their lists', () {
    expect(classify433('Microchip-HCS361', const []), Sdr433Category.fob);
    expect(classify433('AVE', const [], devType: 'tpms'), Sdr433Category.tpms);
    expect(classify433('Oregon-THGR810', const []), Sdr433Category.weather);
  });

  test('unknown model with no fields stays unknown', () {
    expect(classify433('NoSuchDevice', const []), Sdr433Category.unknown);
  });
}
