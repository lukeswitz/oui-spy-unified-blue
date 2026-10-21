import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:oui_spy/theme/app_theme.dart';

const tileCacheTtl = Duration(days: 7);
const _tileCacheMaxAge = Duration(days: 30);
const _tileCacheMaxBytes = 200 * 1024 * 1024;

final Dio _tileDio = Dio(BaseOptions(
  responseType: ResponseType.bytes,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
));

Future<Directory>? _tileDir;

Future<Directory> _openTileDir() async {
  final base = await getApplicationCacheDirectory();
  final dir = Directory('${base.path}/map_tiles');
  await dir.create(recursive: true);
  unawaited(pruneTileCache(dir, DateTime.now()));
  return dir;
}

@visibleForTesting
Future<void> pruneTileCache(Directory dir, DateTime now,
    {int maxBytes = _tileCacheMaxBytes}) async {
  final files = <(File, FileStat)>[];
  await for (final e in dir.list()) {
    if (e is File) files.add((e, await e.stat()));
  }
  files.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
  var total = 0;
  for (final (f, s) in files) {
    total += s.size;
    if (total > maxBytes || now.difference(s.modified) > _tileCacheMaxAge) {
      await f.delete();
    }
  }
}

@visibleForTesting
Future<Uint8List> cachedTileBytes(
    Directory dir, String url, Map<String, String> headers,
    {Future<Uint8List> Function(String url, Map<String, String> headers)? fetch}) async {
  final file = File('${dir.path}/${sha1.convert(utf8.encode(url))}');
  final stat = await file.stat();
  final cached = stat.type == FileSystemEntityType.file;
  if (cached && DateTime.now().difference(stat.modified) < tileCacheTtl) {
    return file.readAsBytes();
  }
  try {
    final bytes = await (fetch ?? _fetchTile)(url, headers);
    await file.writeAsBytes(bytes);
    return bytes;
  } catch (_) {
    if (cached) return file.readAsBytes();
    rethrow;
  }
}

Future<Uint8List> _fetchTile(String url, Map<String, String> headers) async {
  final r = await _tileDio.get<List<int>>(url, options: Options(headers: headers));
  return Uint8List.fromList(r.data!);
}

class _CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _CachedTileImage(getTileUrl(coordinates, options), headers);
}

@immutable
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage(this.url, this.headers);

  final String url;
  final Map<String, String> headers;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_CachedTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: 1,
        debugLabel: url,
      );

  Future<ui.Codec> _load(_CachedTileImage key, ImageDecoderCallback decode) async {
    try {
      final dir = await (_tileDir ??= _openTileDir());
      final bytes = await cachedTileBytes(dir, url, headers);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is _CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

Widget mapTileLayer(MapStyle style) {
  if (style.isVector) return _VectorTiles(style: style);
  return TileLayer(
    urlTemplate: style.url,
    userAgentPackageName: 'tech.colonelpanic.ouispy',
    tileProvider: _CachedTileProvider(),
    maxZoom: 19,
    maxNativeZoom: style.maxNativeZoom,
  );
}

final Map<String, Future<Style>> _styleCache = {};

@visibleForTesting
Style identifiedStyle(Style s, MapStyle m) => Style(
      name: s.name,
      theme: s.theme.copyWith(id: 'oui-apex-${m.name}'),
      providers: s.providers,
      sprites: s.sprites,
      center: s.center,
      zoom: s.zoom,
    );

class _VectorTiles extends StatelessWidget {
  const _VectorTiles({required this.style});

  final MapStyle style;

  @override
  Widget build(BuildContext context) {
    final future = _styleCache.putIfAbsent(
      style.url,
      () async => identifiedStyle(await StyleReader(uri: style.url).read(), style),
    );
    return FutureBuilder<Style>(
      future: future,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded == null) return const SizedBox.shrink();
        return VectorTileLayer(
          theme: loaded.theme,
          sprites: loaded.sprites,
          tileProviders: loaded.providers,
          layerMode: VectorTileLayerMode.raster,
          maximumZoom: 19,
        );
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
