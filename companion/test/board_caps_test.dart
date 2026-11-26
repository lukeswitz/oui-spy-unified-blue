// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/board_caps.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/features/engines/foxhunter_screen.dart';
import 'package:oui_spy/features/engines/unipwn_screen.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';
import 'package:oui_spy/features/pcap/pcap_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _none = BoardCaps(board: '', connected: false, manager: false);
const _s3 = BoardCaps(board: 'v3_app_controlled', connected: true, manager: false);
const _c5 = BoardCaps(board: 'v3_app_controlled_c5', connected: true, manager: false);
const _mgr = BoardCaps(board: 'v3_node_manager_s3', connected: true, manager: true);

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

Future<ProviderContainer> _open(WidgetTester tester, BoardCaps caps, Widget home) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    boardCapsProvider.overrideWithValue(caps),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
  ]);
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.darkTheme, home: home),
  ));
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('capability model', () {
    test('C5 features need a connected C5 board and say why when they cannot run', () {
      expect(_c5.wifi5Ghz.enabled, isTrue);
      expect(_c5.ieee802154.enabled, isTrue);
      expect(_s3.wifi5Ghz.enabled, isFalse);
      expect(_s3.ieee802154.reason, contains('ESP32-C5'));
      expect(_none.wifi5Ghz.reason, contains('Connect'));
    });

    test('wardrive 802.15.4 on a manager follows the C5 nodes live in the mesh', () {
      const mgrC5Node = BoardCaps(board: 'xiao_c3', connected: true, manager: true, meshHas802154: true);
      const mgrNoC5 = BoardCaps(board: 'xiao_c3', connected: true, manager: true);
      expect(mgrC5Node.wardrive802154.enabled, isTrue);
      expect(mgrC5Node.ieee802154.enabled, isFalse);
      expect(mgrNoC5.wardrive802154.reason, contains('No C5 node is live in the mesh'));
      expect(const BoardCaps(board: 'xiao_s3', connected: true, manager: false, meshHas802154: true).wardrive802154.enabled, isFalse);
      expect(_c5.wardrive802154.enabled, isTrue);
      expect(_none.wardrive802154.reason, contains('Connect'));
      expect(mgrC5Node == mgrNoC5, isFalse);
    });

    test('boards without a buzzer are the ones the settings page already named', () {
      for (final b in ['tdongle_s3', 'tdongle_c5', 'stickc']) {
        expect(BoardCaps(board: b, connected: true, manager: false).buzzer.enabled, isFalse, reason: b);
      }
      expect(_s3.buzzer.enabled, isTrue);
      expect(_s3.buzzer.reason, isNull);
      expect(const BoardCaps(board: 'stickc', connected: true, manager: false).buzzer.reason, 'This board has no buzzer.');
    });

    test('manager-only items need a manager', () {
      expect(_mgr.managerOnly.enabled, isTrue);
      expect(_s3.managerOnly.reason, contains('manager'));
      expect(_none.managerOnly.reason, contains('Connect'));
    });

    test('equal capabilities compare equal so listeners do not rebuild', () {
      expect(_s3 == const BoardCaps(board: 'v3_app_controlled', connected: true, manager: false), isTrue);
      expect(_s3.buzzer == _c5.buzzer, isTrue);
    });
  });

  group('disabled instead of hidden', () {
    testWidgets('PCAP on an S3 board keeps 802.15.4 and 5 GHz visible, disabled, with the reason', (tester) async {
      await _open(tester, _s3, const PcapScreen());
      expect(find.byKey(const Key('pcap-mode-zigbee')), findsOneWidget);
      expect(find.text('802.15.4'), findsOneWidget);
      expect(find.byKey(const Key('pcap-5ghz')), findsOneWidget);
      expect(tester.widget<DropdownButton<int>>(find.byKey(const Key('pcap-5ghz'))).onChanged, isNull);
      expect(find.textContaining('Needs an ESP32-C5 board'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('pcap-mode-zigbee')));
      await tester.pump();
      expect(find.text('Channel'), findsNothing);
    });

    testWidgets('PCAP on a C5 board enables both and shows no reason', (tester) async {
      await _open(tester, _c5, const PcapScreen());
      expect(tester.widget<DropdownButton<int>>(find.byKey(const Key('pcap-5ghz'))).onChanged, isNotNull);
      expect(find.textContaining('Needs an ESP32-C5 board'), findsNothing);
    });

    testWidgets('UniPwn keeps its node picker with a manager-only reason when no manager is connected', (tester) async {
      await _open(tester, _s3, const UnipwnScreen());
      expect(find.text('No mesh nodes seen yet.'), findsOneWidget);
      expect(find.textContaining('Needs a manager board'), findsOneWidget);
    });

    testWidgets('Foxhunter keeps HUNT FROM with a manager-only reason when no manager is connected', (tester) async {
      await _open(tester, _s3, const FoxhunterScreen());
      expect(find.text('No mesh nodes seen yet.'), findsOneWidget);
      expect(find.textContaining('Needs a manager board'), findsOneWidget);
      expect(find.text('HUNT'), findsOneWidget);
    });

    testWidgets('the wardrive 802.15.4 switch stays on an S3 board, off and disabled, with the reason', (tester) async {
      await _open(tester, _s3, const Scaffold(body: SingleChildScrollView(child: SessionTargets())));
      final sw = tester.widget<Switch>(find.byKey(const ValueKey('zigbee-switch')));
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNull);
      expect(find.textContaining('Needs an ESP32-C5 board'), findsOneWidget);
    });

    testWidgets('the wardrive 802.15.4 switch works on a C5 board', (tester) async {
      await _open(tester, _c5, const Scaffold(body: SingleChildScrollView(child: SessionTargets())));
      expect(tester.widget<Switch>(find.byKey(const ValueKey('zigbee-switch'))).onChanged, isNotNull);
      expect(find.textContaining('Needs an ESP32-C5 board'), findsNothing);
    });

    testWidgets('the wardrive 802.15.4 switch works on a manager with a C5 node in the mesh', (tester) async {
      await _open(tester, const BoardCaps(board: 'xiao_c3', connected: true, manager: true, meshHas802154: true),
          const Scaffold(body: SingleChildScrollView(child: SessionTargets())));
      expect(tester.widget<Switch>(find.byKey(const ValueKey('zigbee-switch'))).onChanged, isNotNull);
      expect(find.textContaining('Needs an ESP32-C5 board'), findsNothing);
    });

    testWidgets('the wardrive 802.15.4 switch on a manager without a C5 node says so', (tester) async {
      await _open(tester, const BoardCaps(board: 'xiao_c3', connected: true, manager: true),
          const Scaffold(body: SingleChildScrollView(child: SessionTargets())));
      expect(tester.widget<Switch>(find.byKey(const ValueKey('zigbee-switch'))).onChanged, isNull);
      expect(find.textContaining('No C5 node is live in the mesh'), findsOneWidget);
    });

    testWidgets('Settings keeps the Buzzer rows on a board without one, disabled, with the reason', (tester) async {
      const stick = BoardCaps(board: 'stickc', connected: true, manager: false);
      final c = await _open(tester, stick, const DeviceConfigScreen());
      c.read(appStateProvider).connectionState = NodeConnectionState.ready;
      c.read(appStateProvider).notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Node'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sound & Lights'));
      await tester.pumpAndSettle();
      expect(find.text('Buzzer'), findsOneWidget);
      expect(find.text('Buzzer Volume'), findsOneWidget);
      expect(find.text('Alert sounds'), findsOneWidget);
      expect(find.text('This board has no buzzer.'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
      expect(find.text('Status LED'), findsOneWidget);
    });

    testWidgets('a settings row without an action is dimmed', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Column(children: [
            const ConfigActionRow(key: Key('off'), icon: Icons.restart_alt, label: 'Off row', onTap: null),
            ConfigActionRow(key: const Key('on'), icon: Icons.restart_alt, label: 'On row', onTap: () {}),
          ]),
        ),
      ));
      double opacityOf(String key) => tester
          .widget<Opacity>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Opacity)))
          .opacity;
      expect(opacityOf('off'), lessThan(1));
      expect(opacityOf('on'), 1);
    });
  });
}
