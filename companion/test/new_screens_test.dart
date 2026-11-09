import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/trusted_networks.dart';
import 'package:oui_spy/features/alerts/alerts_view.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:oui_spy/features/detections/detections_screen.dart';
import 'package:oui_spy/features/devices/suggestions_sheet.dart';
import 'package:oui_spy/features/signatures/user_signatures_screen.dart';
import 'package:oui_spy/features/stops/stops_screen.dart';
import 'package:oui_spy/features/trusted/trusted_networks_screen.dart';
import 'package:oui_spy/features/wardrive/wardrive_report_screen.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
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

Future<(ProviderContainer, AppDatabase)> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  return (
    ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    ]),
    db,
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: AppTheme.darkTheme, home: home),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Detection & alerts lists the new rows and moves long text behind info buttons', (tester) async {
    final (c, db) = await _container();
    await _pump(tester, c, const DeviceConfigScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detection & alerts'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('About detection & alerts'), findsOneWidget);
    final list = find.ancestor(of: find.text('Wi-Fi beacon floods'), matching: find.byType(Scrollable)).first;
    for (final label in [
      'Wi-Fi beacon floods',
      'Drone loitering',
      'Aircraft circling you',
      'Car following you',
      'Crossing your mesh',
      'About Privacy screen',
      'About Alert threshold',
      'My signatures',
      'Trusted networks',
    ]) {
      final target = label.startsWith('About ') ? find.byTooltip(label) : find.text(label);
      await tester.scrollUntilVisible(target, 200, scrollable: list);
      expect(target, findsOneWidget, reason: label);
    }
    expect(find.textContaining('Display only. The database'), findsNothing);
    await tester.scrollUntilVisible(find.byTooltip('About Alert threshold'), -200, scrollable: list);
    await tester.tap(find.byTooltip('About Alert threshold'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified: two independent signals'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets('Alerts tab lists alerts, opens one, and deletes it', (tester) async {
    final (c, db) = await _container();
    await tester.runAsync(() async {
      await db.insertClassAlert(
        macAddress: 'GPS',
        deviceName: '',
        alertClass: 'gps_watch',
        title: 'GPS warning',
        reason: 'An app on this phone is setting the GPS location',
        isBle: false,
        rssi: 0,
        channel: 0,
        alertedAt: DateTime.now().millisecondsSinceEpoch,
      );
    });
    await _pump(tester, c, const Scaffold(body: AlertsView()));
    await _settle(tester);
    expect(find.text('GPS warning'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);
    await tester.tap(find.text('GPS warning'));
    await tester.pumpAndSettle();
    expect(find.text('Device details'), findsNothing);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(find.text('No alerts yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  for (final width in [360.0, 430.0]) {
    testWidgets('all four Detections tabs fit at $width px in the real fonts with big counts', (tester) async {
      for (final (family, files) in [
        ('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf']),
        ('JetBrainsMono', ['JetBrainsMono-Regular.ttf', 'JetBrainsMono-Medium.ttf']),
      ]) {
        final loader = FontLoader(family);
        for (final f in files) {
          loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
        }
        await loader.load();
      }
      await tester.binding.setSurfaceSize(Size(width, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DUnderlineTabs<DetectionsView>(
              items: const [
                (DetectionsView.live, 'Live'),
                (DetectionsView.devices, 'Devices'),
                (DetectionsView.history, 'History'),
                (DetectionsView.alerts, 'Alerts'),
              ],
              selected: DetectionsView.live,
              counts: const {DetectionsView.live: 12345, DetectionsView.devices: 1234, DetectionsView.alerts: 99},
              onSelect: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.getRect(find.text('99')).right, lessThanOrEqualTo(width - 20));
      expect(tester.getRect(find.text('Alerts')).right, lessThanOrEqualTo(width - 20));
    });
  }

  testWidgets('Detections screen has an Alerts tab that opens the alert list', (tester) async {
    final (c, db) = await _container();
    await _pump(tester, c, const DetectionsScreen());
    await tester.pump();
    expect(find.text('Alerts'), findsOneWidget);
    await tester.tap(find.text('Alerts'));
    await tester.pump();
    expect(c.read(detectionsViewProvider), DetectionsView.alerts);
    expect(find.text('ALERTS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.read(deviceRegistryProvider).dispose();
    await db.close();
  });

  test('a tapped notification opens the tab that holds its alert', () {
    expect(viewForAlertKind('detector'), DetectionsView.history);
    expect(viewForAlertKind('flock'), DetectionsView.history);
    expect(viewForAlertKind('drone'), DetectionsView.history);
    expect(viewForAlertKind('gps_watch'), DetectionsView.alerts);
    expect(viewForAlertKind('trusted_network'), DetectionsView.alerts);
    expect(viewForAlertKind('finder'), DetectionsView.alerts);
    expect(viewForAlertKind('foxhunt'), isNull);
  });

  testWidgets('Suggested signatures: SAVE on a name group saves a signature that reclassifies its radios', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final reg = DeviceRegistry(engine: SignatureEngine(const []));
    for (var n = 1; n <= 3; n++) {
      reg.ingest(Observation(
        key: 'BLE:02:00:00:00:00:0$n',
        kind: RadioKind.ble,
        mac: '02:00:00:00:00:0$n',
        name: 'Zyx-0$n',
        serviceUuids: const ['FFE0'],
        lastSeenMs: n,
      ));
      reg.ingest(Observation(key: 'BLE:02:00:00:00:01:0$n', kind: RadioKind.ble, mac: '02:00:00:00:01:0$n', name: 'Qrs-0$n', lastSeenMs: n));
    }
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      deviceRegistryProvider.overrideWith((ref) {
        reg.setUserSignatures(const []);
        ref.listen(userSignaturesProvider, (_, next) => reg.setUserSignatures(next.items));
        return reg;
      }),
    ]);
    await _pump(tester, c, const Scaffold(body: SuggestionsSheet()));
    await tester.pumpAndSettle();
    expect(find.text('3 radios · Service FFE0'), findsOneWidget);
    expect(find.text('Also share: Name like "Zyx-01"'), findsOneWidget);
    expect(find.text('3 radios · Name like "Qrs-01"'), findsOneWidget);
    expect(find.text('SAVE'), findsNWidgets(2));
    await tester.tap(find.text('SAVE').last);
    await tester.pumpAndSettle();
    expect(find.text('Save signature'), findsOneWidget);
    expect(find.text('Name Qrs-*'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Qrs sensors');
    await tester.tap(find.widgetWithText(ElevatedButton, 'SAVE'));
    await tester.pumpAndSettle();
    expect(find.text('SAVED'), findsOneWidget);
    final sig = c.read(userSignaturesProvider).items.single;
    expect((sig.name, sig.alert, sig.rules.single.text), ('Qrs sensors', true, 'Qrs-*'));
    expect(reg.devices.where((d) => d.signatures.any((s) => s.name == 'Qrs sensors')), hasLength(3));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('My signatures lists a saved signature, toggles its alert and removes it', (tester) async {
    SharedPreferences.setMockInitialValues({
      UserSignatures.prefsKey: jsonEncode([
        const Signature(
          id: 'user-1',
          name: 'Qrs sensors',
          kind: SignatureClass.other,
          rules: [MatchRule(RuleKind.nameGlob, text: 'Qrs-*')],
          alert: true,
        ).toJson(),
      ]),
    });
    final c = ProviderContainer();
    await _pump(tester, c, const UserSignaturesScreen());
    await _settle(tester);
    expect(find.text('Qrs sensors'), findsOneWidget);
    expect(find.text('Name Qrs-* · Other'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await _settle(tester);
    expect(c.read(userSignaturesProvider).items.single.alert, isFalse);
    await tester.tap(find.byTooltip('Remove Qrs sensors'));
    await _settle(tester);
    expect(find.text('No signatures yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Wardrive report renders a session with no route and shares text', (tester) async {
    const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, null));
    final (c, db) = await _container();
    await _pump(
      tester,
      c,
      const WardriveReportScreen(
        session: Session(
          id: 's1',
          name: 'Drive',
          nodeId: 'default',
          startedAt: 0,
          endedAt: 125000,
          enginesActive: 0,
          detectionCount: 0,
          uniqueMacCount: 0,
          distanceKm: 0,
          exported: false,
          isWardrive: true,
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Wardrive report'), findsOneWidget);
    expect(find.text('Seen before'), findsOneWidget);
    expect(find.text('Flock cameras'), findsOneWidget);
    expect(find.text('Uploads'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byTooltip('Share as text'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets('Seen at your stops shows its empty state on an empty database', (tester) async {
    final (c, db) = await _container();
    await _pump(tester, c, const StopsScreen());
    await _settle(tester);
    expect(find.text('Nothing seen at two stops'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets('Trusted networks shows empty state, then a learning network', (tester) async {
    final (c, db) = await _container();
    await _pump(tester, c, const TrustedNetworksScreen());
    await tester.pumpAndSettle();
    expect(find.text('No trusted networks'), findsOneWidget);
    await tester.runAsync(() => c.read(trustedNetworksProvider).trust('MyNetwork', const [], DateTime.now().millisecondsSinceEpoch));
    await tester.pumpAndSettle();
    expect(find.text('MyNetwork'), findsOneWidget);
    expect(find.textContaining('learning'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
