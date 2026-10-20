import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every map style is keyless: OpenFreeMap vector or USGS imagery', () {
    for (final s in MapStyle.values) {
      expect(
          s.url.startsWith('https://tiles.openfreemap.org/styles/') ||
              s.url.startsWith('https://basemap.nationalmap.gov/'),
          isTrue,
          reason: s.name);
      expect(s.url.contains('key='), isFalse, reason: s.name);
    }
    expect(MapStyle.dark.isDark, isTrue);
    expect(MapStyle.satellite.maxNativeZoom, 16);
  });

  test('a saved style that no longer exists maps to its nearest replacement', () async {
    for (final (saved, want) in [
      (null, MapStyle.dark),
      ('cartoDark', MapStyle.dark),
      ('cartoLight', MapStyle.positron),
      ('cartoVoyager', MapStyle.liberty),
      ('osm', MapStyle.liberty),
      ('openTopo', MapStyle.liberty),
      ('terrain', MapStyle.liberty),
      ('satellite', MapStyle.satellite),
      ('fiord', MapStyle.fiord),
    ]) {
      SharedPreferences.setMockInitialValues({'map_style': ?saved});
      final n = MapStyleNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, want, reason: saved);
    }
  });
}
