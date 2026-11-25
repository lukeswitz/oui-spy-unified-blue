// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';

import 'package:oui_spy/theme/app_theme.dart';

const offlineMaxTiles = 3000;
const offlineMaxBytes = 50 * 1024 * 1024;
const offlineParallel = 4;
const offlineZoomSpan = 3;
const offlineRefusal = "This map's provider does not allow offline downloads";

const offlineAllowedStyles = {
  MapStyle.dark,
  MapStyle.fiord,
  MapStyle.liberty,
  MapStyle.bright,
  MapStyle.positron,
  MapStyle.satellite,
};

bool offlineAllowed(MapStyle s) => offlineAllowedStyles.contains(s);

String offlineUserAgent(String version) => 'OUI-APEX/$version';

String offlineSizeLabel(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

int lonToTileX(double lon, int z) {
  final n = 1 << z;
  return _clampInt((((lon.clamp(-180.0, 180.0) + 180) / 360) * n).floor(), 0, n - 1);
}

int latToTileY(double lat, int z) {
  final n = 1 << z;
  final r = lat.clamp(-85.05112878, 85.05112878) * pi / 180;
  return _clampInt(((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor(), 0, n - 1);
}

class TileRange {
  const TileRange(this.z, this.x0, this.x1, this.y0, this.y1);

  final int z;
  final int x0;
  final int x1;
  final int y0;
  final int y1;

  int get count => (x1 - x0 + 1) * (y1 - y0 + 1);
}

TileRange tileRangeFor(LatLngBounds b, int z) => TileRange(
      z,
      lonToTileX(b.west, z),
      lonToTileX(b.east, z),
      latToTileY(b.north, z),
      latToTileY(b.south, z),
    );

String urlTileName(String url) => 'u_${sha1.convert(utf8.encode(url))}';

String sourceTileName(String source, int z, int x, int y) =>
    'v_${source.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}_${z}_${x}_$y';

enum OfflineKind { vector, raster, layer }

class OfflineSource {
  const OfflineSource({
    required this.name,
    required this.kind,
    required this.template,
    required this.minZoom,
    required this.maxZoom,
    this.urlOverride,
  });

  factory OfflineSource.fromJson(Map<String, dynamic> j) => OfflineSource(
        name: j['name'] as String,
        kind: OfflineKind.values.byName(j['kind'] as String),
        template: j['template'] as String,
        minZoom: j['minZoom'] as int,
        maxZoom: j['maxZoom'] as int,
      );

  final String name;
  final OfflineKind kind;
  final String template;
  final int minZoom;
  final int maxZoom;
  final String Function(int z, int x, int y)? urlOverride;

  int get avgBytes => switch (kind) {
        OfflineKind.vector => 40 * 1024,
        OfflineKind.raster => 150 * 1024,
        OfflineKind.layer => 25 * 1024,
      };

  String urlFor(int z, int x, int y) =>
      urlOverride?.call(z, x, y) ??
      template.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');

  String fileName(int z, int x, int y) =>
      kind == OfflineKind.layer ? urlTileName(urlFor(z, x, y)) : sourceTileName(name, z, x, y);

  int? effectiveZoom(int z) => z < minZoom ? null : min(z, maxZoom);

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'template': template,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
      };
}

class OfflineTile {
  const OfflineTile(this.url, this.name);

  final String url;
  final String name;
}

class OfflinePlan {
  OfflinePlan._(this.style, this.sources, this.bounds, this.minZoom, this.maxZoom, this.parts);

  factory OfflinePlan.build({
    required MapStyle style,
    required List<OfflineSource> sources,
    required LatLngBounds bounds,
    required double zoom,
  }) {
    final cap = sources.isEmpty ? 0 : sources.map((s) => s.maxZoom).reduce(max);
    final minZoom = _clampInt(zoom.floor(), 0, cap);
    final maxZoom = min(minZoom + offlineZoomSpan, cap);
    final parts = <(OfflineSource, TileRange)>[];
    for (final s in sources) {
      final zooms = <int>{};
      for (var z = minZoom; z <= maxZoom; z++) {
        final e = s.effectiveZoom(z);
        if (e != null) zooms.add(e);
      }
      for (final z in zooms.toList()..sort()) {
        parts.add((s, tileRangeFor(bounds, z)));
      }
    }
    return OfflinePlan._(style, sources, bounds, minZoom, maxZoom, parts);
  }

  final MapStyle style;
  final List<OfflineSource> sources;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final List<(OfflineSource, TileRange)> parts;

  int get tileCount => parts.fold(0, (n, p) => n + p.$2.count);

  int get estimatedBytes => parts.fold(0, (n, p) => n + p.$2.count * p.$1.avgBytes);

  String? get refusal {
    if (!offlineAllowed(style)) return offlineRefusal;
    if (tileCount == 0) return 'This map has no tiles to save at this zoom.';
    if (tileCount > offlineMaxTiles) {
      return 'This area needs $tileCount tiles. The limit is $offlineMaxTiles. Zoom in or move to a smaller area.';
    }
    return null;
  }

  Iterable<OfflineTile> get tiles sync* {
    for (final (s, r) in parts) {
      for (var x = r.x0; x <= r.x1; x++) {
        for (var y = r.y0; y <= r.y1; y++) {
          yield OfflineTile(s.urlFor(r.z, x, y), s.fileName(r.z, x, y));
        }
      }
    }
  }
}

class OfflineArea {
  const OfflineArea({
    required this.id,
    required this.style,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.minZoom,
    required this.maxZoom,
    required this.tiles,
    required this.bytes,
    required this.createdMs,
  });

  factory OfflineArea.fromJson(Map<String, dynamic> j) => OfflineArea(
        id: j['id'] as String,
        style: j['style'] as String,
        south: (j['south'] as num).toDouble(),
        west: (j['west'] as num).toDouble(),
        north: (j['north'] as num).toDouble(),
        east: (j['east'] as num).toDouble(),
        minZoom: j['minZoom'] as int,
        maxZoom: j['maxZoom'] as int,
        tiles: j['tiles'] as int,
        bytes: j['bytes'] as int,
        createdMs: j['createdMs'] as int,
      );

  final String id;
  final String style;
  final double south;
  final double west;
  final double north;
  final double east;
  final int minZoom;
  final int maxZoom;
  final int tiles;
  final int bytes;
  final int createdMs;

  String get styleLabel {
    for (final s in MapStyle.values) {
      if (s.name == style) return s.label;
    }
    return style;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'style': style,
        'south': south,
        'west': west,
        'north': north,
        'east': east,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'tiles': tiles,
        'bytes': bytes,
        'createdMs': createdMs,
      };
}

class OfflineCancel {
  bool canceled = false;
}

class OfflineDownloadException implements Exception {
  const OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef OfflineFetch = Future<Uint8List?> Function(String url, Map<String, String> headers);

final Dio _offlineDio = Dio(BaseOptions(
  responseType: ResponseType.bytes,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
  validateStatus: (s) => s == 200 || s == 404,
));

Future<Uint8List?> _fetchOfflineTile(String url, Map<String, String> headers) async {
  final r = await _offlineDio.get<List<int>>(url, options: Options(headers: headers));
  if (r.statusCode == 404) return null;
  return Uint8List.fromList(r.data!);
}

Future<Map<String, dynamic>> fetchOfflineJson(String url, String userAgent) async {
  final r = await _offlineDio.get<List<int>>(url, options: Options(headers: {'User-Agent': userAgent}));
  if (r.statusCode != 200) throw OfflineDownloadException('Map source not found: HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.data!)) as Map<String, dynamic>;
}

Future<List<OfflineSource>> offlineSourcesFromStyle(
  Map<String, dynamic> style,
  Future<Map<String, dynamic>> Function(String url) fetchJson,
) async {
  final sources = style['sources'];
  if (sources is! Map) throw const OfflineDownloadException('This map style has no tile sources');
  final out = <OfflineSource>[];
  for (final e in sources.entries) {
    final v = e.value as Map;
    final kind = switch (v['type']) {
      'vector' => OfflineKind.vector,
      'raster' => OfflineKind.raster,
      _ => null,
    };
    if (kind == null) continue;
    final url = v['url'] as String?;
    final Map src = url != null ? await fetchJson(url) : v;
    final tiles = src['tiles'];
    if (tiles is List && tiles.isNotEmpty) {
      out.add(OfflineSource(
        name: e.key as String,
        kind: kind,
        template: tiles[0] as String,
        minZoom: (src['minzoom'] as int?) ?? 1,
        maxZoom: (src['maxzoom'] as int?) ?? 14,
      ));
    }
  }
  if (out.isEmpty) throw const OfflineDownloadException('This map style has no tile sources');
  return out;
}

class ResolvedVectorStyle {
  const ResolvedVectorStyle(this.styleJson, this.sources);

  final Map<String, dynamic> styleJson;
  final List<OfflineSource> sources;
}

Future<ResolvedVectorStyle> resolveVectorStyle(
  MapStyle m,
  String userAgent, {
  Future<Map<String, dynamic>> Function(String url)? fetchJson,
}) async {
  final fetch = fetchJson ?? (u) => fetchOfflineJson(u, userAgent);
  final style = await fetch(m.url);
  return ResolvedVectorStyle(style, await offlineSourcesFromStyle(style, fetch));
}

class OfflineStore {
  OfflineStore(this.root);

  final Directory root;
  List<String>? _dirs;

  Directory get _styles => Directory('${root.path}/styles');

  Future<void> init() async {
    await root.create(recursive: true);
    await for (final e in root.list()) {
      if (e is Directory && e.path.split(Platform.pathSeparator).last.startsWith('.partial_')) {
        await e.delete(recursive: true);
      }
    }
  }

  Future<List<String>> _areaDirs() async {
    final cached = _dirs;
    if (cached != null) return cached;
    final out = <String>[];
    if (await root.exists()) {
      await for (final e in root.list()) {
        if (e is Directory && File('${e.path}/area.json').existsSync()) out.add(e.path);
      }
    }
    return _dirs = out;
  }

  Future<List<OfflineArea>> areas() async {
    final out = <OfflineArea>[];
    for (final d in await _areaDirs()) {
      final f = File('$d/area.json');
      if (!await f.exists()) continue;
      out.add(OfflineArea.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
    }
    out.sort((a, b) => b.createdMs.compareTo(a.createdMs));
    return out;
  }

  Future<Uint8List?> readTile(String name) async {
    for (final d in await _areaDirs()) {
      final f = File('$d/tiles/$name');
      if (await f.exists()) return f.readAsBytes();
    }
    return null;
  }

  Future<void> delete(OfflineArea area) async {
    final dir = Directory('${root.path}/${area.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    _dirs = null;
    final left = await areas();
    if (!left.any((a) => a.style == area.style)) {
      final f = File('${_styles.path}/${area.style}.json');
      if (await f.exists()) await f.delete();
    }
  }

  Future<ResolvedVectorStyle?> savedStyle(MapStyle m) async {
    final f = File('${_styles.path}/${m.name}.json');
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return ResolvedVectorStyle(
      j['style'] as Map<String, dynamic>,
      [for (final s in j['sources'] as List) OfflineSource.fromJson(s as Map<String, dynamic>)],
    );
  }

  Future<OfflineArea?> download(
    OfflinePlan plan, {
    required String userAgent,
    ResolvedVectorStyle? vectorStyle,
    OfflineFetch? fetch,
    void Function(int done, int total)? onProgress,
    OfflineCancel? cancel,
  }) async {
    final refusal = plan.refusal;
    if (refusal != null) throw OfflineDownloadException(refusal);
    final doFetch = fetch ?? _fetchOfflineTile;
    final headers = {'User-Agent': userAgent};
    final id = 'a_${DateTime.now().microsecondsSinceEpoch}';
    final tmp = Directory('${root.path}/.partial_$id');
    await Directory('${tmp.path}/tiles').create(recursive: true);
    final jobs = plan.tiles.toList();
    var next = 0;
    var done = 0;
    var bytes = 0;
    Object? failure;

    Future<void> worker() async {
      while (failure == null && !(cancel?.canceled ?? false)) {
        final i = next++;
        if (i >= jobs.length) return;
        final job = jobs[i];
        try {
          final data = await doFetch(job.url, headers);
          if (data != null) {
            bytes += data.length;
            if (bytes > offlineMaxBytes) {
              failure = OfflineDownloadException(
                  'This area is over ${offlineSizeLabel(offlineMaxBytes)}. Zoom in or move to a smaller area.');
              return;
            }
            await File('${tmp.path}/tiles/${job.name}').writeAsBytes(data);
          }
          done++;
          onProgress?.call(done, jobs.length);
        } catch (e) {
          failure ??= e;
          return;
        }
      }
    }

    await Future.wait([for (var i = 0; i < offlineParallel; i++) worker()]);
    if (failure != null || (cancel?.canceled ?? false)) {
      await tmp.delete(recursive: true);
      if (failure != null) throw failure!;
      return null;
    }
    final area = OfflineArea(
      id: id,
      style: plan.style.name,
      south: plan.bounds.south,
      west: plan.bounds.west,
      north: plan.bounds.north,
      east: plan.bounds.east,
      minZoom: plan.minZoom,
      maxZoom: plan.maxZoom,
      tiles: jobs.length,
      bytes: bytes,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    await File('${tmp.path}/area.json').writeAsString(jsonEncode(area.toJson()));
    if (vectorStyle != null) {
      await _styles.create(recursive: true);
      await File('${_styles.path}/${plan.style.name}.json').writeAsString(jsonEncode({
        'style': vectorStyle.styleJson,
        'sources': [for (final s in vectorStyle.sources) s.toJson()],
      }));
    }
    await tmp.rename('${root.path}/$id');
    _dirs = null;
    return area;
  }
}

Future<OfflineStore>? _sharedStore;

Future<OfflineStore> openOfflineStore() => _sharedStore ??= _openStore();

Future<OfflineStore> _openStore() async {
  final base = await getApplicationSupportDirectory();
  final store = OfflineStore(Directory('${base.path}/map_offline'));
  await store.init();
  return store;
}
