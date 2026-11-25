// Copyright (c) 2026 Luke Switzer
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/node_positions.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/triangulation.dart';
import 'package:oui_spy/core/triangulation_state.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/wardrive/wardrive_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get scanning => false;

  @override
  bool get radioListening => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _dist = Distance(roundResult: false);
const _nodes = {
  'AAAA': LatLng(10.0, 20.0),
  'BBBB': LatLng(10.0008, 20.0002),
  'CCCC': LatLng(10.0002, 20.0009),
};
const _target = LatLng(10.0004, 20.0004);

Detection _heard(String node, LatLng at) => Detection(
      id: 'x$node',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:09',
      engine: Engine.flockBle,
      method: 'oui',
      rssi: (-59 - 27 * math.log(_dist.as(LengthUnit.Meter, at, _target)) / math.ln10).round(),
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.now(),
      sourceNodeId: node,
    );

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    triangulationProvider.overrideWith((ref) => TriangulationController(
          placed: () => ref.read(nodePositionsProvider),
          settings: () => ref.read(triSettingsProvider),
          selfNode: () => ref.read(appStateProvider).nodeId,
          minInterval: Duration.zero,
        )),
  ]);
  addTearDown(container.dispose);
  container.read(appStateProvider);
  final pos = container.read(nodePositionsProvider.notifier);
  for (final e in _nodes.entries) {
    await pos.place(e.key, e.value);
  }
  final tri = container.read(triangulationProvider);
  for (final e in _nodes.entries) {
    tri.onDetection(_heard(e.key, e.value));
  }
  container.read(wardriveProvider).requestZoom(_target.latitude, _target.longitude);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.darkTheme, home: const WardriveScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  testWidgets('placed nodes and a fix show on the map with a green ring and dashed lines', (tester) async {
    final container = await _pump(tester);
    final app = container.read(appStateProvider);
    for (final id in _nodes.keys) {
      expect(find.text(app.labelForNode(id)), findsOneWidget, reason: id);
    }
    expect(find.byKey(const Key('tri-fix-02:00:00:00:00:09')), findsOneWidget);

    final rings = tester
        .widgetList<CircleLayer>(find.byType(CircleLayer))
        .expand((l) => l.circles)
        .where((c) => c.useRadiusInMeter)
        .toList();
    final fixes = container.read(triangulationProvider).fixes;
    expect(fixes, hasLength(1));
    expect(fixes.single.fix.errM, lessThan(kTriGoodErrorM));
    expect(rings.any((c) => c.borderColor == AppTheme.success && (c.radius - fixes.single.fix.errM).abs() < 3), isTrue);

    final dashed = tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .expand((l) => l.polylines)
        .where((p) => p.pattern != const StrokePattern.solid() && p.points.length == 2)
        .toList();
    expect(dashed.where((p) => p.points.last == fixes.single.fix.at), hasLength(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('turning Triangulation off hides the nodes and fixes', (tester) async {
    final container = await _pump(tester);
    final app = container.read(appStateProvider);
    expect(find.text(app.labelForNode('AAAA')), findsOneWidget);
    expect(find.byKey(const Key('tri-fix-02:00:00:00:00:09')), findsOneWidget);
    await container.read(triSettingsProvider.notifier).setEnabled(false);
    await tester.pump();
    expect(find.text(app.labelForNode('AAAA')), findsNothing);
    expect(find.byKey(const Key('tri-fix-02:00:00:00:00:09')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a fix with a large error is drawn amber', (tester) async {
    final container = await _pump(tester);
    final tri = container.read(triangulationProvider);
    final far = Detection(
      id: 'far',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:00:00:00:0A',
      engine: Engine.flockBle,
      method: 'oui',
      rssi: -45,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.now(),
      sourceNodeId: 'AAAA',
    );
    tri.onDetection(far);
    tri.onDetection(far.copyWith(sourceNodeId: 'BBBB', rssi: -110));
    tri.onDetection(far.copyWith(sourceNodeId: 'CCCC', rssi: -45));
    final bad = tri.fixes.firstWhere((f) => f.mac == '02:00:00:00:00:0A');
    expect(bad.fix.errM, greaterThanOrEqualTo(kTriGoodErrorM));
    await tester.pump();
    final rings = tester.widgetList<CircleLayer>(find.byType(CircleLayer)).expand((l) => l.circles).toList();
    expect(rings.any((c) => c.useRadiusInMeter && c.borderColor == AppTheme.warning), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
