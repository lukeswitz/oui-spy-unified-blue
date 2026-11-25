// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

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
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeReader;

import 'package:oui_spy/core/offline/offline_maps.dart';
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
    {Future<Uint8List> Function(String url, Map<String, String> headers)? fetch,
    OfflineStore? offline}) async {
  final saved = await offline?.readTile(urlTileName(url));
  if (saved != null) return saved;
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
      final bytes = await cachedTileBytes(dir, url, headers, offline: await openOfflineStore());
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
Object? cssColorKeywords(Object? v) => switch (v) {
      'transparent' => 'rgba(0,0,0,0)',
      Map<String, dynamic>() => <String, dynamic>{for (final e in v.entries) e.key: cssColorKeywords(e.value)},
      List() => [for (final e in v) cssColorKeywords(e)],
      _ => v,
    };

class OfflineFirstTileProvider extends VectorTileProvider {
  OfflineFirstTileProvider(this.delegate, this.store, this.source);

  final VectorTileProvider delegate;
  final OfflineStore store;
  final String source;

  @override
  TileProviderType get type => delegate.type;

  @override
  int get maximumZoom => delegate.maximumZoom;

  @override
  int get minimumZoom => delegate.minimumZoom;

  @override
  Future<Uint8List> provide(TileIdentity tile) async =>
      await store.readTile(sourceTileName(source, tile.z, tile.x, tile.y)) ?? await delegate.provide(tile);
}

Future<Style> _readStyle(MapStyle m) async {
  if (!offlineAllowed(m)) return _readStyleOnline(m, null);
  final store = await openOfflineStore();
  try {
    return await _readStyleOnline(m, store);
  } catch (_) {
    final saved = await store.savedStyle(m);
    if (saved == null) rethrow;
    return identifiedStyle(savedOfflineStyle(saved, store), m);
  }
}

Future<Style> _readStyleOnline(MapStyle m, OfflineStore? store) async {
  final s = await StyleReader(uri: m.url).read();
  final raw = await _tileDio.get<List<int>>(m.url);
  final json = cssColorKeywords(jsonDecode(utf8.decode(raw.data!))) as Map<String, dynamic>;
  return identifiedStyle(
      Style(
        name: s.name,
        theme: ThemeReader().read(json),
        providers: store == null
            ? s.providers
            : TileProviders({
                for (final e in s.providers.tileProviderBySource.entries)
                  e.key: OfflineFirstTileProvider(e.value, store, e.key),
              }),
        sprites: s.sprites,
        center: s.center,
        zoom: s.zoom,
      ),
      m);
}

@visibleForTesting
Style savedOfflineStyle(ResolvedVectorStyle saved, OfflineStore store) => Style(
      theme: ThemeReader().read(cssColorKeywords(saved.styleJson) as Map<String, dynamic>),
      providers: TileProviders({
        for (final s in saved.sources)
          s.name: OfflineFirstTileProvider(
              NetworkVectorTileProvider(
                urlTemplate: s.template,
                type: s.kind == OfflineKind.raster ? TileProviderType.raster : TileProviderType.vector,
                maximumZoom: s.maxZoom,
                minimumZoom: s.minZoom,
              ),
              store,
              s.name),
      }),
    );

Future<({List<OfflineSource> sources, ResolvedVectorStyle? vectorStyle})> resolveOfflineSources(
    MapStyle m, String userAgent) async {
  if (m.isVector) {
    final r = await resolveVectorStyle(m, userAgent);
    return (sources: r.sources, vectorStyle: r);
  }
  final provider = _CachedTileProvider();
  final options = TileLayer(urlTemplate: m.url);
  return (
    sources: [
      OfflineSource(
        name: 'tiles',
        kind: OfflineKind.layer,
        template: m.url,
        minZoom: 0,
        maxZoom: m.maxNativeZoom,
        urlOverride: (z, x, y) => provider.getTileUrl(TileCoordinates(x, y, z), options),
      ),
    ],
    vectorStyle: null,
  );
}

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
    final future = _styleCache.putIfAbsent(style.url, () => _readStyle(style));
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
        color: AppTheme.background.withValues(alpha: 0.4),
        child: Text(
          style.attribution,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 8,
            height: 1.2,
            color: AppTheme.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
