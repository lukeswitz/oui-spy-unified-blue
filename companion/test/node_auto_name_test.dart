import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';

void main() {
  test('chip codes cover every firmware board', () {
    expect(AppState.chipCode('xiao_c5'), 'C5');
    expect(AppState.chipCode('tdongle_c5'), 'C5');
    expect(AppState.chipCode('xiao_c3'), 'C3');
    expect(AppState.chipCode('xiao_s3'), 'S3');
    expect(AppState.chipCode('s3_devkitc'), 'S3');
    expect(AppState.chipCode('tdongle_s3'), 'S3');
    expect(AppState.chipCode('stickc'), '32');
    expect(AppState.chipCode('stickc_plus'), '32');
    expect(AppState.chipCode('stickc_plus2'), '32');
    expect(AppState.chipCode('wroom'), '32');
    expect(AppState.chipCode(''), isNull);
    expect(AppState.chipCode('unknown'), isNull);
  });

  test('numbers count up per chip in order first seen', () {
    expect(AppState.nextAutoName('C5', const []), 'C501');
    expect(AppState.nextAutoName('C5', const ['C501']), 'C502');
    expect(AppState.nextAutoName('C3', const ['C501', 'C502']), 'C301');
    expect(AppState.nextAutoName('S3', const ['S301', 'C501', 'S303']), 'S304');
    expect(AppState.nextAutoName('32', const ['3201', 'S301']), '3202');
  });
}
