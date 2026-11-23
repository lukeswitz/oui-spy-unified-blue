import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/services/faa_service.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/theme/app_theme.dart';
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

Detection _det({
  String mac = '02:00:00:00:00:01',
  double? lat,
  double? lon,
  OdidExtension? odid,
  bool flock = true,
}) =>
    Detection(
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
      ssid: 'MyNetwork',
      sourceNodeId: 'AABBCC',
      latitude: lat,
      longitude: lon,
      flock: flock ? const FlockExtension(signals: FlockSignal.name) : null,
      wardrive: const WardriveExtension(authMode: 3),
      odid: odid,
    );

class _FakeFaa extends FaaService {
  @override
  Future<FaaRegistration?> lookup(String uasId) async => FaaRegistration(
        status: 'Accepted',
        brand: 'b',
        model: 'm',
        manufacturerCode: '',
        productType: '',
        operationRules: '',
        makeName: '',
        modelName: '',
        series: '',
        trackingNumber: '',
        complianceCategories: '',
        updatedAt: '',
        cachedAt: DateTime.now(),
      );
}

Future<ProviderContainer> _open(WidgetTester tester, Detection d,
    {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    ...overrides,
  ]);
  await tester.binding.setSurfaceSize(const Size(360, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showDetectionDetails(context, ref, d),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _release(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.read(deviceRegistryProvider).dispose();
}

void main() {
  testWidgets('header block is fill and the engine chip is the marker color', (tester) async {
    final d = _det();
    final container = await _open(tester, d);
    final p = AppTheme.of(tester.element(find.byKey(const Key('detail-header'))));
    final header = tester.widget<Container>(find.byKey(const Key('detail-header')));
    expect((header.decoration as BoxDecoration?)?.color ?? header.color, p.fill);
    final chip = tester.widget<Container>(find.byKey(const Key('detail-engine-chip')));
    expect((chip.decoration as BoxDecoration?)?.color ?? chip.color, d.engine.color);
    await _release(tester, container);
  });

  testWidgets('a drone chip says DRONE', (tester) async {
    final container = await _open(tester,
        _det(flock: false, odid: const OdidExtension(uavId: 'UAV1')).copyWith(engine: Engine.skySpy));
    expect(find.descendant(of: find.byKey(const Key('detail-engine-chip')), matching: find.text('DRONE')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('detail-type-icon')), matching: find.byType(SvgPicture)),
        findsOneWidget);
    await _release(tester, container);
  });

  testWidgets('a UniPwn hit shows robot, serial and exploited state', (tester) async {
    final container = await _open(
        tester,
        _det(flock: false).copyWith(
            engine: Engine.uniPwn,
            method: 'unitree_ble',
            unipwn: const UnipwnExtension(robotType: 'go2', serialNumber: 'SN1', exploited: true)));
    for (final s in ['Robot', 'GO2', 'Serial', 'SN1', 'Exploited', 'Yes']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await _release(tester, container);
  });

  testWidgets('the chip shows the same icon as the map pin', (tester) async {
    final container = await _open(tester, _det());
    final icon = tester.widget<Icon>(
        find.descendant(of: find.byKey(const Key('detail-type-icon')), matching: find.byType(Icon)));
    expect(icon.icon, Icons.videocam);
    await _release(tester, container);
  });

  testWidgets('every field label stays, in order', (tester) async {
    final container = await _open(tester, _det());
    const labels = [
      'Engine',
      'Method',
      'RSSI',
      'Channel',
      'Seen',
      'Source Node',
      'SSID',
      'Security',
      'Confidence',
      'Signals',
    ];
    double last = -1;
    for (final l in labels) {
      expect(find.text(l), findsOneWidget, reason: l);
      final y = tester.getTopLeft(find.text(l)).dy;
      expect(y, greaterThan(last), reason: l);
      last = y;
    }
    await _release(tester, container);
  });

  testWidgets('tapping a value row copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final container = await _open(tester, _det());
    await tester.ensureVisible(find.text('Channel'));
    await tester.pump();
    await tester.tap(find.text('Channel'));
    await tester.pump();
    expect(copied, '6');
    expect(find.text('Channel copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Channel copied'), findsNothing);
    await _release(tester, container);
  });

  testWidgets('Flock engine detection is described as a Flock Safety device', (tester) async {
    final container = await _open(tester, _det());
    expect(find.text('Flock Safety device'), findsOneWidget);
    expect(find.text('Matched by PROBE REQ.'), findsOneWidget);
    expect(find.text('Probably a Wi-Fi access point'), findsNothing);
    await _release(tester, container);
  });

  testWidgets('foxhunt present for an Axon MAC; map only with GPS', (tester) async {
    var container = await _open(tester, _det(mac: '00:25:DF:00:00:01'));
    expect(find.text('Foxhunt this device'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Map'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Copy'), findsOneWidget);
    await _release(tester, container);

    container = await _open(tester, _det(lat: 1.5, lon: 2.5));
    expect(find.widgetWithText(OutlinedButton, 'Map'), findsOneWidget);
    await _release(tester, container);
  });

  testWidgets('FAA lookup row only for a drone with a uavId', (tester) async {
    var container = await _open(tester, _det());
    expect(find.text('FAA RemoteID Lookup'), findsNothing);
    await _release(tester, container);

    container = await _open(
        tester, _det(flock: false, odid: const OdidExtension(uavId: 'UAV123')));
    expect(find.text('FAA RemoteID Lookup'), findsOneWidget);
    await _release(tester, container);
  });

  testWidgets('FAA copy message text uses textPrimary', (tester) async {
    final container = await _open(
      tester,
      _det(flock: false, odid: const OdidExtension(uavId: 'UAV123')),
      overrides: [faaServiceProvider.overrideWith((ref) => _FakeFaa())],
    );
    await tester.ensureVisible(find.text('FAA RemoteID Lookup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FAA RemoteID Lookup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pump();
    final t = AppTheme.of(tester.element(find.text('Status copied')));
    final text = tester.widget<Text>(find.text('Status copied'));
    expect(text.style?.color, t.textPrimary);
    await tester.pump(const Duration(seconds: 2));
    await _release(tester, container);
  });

  testWidgets('delete button foreground is the error color', (tester) async {
    final container = await _open(tester, _det());
    final btn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Delete'));
    expect(btn.style?.foregroundColor?.resolve(<WidgetState>{}), AppTheme.error);
    await _release(tester, container);
  });
}
