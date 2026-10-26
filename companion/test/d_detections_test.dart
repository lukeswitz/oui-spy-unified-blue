import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/detections/detections_screen.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_tabs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get radioListening => false;

  @override
  String get name => 'test';

  @override
  Stream<Observation> get observations => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Detection _det({String mac = '00:25:DF:00:00:01', String ssid = 'MyNetwork'}) => Detection(
      id: 'x',
      sessionId: 's',
      nodeId: 'n',
      macAddress: mac,
      engine: Engine.flockWifi,
      method: 'wildcard_probe',
      rssi: -60,
      channel: 6,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.now(),
      ssid: ssid,
      sourceNodeId: 'AABBCC',
      flock: const FlockExtension(signals: FlockSignal.name),
      wardrive: const WardriveExtension(authMode: 3),
    );

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
}

Future<void> _pumpRow(WidgetTester tester, Detection d, {double width = 360}) async {
  final container = await _container();

  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: DetectionRow(detection: d)),
    ),
  ));
  await tester.pump();
}

Future<void> _release(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.read(deviceRegistryProvider).dispose();
}

bool _hasLeftBorder(Widget w) {
  if (w is! DecoratedBox) return false;
  final deco = w.decoration;
  if (deco is! BoxDecoration) return false;
  final b = deco.border;
  return b is Border && b.left.style == BorderStyle.solid &&
      b.left.width > 0 &&
      b.right.style == BorderStyle.none;
}

void main() {
  testWidgets('detections shows underline tabs and Devices switches the view', (tester) async {
    final container = await _container();

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DetectionsScreen()),
    ));
    await tester.pump();
    expect(find.text('Detections'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byType(SegmentedButton<DetectionsView>), findsNothing);
    expect(container.read(detectionsViewProvider), DetectionsView.live);
    await tester.tap(find.text('Devices'));
    await tester.pump();
    expect(container.read(detectionsViewProvider), DetectionsView.devices);
    await _release(tester, container);
  });

  testWidgets('feed header keeps filter, sort, and more; more sheet keeps its actions', (tester) async {
    final container = await _container();

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DetectionsScreen()),
    ));
    await tester.pump();
    expect(find.byTooltip('Filter'), findsOneWidget);
    expect(find.byTooltip('Sort: TIME'), findsOneWidget);
    expect(find.byTooltip('History'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('HIDE STATS'), findsOneWidget);
    expect(find.text('SEARCH'), findsOneWidget);
    expect(find.text('EXPORT CSV'), findsOneWidget);
    expect(find.text('CLEAR FEED'), findsOneWidget);
    await _release(tester, container);
  });

  testWidgets('detection row shows auth pill, confidence, node, police icon, and square', (tester) async {
    await _pumpRow(tester, _det());
    expect(find.text('WPA2'), findsOneWidget);
    expect(find.text('High (Flock Probe Captured)'), findsOneWidget);
    expect(find.textContaining('OUISPY'), findsOneWidget);
    expect(find.byIcon(Icons.local_police), findsOneWidget);
    final square = find.byWidgetPredicate((w) =>
        w is Container &&
        w.color == Engine.flockWifi.color &&
        w.constraints?.maxWidth == 8 &&
        w.constraints?.maxHeight == 8);
    expect(square, findsOneWidget);
    expect(find.byWidgetPredicate(_hasLeftBorder), findsNothing);
  });

  testWidgets('underline tab hit area is at least 48 high', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: DUnderlineTabs<int>(items: const [(0, 'ONE'), (1, 'TWO')], selected: 0, onSelect: (_) {}),
      ),
    ));
    final hit = find.ancestor(of: find.text('ONE'), matching: find.byType(GestureDetector)).first;
    expect(tester.getSize(hit).height, greaterThanOrEqualTo(48));
  });

  test('SHARE LAST PCAP button has no color overrides', () {
    final src = File('lib/features/pcap/pcap_screen.dart').readAsStringSync();
    final i = src.indexOf("'SHARE LAST PCAP'");
    final block = src.substring(i, src.indexOf(');', i));
    expect(block.contains('AppTheme.accent'), isFalse);
    expect(block.contains('Colors.black'), isFalse);
  });

  testWidgets('row with a 40 character SSID does not overflow at 320', (tester) async {
    await _pumpRow(tester, _det(ssid: 'MyNetwork-with-a-very-long-ssid-name-123'), width: 320);
    expect(tester.takeException(), isNull);
  });
}
