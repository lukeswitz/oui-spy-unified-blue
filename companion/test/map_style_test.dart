import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeReader;

import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every map style is keyless https', () {
    for (final s in MapStyle.values) {
      expect(s.url.startsWith('https://'), isTrue, reason: s.name);
      expect(s.url.contains('key='), isFalse, reason: s.name);
    }
    expect(
        MapStyle.values.map((s) => s.name),
        containsAll(['osm', 'openTopo', 'terrain', 'satelliteWorld', 'cartoDark', 'cartoLight', 'cartoVoyager']));
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

  test('CSS transparent becomes rgba the renderer parses', () {
    final out = cssColorKeywords({
      'layers': [
        {'paint': {'fill-color': 'transparent', 'line-color': '#fff'}, 'id': 'transparent-ish'},
      ],
    }) as Map;
    final paint = (out['layers'] as List).first['paint'] as Map;
    expect(paint['fill-color'], 'rgba(0,0,0,0)');
    expect(paint['line-color'], '#fff');
    final theme = ThemeReader().read(cssColorKeywords({
      'version': 8,
      'sources': <String, dynamic>{},
      'layers': [
        {'id': 'bg', 'type': 'background', 'paint': {'background-color': 'transparent'}},
      ],
    }) as Map<String, dynamic>);
    expect(theme.layers, isNotEmpty);
  });

  test('a saved style loads back', () async {
    for (final (saved, want) in [
      (null, MapStyle.dark),
      ('cartoDark', MapStyle.cartoDark),
      ('cartoLight', MapStyle.cartoLight),
      ('cartoVoyager', MapStyle.cartoVoyager),
      ('osm', MapStyle.osm),
      ('openTopo', MapStyle.openTopo),
      ('terrain', MapStyle.terrain),
      ('satellite', MapStyle.satellite),
      ('satelliteWorld', MapStyle.satelliteWorld),
      ('fiord', MapStyle.fiord),
    ]) {
      SharedPreferences.setMockInitialValues({'map_style': ?saved});
      final n = MapStyleNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, want, reason: saved);
    }
  });
}
