import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/link/sdr.dart';

void main() {
  test('no usage field leaves the detection without a gauge', () {
    final f = <String, Object?>{'model': 'SilverSpring-Mesh', 'id': 'AABBCCDDEEFF0011'};
    sdrTrackUsage(f, null, 0);
    expect(f.containsKey('_usage'), isFalse);
  });

  test('cumulative reading gives a rate once it changes, needle relative to peak', () {
    final a = <String, Object?>{'model': 'ERT-SCM', 'consumption_data': 1000};
    sdrTrackUsage(a, null, 0);
    expect(a['_usage'], 0.0);

    final b = <String, Object?>{'model': 'ERT-SCM', 'consumption_data': 1010};
    sdrTrackUsage(b, a, 3600000);
    expect(b['_usageRate'], 10.0);
    expect(b['_usage'], 1.0);

    final c = <String, Object?>{'model': 'ERT-SCM', 'consumption_data': 1010};
    sdrTrackUsage(c, b, 3700000);
    expect(c['_usageRate'], 10.0);

    final d = <String, Object?>{'model': 'ERT-SCM', 'consumption_data': 1015};
    sdrTrackUsage(d, c, 7200000);
    expect(d['_usageRate'], 5.0);
    expect(d['_usage'], 0.5);
  });

  test('instant power drives the needle directly', () {
    final a = <String, Object?>{'model': 'Efergy-e2CT', 'power_W': 2000.0};
    sdrTrackUsage(a, null, 0);
    expect(a['_usage'], 1.0);
    final b = <String, Object?>{'model': 'Efergy-e2CT', 'power_W': 500.0};
    sdrTrackUsage(b, a, 1000);
    expect(b['_usage'], 0.25);
  });
}
