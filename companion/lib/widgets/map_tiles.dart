import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeReader;

import 'package:oui_spy/theme/app_theme.dart';

final Map<String, Future<Style>> _styleCache = {};

/// vector_tile_renderer's colour parser rejects the CSS keyword `transparent`,
/// which CARTO's GL styles use on three layers. Rewrite it to its rgba form
/// before the theme is built, otherwise the first paint of those layers throws
/// and the whole tile renders blank.
Object? _rgbaForTransparent(Object? node) {
  if (node == 'transparent') return 'rgba(0,0,0,0)';
  if (node is Map) {
    return node.map((k, v) => MapEntry(k as String, _rgbaForTransparent(v)));
  }
  if (node is List) return node.map(_rgbaForTransparent).toList();
  return node;
}

Future<Style> _readStyle(String url) async {
  final style = await StyleReader(uri: url).read();
  final response = await Dio().get<Map<String, dynamic>>(url);
  final raw = response.data;
  if (raw == null) return style;
  return Style(
    name: style.name,
    theme: ThemeReader()
        .read(_rgbaForTransparent(raw)! as Map<String, dynamic>),
    providers: style.providers,
    sprites: style.sprites,
  );
}

Widget mapTileLayer(MapStyle style, {ColorFilter? tint}) {
  if (style.isVector) return _VectorTiles(style: style, tint: tint);
  final layer = TileLayer(
    urlTemplate: style.url,
    userAgentPackageName: 'tech.colonelpanic.ouispy',
    maxZoom: 19,
    tileBuilder: tint == null
        ? null
        : (context, tileWidget, tile) =>
            ColorFiltered(colorFilter: tint, child: tileWidget),
  );
  return layer;
}

class _VectorTiles extends StatelessWidget {
  const _VectorTiles({required this.style, this.tint});

  final MapStyle style;
  final ColorFilter? tint;

  @override
  Widget build(BuildContext context) {
    final future = _styleCache.putIfAbsent(
      style.url,
      () => _readStyle(style.url),
    );
    return FutureBuilder<Style>(
      future: future,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded == null) return const SizedBox.shrink();
        final Widget layer = VectorTileLayer(
          theme: loaded.theme,
          sprites: loaded.sprites,
          tileProviders: loaded.providers,
          layerMode: VectorTileLayerMode.raster,
          maximumZoom: 19,
        );
        if (tint == null) return layer;
        return ColorFiltered(colorFilter: tint!, child: layer);
      },
    );
  }
}

Widget mapAttribution(MapStyle style) {
  return Align(
    alignment: Alignment.bottomRight,
    child: IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: const Color(0x66000000),
        child: Text(
          style.attribution,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 8,
            height: 1.2,
            color: Color(0xFFB0B5C8),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
