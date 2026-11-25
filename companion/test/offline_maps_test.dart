// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:oui_spy/core/offline/offline_maps.dart';
import 'package:oui_spy/features/wardrive/offline_download_dialog.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

final _bounds = LatLngBounds(const LatLng(10.0, 20.0), const LatLng(10.5, 20.5));

const _vectorSource = OfflineSource(
  name: 'openmaptiles',
  kind: OfflineKind.vector,
  template: 'https://tiles.example/planet/{z}/{x}/{y}.pbf',
  minZoom: 0,
  maxZoom: 14,
);

const _rasterSource = OfflineSource(
  name: 'ne2_shaded',
  kind: OfflineKind.raster,
  template: 'https://tiles.example/ne2/{z}/{x}/{y}.png',
  minZoom: 1,
  maxZoom: 6,
);

OfflineSource _layerSource({int minZoom = 0, int maxZoom = 16}) => OfflineSource(
      name: 'tiles',
      kind: OfflineKind.layer,
      template: 'https://tiles.example/{z}/{y}/{x}',
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

LatLngBounds _boundsForTiles(int z, int x0, int x1, int y0, int y1) {
  final n = 1 << z;
  double lon(num x) => x / n * 360 - 180;
  double lat(num y) => atan(_sinh(pi * (1 - 2 * y / n))) * 180 / pi;
  return LatLngBounds(LatLng(lat(y1 + 0.5), lon(x0 + 0.5)), LatLng(lat(y0 + 0.5), lon(x1 + 0.5)));
}

double _sinh(double v) => (exp(v) - exp(-v)) / 2;

OfflinePlan _smallPlan({MapStyle style = MapStyle.satellite, List<OfflineSource>? sources, double zoom = 12}) =>
    OfflinePlan.build(style: style, sources: sources ?? [_layerSource()], bounds: _bounds, zoom: zoom);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tile math', () {
    test('known points map to the standard slippy tiles', () {
      expect((lonToTileX(0, 2), latToTileY(0, 2)), (2, 2));
      expect((lonToTileX(20.0, 12), latToTileY(10.0, 12)), (2275, 1933));
      expect((lonToTileX(20.0, 16), latToTileY(10.0, 16)), (36408, 30938));
      expect((lonToTileX(20.0, 6), latToTileY(10.0, 6)), (35, 30));
    });

    test('a bounds becomes an inclusive tile range', () {
      final r = tileRangeFor(_bounds, 12);
      expect((r.x0, r.x1, r.y0, r.y1), (2275, 2281, 1927, 1933));
      expect(r.count, 49);
    });

    test('the whole world at zoom 1 is four tiles and edges clamp', () {
      final world = LatLngBounds(const LatLng(-90, -180), const LatLng(90, 180));
      expect(tileRangeFor(world, 1).count, 4);
      expect(tileRangeFor(world, 0).count, 1);
    });
  });

  group('plan', () {
    test('zoom range is the current zoom up to plus 3, capped by the provider max', () {
      final p = _smallPlan(zoom: 12.7);
      expect((p.minZoom, p.maxZoom), (12, 15));
      final nearCap = _smallPlan(zoom: 15.2);
      expect((nearCap.minZoom, nearCap.maxZoom), (15, 16));
      final past = _smallPlan(zoom: 19);
      expect((past.minZoom, past.maxZoom), (16, 16));
    });

    test('a vector style counts each source once per effective zoom', () {
      final p = _smallPlan(style: MapStyle.liberty, sources: [_rasterSource, _vectorSource], zoom: 12.3);
      expect((p.minZoom, p.maxZoom), (12, 14));
      final vector = [12, 13, 14].fold<int>(0, (n, z) => n + tileRangeFor(_bounds, z).count);
      expect(p.tileCount, vector + tileRangeFor(_bounds, 6).count);
      expect(p.tiles.length, p.tileCount);
      expect(p.tiles.map((t) => t.name).toSet().length, p.tileCount);
    });

    test('the 3,000 tile cap refuses with a reason', () {
      OfflinePlan at(int rows) => OfflinePlan.build(
            style: MapStyle.satellite,
            sources: [_layerSource(minZoom: 10, maxZoom: 10)],
            bounds: _boundsForTiles(10, 100, 149, 200, 200 + rows - 1),
            zoom: 10,
          );
      expect(at(60).tileCount, 3000);
      expect(at(60).refusal, isNull);
      expect(at(61).tileCount, 3050);
      expect(at(61).refusal, contains('3000'));
    });

    test('download refuses an over-cap plan', () async {
      final tmp = await Directory.systemTemp.createTemp('offline');
      addTearDown(() => tmp.delete(recursive: true));
      final store = OfflineStore(Directory('${tmp.path}/o'))..root.createSync();
      final plan = OfflinePlan.build(
        style: MapStyle.satellite,
        sources: [_layerSource(minZoom: 10, maxZoom: 10)],
        bounds: _boundsForTiles(10, 100, 149, 200, 260),
        zoom: 10,
      );
      await expectLater(store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List(1)),
          throwsA(isA<OfflineDownloadException>()));
    });
  });

  group('provider allowlist', () {
    test('only OpenFreeMap styles and USGS satellite may be saved', () {
      const allowed = {'dark', 'fiord', 'liberty', 'bright', 'positron', 'satellite'};
      for (final s in MapStyle.values) {
        expect(offlineAllowed(s), allowed.contains(s.name), reason: s.name);
      }
      for (final s in [
        MapStyle.osm,
        MapStyle.satelliteWorld,
        MapStyle.terrain,
        MapStyle.openTopo,
        MapStyle.cartoDark,
        MapStyle.cartoLight,
        MapStyle.cartoVoyager,
      ]) {
        expect(_smallPlan(style: s).refusal, offlineRefusal, reason: s.name);
      }
      expect(offlineRefusal, "This map's provider does not allow offline downloads");
    });

    test('allowed styles point at the providers that permit it', () {
      for (final s in MapStyle.values.where(offlineAllowed)) {
        final host = Uri.parse(s.url).host;
        expect(host == 'tiles.openfreemap.org' || host == 'basemap.nationalmap.gov', isTrue, reason: s.name);
      }
    });
  });

  group('sources', () {
    test('a style resolves inline and TileJSON sources like the map does', () async {
      final fetched = <String>[];
      final sources = await offlineSourcesFromStyle({
        'sources': {
          'ne2_shaded': {
            'type': 'raster',
            'maxzoom': 6,
            'tiles': ['https://tiles.example/ne2/{z}/{x}/{y}.png'],
          },
          'openmaptiles': {'type': 'vector', 'url': 'https://tiles.example/planet'},
          'dem': {'type': 'raster-dem', 'url': 'https://tiles.example/dem'},
        },
      }, (url) async {
        fetched.add(url);
        return {
          'tiles': ['https://tiles.example/planet/v1/{z}/{x}/{y}.pbf'],
          'maxzoom': 14,
          'minzoom': 0,
        };
      });
      expect(fetched, ['https://tiles.example/planet']);
      expect(sources.map((s) => (s.name, s.kind, s.minZoom, s.maxZoom)), [
        ('ne2_shaded', OfflineKind.raster, 1, 6),
        ('openmaptiles', OfflineKind.vector, 0, 14),
      ]);
    });

    test('the satellite URL is the one the live tile layer requests', () async {
      final r = await resolveOfflineSources(MapStyle.satellite, 'OUI-APEX/0');
      final s = r.sources.single;
      expect(s.maxZoom, 16);
      expect(r.vectorStyle, isNull);
      expect(s.urlFor(16, 36408, 30938),
          'https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/16/30938/36408');
    });
  });

  group('store', () {
    late Directory tmp;
    late OfflineStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('offline');
      store = OfflineStore(Directory('${tmp.path}/offline'));
      await store.init();
    });
    tearDown(() => tmp.delete(recursive: true));

    test('download saves every tile with the app user agent, 4 at a time, and reports progress', () async {
      final plan = _smallPlan();
      final seen = <Map<String, String>>[];
      var inFlight = 0;
      var peak = 0;
      final progress = <int>[];
      final area = await store.download(
        plan,
        userAgent: offlineUserAgent('0.7.0'),
        fetch: (url, headers) async {
          seen.add(headers);
          inFlight++;
          peak = max(peak, inFlight);
          await Future<void>.delayed(const Duration(milliseconds: 2));
          inFlight--;
          return Uint8List.fromList(url.codeUnits);
        },
        onProgress: (d, t) => progress.add(d),
      );
      expect(area, isNotNull);
      expect(area!.tiles, plan.tileCount);
      expect(peak, offlineParallel);
      expect(seen.every((h) => h['User-Agent'] == 'OUI-APEX/0.7.0'), isTrue);
      expect(progress.last, plan.tileCount);
      expect(await store.areas(), hasLength(1));
      final first = plan.tiles.first;
      expect(await store.readTile(first.name), first.url.codeUnits);
      expect(await store.readTile('missing'), isNull);
      expect(area.bytes, plan.tiles.fold<int>(0, (n, t) => n + t.url.length));
    });

    test('a 404 tile is skipped and any other failure discards the partial area', () async {
      final plan = _smallPlan();
      final skipped = await store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => null);
      expect(skipped!.bytes, 0);
      expect(skipped.tiles, plan.tileCount);

      await expectLater(
        store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => throw const SocketException('down')),
        throwsA(isA<SocketException>()),
      );
      expect(await store.areas(), hasLength(1));
      expect(store.root.listSync().whereType<Directory>().where((d) => d.path.contains('.partial_')), isEmpty);
    });

    test('a download over 50 MB stops and leaves nothing behind', () async {
      final plan = _smallPlan();
      await expectLater(
        store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List(20 * 1024 * 1024)),
        throwsA(isA<OfflineDownloadException>().having((e) => e.message, 'message', contains('50.0 MB'))),
      );
      expect(await store.areas(), isEmpty);
      expect(store.root.listSync().whereType<Directory>().where((d) => d.path.contains('.partial_')), isEmpty);
    });

    test('cancel stops the download and leaves nothing behind', () async {
      final cancel = OfflineCancel();
      var calls = 0;
      final area = await store.download(
        _smallPlan(),
        userAgent: 'OUI-APEX/0',
        cancel: cancel,
        fetch: (u, h) async {
          if (++calls == 5) cancel.canceled = true;
          return Uint8List(1);
        },
      );
      expect(area, isNull);
      expect(await store.areas(), isEmpty);
      expect(store.root.listSync().whereType<Directory>().where((d) => d.path.contains('.partial_')), isEmpty);
    });

    test('deleting an area removes its tiles and leaves other areas alone', () async {
      final a = (await store.download(_smallPlan(), userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List(3)))!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final b = (await store.download(_smallPlan(zoom: 8), userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List(4)))!;
      final tileOfA = _smallPlan().tiles.first.name;
      await store.delete(a);
      expect((await store.areas()).map((x) => x.id), [b.id]);
      expect(await store.readTile(tileOfA), isNull);
      expect(await store.readTile(_smallPlan(zoom: 8).tiles.first.name), [0, 0, 0, 0]);
    });

    test('pruneTileCache never touches the offline folder', () async {
      final plan = _smallPlan();
      await store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List.fromList([7, 7]));
      final old = DateTime.now().subtract(const Duration(days: 400));
      final files = store.root.listSync(recursive: true).whereType<File>().toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        await f.setLastModified(old);
      }
      final cache = Directory('${tmp.path}/cache')..createSync();
      File('${cache.path}/stale').writeAsBytesSync([1]);
      File('${cache.path}/stale').setLastModifiedSync(old);
      Directory('${cache.path}/nested').createSync();
      File('${cache.path}/nested/kept').writeAsBytesSync([1]);

      await pruneTileCache(cache, DateTime.now(), maxBytes: 0);
      await pruneTileCache(store.root, DateTime.now(), maxBytes: 0);

      expect(File('${cache.path}/stale').existsSync(), isFalse);
      expect(File('${cache.path}/nested/kept').existsSync(), isTrue);
      expect(store.root.listSync(recursive: true).whereType<File>().length, files.length);
      expect(await store.readTile(plan.tiles.first.name), [7, 7]);
    });

    test('the raster provider reads saved tiles first, even when the network is down', () async {
      final plan = _smallPlan();
      await store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List.fromList([9, 9, 9]));
      final cache = Directory('${tmp.path}/cache')..createSync();
      final tile = plan.tiles.first;
      final bytes = await cachedTileBytes(
        cache,
        tile.url,
        const {},
        offline: store,
        fetch: (u, h) async => throw const SocketException('offline'),
      );
      expect(bytes, [9, 9, 9]);
      expect(cache.listSync(), isEmpty);
      await expectLater(
        cachedTileBytes(cache, 'https://basemap.nationalmap.gov/other', const {},
            offline: store, fetch: (u, h) async => throw const SocketException('offline')),
        throwsA(isA<SocketException>()),
      );
    });

    test('the vector provider reads saved tiles first and falls through to the network', () async {
      final plan = _smallPlan(style: MapStyle.liberty, sources: [_vectorSource], zoom: 12);
      await store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List.fromList([5, 6]));
      final delegate = _FakeProvider();
      final p = OfflineFirstTileProvider(delegate, store, 'openmaptiles');
      final r = tileRangeFor(_bounds, 12);
      expect(await p.provide(TileIdentity(12, r.x0, r.y0)), [5, 6]);
      expect(delegate.calls, 0);
      expect(await p.provide(TileIdentity(3, 1, 1)), [1]);
      expect(delegate.calls, 1);
      expect((p.minimumZoom, p.maximumZoom, p.type), (0, 14, TileProviderType.vector));
    });

    test('a saved vector style comes back as a style with offline-first providers', () async {
      final json = {
        'version': 8,
        'sources': {
          'openmaptiles': {'type': 'vector', 'url': 'https://tiles.example/planet'},
        },
        'layers': [
          {
            'id': 'bg',
            'type': 'background',
            'paint': {'background-color': 'transparent'},
          },
        ],
      };
      final resolved = ResolvedVectorStyle(json, [_vectorSource]);
      final plan = _smallPlan(style: MapStyle.liberty, sources: [_vectorSource], zoom: 12);
      await store.download(plan,
          userAgent: 'OUI-APEX/0', vectorStyle: resolved, fetch: (u, h) async => Uint8List.fromList([5]));
      final saved = await store.savedStyle(MapStyle.liberty);
      expect(saved, isNotNull);
      expect(await store.savedStyle(MapStyle.dark), isNull);
      final style = savedOfflineStyle(saved!, store);
      expect(style.providers.get('openmaptiles'), isA<OfflineFirstTileProvider>());
      expect(style.theme.layers, isNotEmpty);
      final area = (await store.areas()).single;
      await store.delete(area);
      expect(await store.savedStyle(MapStyle.liberty), isNull);
    });
  });

  group('dialog', () {
    Future<void> open(WidgetTester tester, List<OfflineSource> sources, LatLngBounds bounds, double zoom,
        {MapStyle style = MapStyle.satellite, OfflineResolver? resolve, List<String>? agents}) async {
      PackageInfo.setMockInitialValues(
          appName: 'x', packageName: 'x', version: '9.9.9', buildNumber: '1', buildSignature: '');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OfflineDownloadDialog(
            style: style,
            bounds: bounds,
            zoom: zoom,
            resolve: resolve ??
                (m, ua) async {
                  agents?.add(ua);
                  return (sources: sources, vectorStyle: null);
                },
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows style, zoom range, tile count and size, and enables SAVE', (tester) async {
      final agents = <String>[];
      await open(tester, [_layerSource()], _bounds, 12, agents: agents);
      expect(find.text('Satellite (US)'), findsOneWidget);
      expect(find.text('12 to 15'), findsOneWidget);
      final plan = _smallPlan();
      expect(find.text(NumberFormat.decimalPattern().format(plan.tileCount)), findsOneWidget);
      expect(find.textContaining('Estimated size'), findsOneWidget);
      expect(agents, ['OUI-APEX/9.9.9']);
      final save = tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE'));
      expect(save.onPressed, isNotNull);
    });

    testWidgets('over 3,000 tiles shows the reason and disables SAVE', (tester) async {
      await open(tester, [_layerSource(minZoom: 10, maxZoom: 10)], _boundsForTiles(10, 100, 149, 200, 260), 10);
      expect(find.textContaining('The limit is 3000'), findsOneWidget);
      final save = tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE'));
      expect(save.onPressed, isNull);
    });

    testWidgets('a provider that does not allow downloads is refused with the one-line reason', (tester) async {
      await open(tester, [_layerSource()], _bounds, 12, style: MapStyle.osm);
      expect(find.text(offlineRefusal), findsOneWidget);
      final save = tester.widget<TextButton>(find.widgetWithText(TextButton, 'SAVE'));
      expect(save.onPressed, isNull);
    });

    testWidgets('a failed source lookup is shown instead of a spinner', (tester) async {
      await open(tester, const [], _bounds, 12, resolve: (m, ua) async => throw const OfflineDownloadException('No network'));
      expect(find.text('No network'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'SAVE'), findsNothing);
    });
  });
}

class _FakeProvider extends VectorTileProvider {
  int calls = 0;

  @override
  int get maximumZoom => 14;

  @override
  int get minimumZoom => 0;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    calls++;
    return Uint8List.fromList([1]);
  }
}
