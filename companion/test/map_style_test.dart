import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeReader;

import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

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

  test('each vector style gets its own theme id so switching styles re-renders', () {
    final base = ThemeReader().read({'version': 8, 'sources': {}, 'layers': []});
    expect(base.id, 'default');
    final style = Style(theme: base, providers: const TileProviders({}));
    final ids = {
      for (final m in MapStyle.values.where((m) => m.isVector))
        identifiedStyle(style, m).theme.id,
    };
    expect(ids.length, MapStyle.values.where((m) => m.isVector).length);
    expect(ids.contains('default'), isFalse);
    expect(identifiedStyle(style, MapStyle.dark).theme.version, base.version);
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
