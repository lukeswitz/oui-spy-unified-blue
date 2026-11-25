// Copyright (c) 2026 Luke Switzer
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:oui_spy/core/offline/offline_maps.dart';
import 'package:oui_spy/features/config/saved_map_areas_section.dart';
import 'package:oui_spy/theme/app_theme.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
  }
  await tester.pump();
}

void main() {
  testWidgets('saved areas list with size and delete removes the area', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('areas');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = OfflineStore(Directory('${tmp.path}/offline'));
    await tester.runAsync(() async {
      await store.init();
      final plan = OfflinePlan.build(
        style: MapStyle.satellite,
        sources: const [
          OfflineSource(
              name: 'tiles', kind: OfflineKind.layer, template: 'https://tiles.example/{z}/{y}/{x}', minZoom: 0, maxZoom: 16),
        ],
        bounds: LatLngBounds(const LatLng(10.0, 20.0), const LatLng(10.01, 20.01)),
        zoom: 12,
      );
      await store.download(plan, userAgent: 'OUI-APEX/0', fetch: (u, h) async => Uint8List(2048));
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SavedMapAreasSection(storeOpener: () async => store)),
    ));
    await settle(tester);
    expect(find.text('Saved map areas'), findsOneWidget);
    expect(find.text('Satellite (US), zoom 12 to 15'), findsOneWidget);
    expect(find.byTooltip('Delete this saved area'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete this saved area'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await settle(tester);
    expect(find.text('None'), findsOneWidget);
    expect(find.byTooltip('Delete this saved area'), findsNothing);
    expect(await tester.runAsync(store.areas), isEmpty);
  });
}
