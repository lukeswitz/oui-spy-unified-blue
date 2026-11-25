// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/radio_classifier.dart';
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
  testWidgets('row shows the seen count, Flock confidence line and source node', (tester) async {
    await _pumpRow(tester, _det().copyWith(count: 7));
    expect(find.textContaining('×7', findRichText: true), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    final app = ProviderScope.containerOf(tester.element(find.byType(DetectionRow))).read(appStateProvider);
    expect(find.text(app.labelForNode('AABBCC')), findsOneWidget);
    await _pumpRow(tester, _det().copyWith(flock: const FlockExtension(signals: FlockSignal.oui)));
    expect(find.text('Suspected (Known OUI)'), findsOneWidget);
    expect(find.textContaining('×', findRichText: true), findsNothing);
  });

  test('name sort key is the shown name: SSID for WiFi, MAC when unnamed', () {
    final wifi = _det(ssid: '').copyWith(wardrive: const WardriveExtension(ssid: 'Zulu'));
    final bare = _det(mac: '02:00:00:00:00:01', ssid: '').copyWith(wardrive: null, deviceName: '');
    expect(detectionHeadline(wifi), 'Zulu');
    expect(detectionHeadline(bare), '02:00:00:00:00:01');
    expect(detectionHasName(wifi), isTrue);
    expect(detectionHasName(bare), isFalse);
    final hidden = bare.copyWith(method: 'wifi_ap');
    expect(detectionIsHiddenAp(hidden), isTrue);
    expect(detectionHeadline(hidden), 'Hidden network');
    expect(detectionIsHiddenAp(wifi.copyWith(method: 'wifi_ap')), isFalse);
  });

  test('an SDR decode is neither a Bluetooth nor a WiFi device', () {
    final d = _det(mac: 'SilverSpring-Mesh|0000000000000001', ssid: '{}')
        .copyWith(engine: Engine.sdr, method: 'rtl433', channel: 0, wardrive: null);
    expect(d.isBleDetection, isFalse);
    expect(d.isWifiDetection, isFalse);
    expect(_det().isWifiDetection, isTrue);
  });

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
    await tester.tap(find.byTooltip('Detections guide'));
    await tester.pumpAndSettle();
    expect(find.text('Detections guide'), findsOneWidget);
    expect(find.textContaining('Layers indents Wi-Fi clients'), findsOneWidget);
    Navigator.of(tester.element(find.text('Detections guide'))).pop();
    await tester.pumpAndSettle();
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

  testWidgets('sort opens at the top; SSID grouping turns on and back off', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final (ch, v) in const [
      ('plugins.flutter.io/path_provider', '.'),
      ('plugins.it_nomads.com/flutter_secure_storage', null),
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(ch), (c) async => v);
      addTearDown(() => messenger.setMockMethodCallHandler(MethodChannel(ch), null));
    }
    final container = await _container();
    final app = container.read(appStateProvider);
    final ble = container.read(bleManagerProvider);
    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:01', 'MyNetwork', -80, 1, 3);
    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:02', 'MyNetwork', -70, 6, 3);
    ble.addPhoneWifiDetection('0a:bb:cc:dd:ee:09', '', -60, 1, 0, client: true, ap: '0A:BB:CC:DD:EE:01');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(app.recentDetections, hasLength(3));
    final indented = find.byWidgetPredicate(
        (w) => w is Padding && w.padding == const EdgeInsets.only(left: 28) && w.child is DetectionRow);

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const DetectionsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Sort: TIME'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('SORT')).dy, lessThan(200));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('SORT'), findsNothing);

    expect(find.byType(DetectionRow), findsNWidgets(2));
    expect(indented, findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GROUP CLIENTS'));
    await tester.pumpAndSettle();
    expect(find.byType(DetectionRow), findsNWidgets(2));
    expect(indented, findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UNGROUP CLIENTS'));
    await tester.pumpAndSettle();
    expect(find.byType(DetectionRow), findsNWidgets(2));
    expect(indented, findsNothing);
    expect(container.read(sharedPreferencesProvider).getBool('feedGroupBySsid'), isFalse);
    await tester.tap(find.byTooltip('Group clients'));
    await tester.pumpAndSettle();
    expect(indented, findsOneWidget);
    await tester.tap(find.byTooltip('Ungroup clients'));
    await tester.pumpAndSettle();
    expect(indented, findsNothing);
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Group clients'), findsOneWidget);
    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();

    ble.addPhoneDetection('AA:BB:CC:DD:EE:09', 'Newest BLE', -50, const []);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
    final rows = tester.widgetList<DetectionRow>(find.byType(DetectionRow)).map((r) => r.detection.isBleDetection).toList();
    expect(rows, [false, false, true]);
    await _release(tester, container);
  });

  testWidgets('detection row shows auth next to the name, police icon, no left border', (tester) async {
    await _pumpRow(tester, _det());
    expect(find.text('WPA2'), findsOneWidget);
    expect(find.byIcon(Icons.local_police), findsOneWidget);
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
