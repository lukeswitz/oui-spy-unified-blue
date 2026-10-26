import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/home/engine_card.dart';
import 'package:oui_spy/features/home/home_screen.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_stats_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get scanning => false;

  @override
  bool get radioListening => false;

  @override
  int get radioMask => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManagerBle extends BleManager {
  @override
  bool get isManagerConnected => true;
}

Detection _det(String mac, {String ssid = 'MyNetwork'}) => Detection(
      id: mac,
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
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  double width = 360,
  double scale = 1.0,
  bool manager = false,
  bool running = false,
  bool wardriveRunning = false,
  bool detections = false,
  Map<Engine, EngineState> states = const {},
  NodeConnectionState conn = NodeConnectionState.ready,
  String nodeId = '',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.binding.setSurfaceSize(Size(width, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    if (manager)
      bleManagerProvider.overrideWith((ref) {
        final m = _ManagerBle();
        ref.onDispose(m.dispose);
        return m;
      }),
  ]);
  final app = container.read(appStateProvider);
  app.connectionState = conn;
  app.nodeId = nodeId;
  states.forEach((e, s) {
    app.activeEngines |= e.bitmask;
    app.engineStates[e.index] = s;
  });
  if (running) {
    app.activeEngines = Engine.flockWifi.bitmask;
    app.engineStates[Engine.flockWifi.index] = EngineState.active;
  }
  if (detections) {
    app.recentDetections.add(_det('02:00:00:00:00:01'));
    app.recentDetections.add(_det('02:00:00:00:00:02'));
  }
  if (wardriveRunning) {
    container.read(wardriveProvider).state = WardriveState.running;
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const HomeScreen(),
    ),
  ));
  await tester.pump();
  return container;
}

Future<void> _release(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

const _homeEngines = [
  Engine.flockWifi,
  Engine.flockBle,
  Engine.detector,
  Engine.skySpy,
  Engine.foxhunter,
  Engine.uniPwn,
  Engine.pcap,
];

Finder _cardFinder(Engine e) => find.byWidgetPredicate((w) => w is EngineCard && w.engine == e);

TextSpan _word(WidgetTester tester, Engine e) {
  final t = tester.widget<Text>(
      find.descendant(of: _cardFinder(e), matching: find.byKey(const ValueKey('engine-sub'))));
  return (t.textSpan! as TextSpan).children!.first as TextSpan;
}

void main() {
  testWidgets('home header shows the node name and no Overview title', (tester) async {
    await _pump(tester, nodeId: 'MyNode');
    final title = tester.widget<Text>(find.text('MyNode'));
    expect(title.style!.fontSize, 28);
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Live'), findsOneWidget);
    await _release(tester);
  });

  testWidgets('overview shows its section headers without numbers', (tester) async {
    await _pump(tester, detections: true);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Tracking'), findsOneWidget);
    expect(find.text('Specialty'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    for (final n in ['01', '02', '03', '04', '05']) {
      expect(find.text(n), findsNothing, reason: n);
    }
    await _release(tester);
  });

  testWidgets('stat cards are filled rounded cards without borders', (tester) async {
    await _pump(tester);
    final p = AppTheme.of(tester.element(find.byType(HomeScreen)));
    final cards = find.descendant(
        of: find.byType(DStatsStrip), matching: find.byWidgetPredicate((w) => w is Material && w.color == p.surface));
    expect(cards, findsNWidgets(3));
    final shape = tester.widget<Material>(cards.first).shape! as RoundedRectangleBorder;
    expect(shape.side, BorderSide.none);
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.card));
    for (final l in ['Unique', 'Engines', 'Per min']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    await _release(tester);
  });

  testWidgets('home shows scan targets and radios but no start button', (tester) async {
    await _pump(tester);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.byType(SessionTargets), findsOneWidget);
    for (final l in ['FLOCK', 'DRONE', 'WIGLE', 'DETECT', 'WiFi', 'BLE', 'WiFi+BLE']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.byType(SessionStartButton), findsNothing);
    expect(find.byKey(const ValueKey('session-start')), findsNothing);
    final scan = tester.getRect(find.byKey(const ValueKey('group-scan')));
    final stats = tester.getRect(find.byType(DStatsStrip));
    final safety = tester.getRect(find.byKey(const ValueKey('group-safety')));
    expect(scan.top, greaterThan(stats.bottom));
    expect(scan.bottom, lessThan(safety.top));
    await _release(tester);
  });

  testWidgets('all seven engine rows have equal height and width', (tester) async {
    await _pump(tester, running: true);
    final rects = [for (final e in _homeEngines) tester.getRect(_cardFinder(e))];
    expect(rects.length, 7);
    expect(rects.map((r) => r.height).toList(), everyElement(rects.first.height));
    expect(rects.map((r) => r.width).toSet().length, 1);
    expect(rects.first.height, greaterThanOrEqualTo(64));
    expect(rects.map((r) => r.left).toSet().length, 1);
    await _release(tester);
  });

  testWidgets('each engine group is one borderless rounded card with inset dividers', (tester) async {
    await _pump(tester);
    final p = AppTheme.of(tester.element(find.byType(HomeScreen)));
    const groups = {
      'safety': [Engine.flockWifi, Engine.flockBle],
      'tracking': [Engine.detector, Engine.skySpy],
      'specialty': [Engine.foxhunter, Engine.uniPwn, Engine.pcap],
    };
    for (final g in groups.entries) {
      final panel = find.byKey(ValueKey('group-${g.key}'));
      expect(panel, findsOneWidget, reason: g.key);
      final deco = tester.widget<Container>(panel).decoration! as BoxDecoration;
      expect(deco.color, p.surface);
      expect(deco.border, isNull);
      expect(deco.borderRadius, BorderRadius.circular(AppRadius.card));
      expect(tester.widget<Container>(panel).clipBehavior, Clip.antiAlias);
      for (final e in g.value) {
        expect(find.descendant(of: panel, matching: _cardFinder(e)), findsOneWidget, reason: e.name);
      }
      final dividers = find.descendant(of: panel, matching: find.byType(Divider));
      expect(dividers, findsNWidgets(g.value.length - 1), reason: g.key);
      expect(tester.widget<Divider>(dividers.first).indent, 62);
    }
    await _release(tester);
  });

  testWidgets('engine rows carry no border of their own', (tester) async {
    await _pump(tester, running: true);
    for (final e in _homeEngines) {
      final row = tester.widget<Container>(
          find.descendant(of: _cardFinder(e), matching: find.byType(Container)).first);
      expect(row.decoration, isNull, reason: e.name);
    }
    await _release(tester);
  });

  testWidgets('recent activity and accounts share the panel style', (tester) async {
    await _pump(tester, detections: true);
    expect(find.byKey(const ValueKey('group-recent')), findsOneWidget);
    await _release(tester);
  });

  testWidgets('every engine card shows its description, running or not', (tester) async {
    await _pump(tester, running: true);
    for (final e in Engine.values) {
      final f = _cardFinder(e);
      if (f.evaluate().isEmpty) continue;
      expect(find.descendant(of: f, matching: find.textContaining(e.description, findRichText: true)),
          findsOneWidget, reason: e.name);
    }
    expect(find.byType(EngineCard), findsNWidgets(7));
    await _release(tester);
  });

  testWidgets('switches and counts share one right edge across all rows', (tester) async {
    await _pump(tester);
    final rights = <double>{};
    final countRights = <double>{};
    for (final e in _homeEngines) {
      final card = _cardFinder(e);
      rights.add(tester.getRect(find.descendant(of: card, matching: find.byType(Switch))).right);
      countRights.add(tester
          .getRect(find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 17)))
          .right);
    }
    expect(rights.length, 1);
    expect(countRights.length, 1);
    await _release(tester);
  });

  testWidgets('seven engine switches, enabled when connected', (tester) async {
    await _pump(tester);
    expect(find.byType(EngineCard), findsNWidgets(7));
    final switches = find.descendant(of: find.byType(EngineCard), matching: find.byType(Switch));
    expect(switches, findsNWidgets(7));
    for (final s in tester.widgetList<Switch>(switches)) {
      expect(s.onChanged, isNotNull);
    }
    await _release(tester);
  });

  testWidgets('stats strip has three equal columns without a manager', (tester) async {
    await _pump(tester);
    final cols = find.descendant(of: find.byType(DStatsStrip), matching: find.byType(Expanded));
    expect(cols, findsNWidgets(3));
    final widths = tester.widgetList(cols).map((w) => tester.getSize(find.byWidget(w)).width).toSet();
    expect(widths.length, 1);
    expect(find.text('Nodes'), findsNothing);
    await _release(tester);
  });

  testWidgets('stats strip has four equal columns with a manager', (tester) async {
    await _pump(tester, manager: true);
    final cols = find.descendant(of: find.byType(DStatsStrip), matching: find.byType(Expanded));
    expect(cols, findsNWidgets(4));
    final widths = tester.widgetList(cols).map((w) => tester.getSize(find.byWidget(w)).width).toSet();
    expect(widths.length, 1);
    expect(find.text('Nodes'), findsOneWidget);
    await _release(tester);
  });

  testWidgets('narrow width and large text scale do not overflow', (tester) async {
    final container = await _pump(tester, width: 320, scale: 1.3, manager: true, running: true, detections: true);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: EngineCard(
                  engine: Engine.flockWifi,
                  detectionCount: 12345,
                  isActive: true,
                  engineState: EngineState.active,
                  lastDetection: DateTime.now(),
                  rate: 12345,
                  nodeCount: 12,
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _release(tester);
  });

  test('map idle overlay carries the start button only', () {
    final src = File('lib/features/wardrive/wardrive_controls.dart').readAsStringSync();
    expect(src.contains('SessionStartButton('), isTrue);
    expect(src.contains('SessionBar('), isFalse);
  });

  Future<ProviderContainer> pumpButton(WidgetTester tester, {bool running = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    ]);
    if (running) container.read(wardriveProvider).state = WardriveState.running;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: SessionStartButton()),
      ),
    ));
    await tester.pump();
    return container;
  }

  testWidgets('start button shows START and is enabled when idle', (tester) async {
    await pumpButton(tester);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('STOP'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    await _release(tester);
  });

  testWidgets('start button becomes STOP in error color while running', (tester) async {
    await pumpButton(tester, running: true);
    expect(find.text('STOP'), findsOneWidget);
    expect(find.text('START'), findsNothing);
    final b = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(b.onPressed, isNotNull);
    final states = <WidgetState>{};
    final bg = b.style!.backgroundColor!.resolve(states)!;
    final fg = b.style!.foregroundColor!.resolve(states)!;
    expect(bg, AppTheme.error);
    expect(AppTheme.contrast(bg, fg), greaterThanOrEqualTo(4.5));
    await _release(tester);
  });

  testWidgets('start button shows STOP while paused', (tester) async {
    final c = await pumpButton(tester);
    final wd = c.read(wardriveProvider);
    wd.state = WardriveState.paused;
    wd.notifyListeners();
    await tester.pump();
    expect(find.text('STOP'), findsOneWidget);
    await _release(tester);
  });

  Color? rowColor(WidgetTester tester, Engine e) => tester
      .widget<Container>(find.descendant(of: _cardFinder(e), matching: find.byType(Container)).first)
      .color;

  BoxDecoration wellDeco(WidgetTester tester, Engine e) => tester
      .widget<Container>(find.descendant(of: _cardFinder(e), matching: find.byKey(const ValueKey('engine-well'))))
      .decoration! as BoxDecoration;

  testWidgets('alerting row is warning with readable text, exploiting row is error', (tester) async {
    await _pump(tester, states: {
      Engine.flockWifi: EngineState.alerting,
      Engine.foxhunter: EngineState.exploiting,
    });
    expect(rowColor(tester, Engine.flockWifi), AppTheme.warning);
    final name = tester.widget<Text>(find.descendant(of: _cardFinder(Engine.flockWifi), matching: find.text('Flock WiFi')));
    expect(AppTheme.contrast(name.style!.color!, AppTheme.warning), greaterThanOrEqualTo(4.5));
    final word = _word(tester, Engine.flockWifi);
    expect(word.text, 'Alert');
    expect(AppTheme.contrast(word.style!.color!, AppTheme.warning), greaterThanOrEqualTo(4.5));
    final well = wellDeco(tester, Engine.flockWifi);
    expect(well.color, name.style!.color!.withValues(alpha: 0.16));
    expect(well.border, isNull);

    expect(rowColor(tester, Engine.foxhunter), AppTheme.error);
    final rowName = tester.widget<Text>(find.descendant(of: _cardFinder(Engine.foxhunter), matching: find.text('Foxhunter')));
    expect(AppTheme.contrast(rowName.style!.color!, AppTheme.error), greaterThanOrEqualTo(4.5));
    await _release(tester);
  });

  testWidgets('CANCEL is an error-colored outlined button', (tester) async {
    await _pump(tester, conn: NodeConnectionState.connecting);
    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.style!.foregroundColor!.resolve({}), AppTheme.error);
    expect(btn.style!.side!.resolve({})!.color, AppTheme.error);
    await _release(tester);
  });

  testWidgets('running row subtitle says Active in accent, stopped says Off', (tester) async {
    await _pump(tester, running: true);
    final p = AppTheme.of(tester.element(_cardFinder(Engine.flockWifi)));

    final on = wellDeco(tester, Engine.flockWifi);
    expect(on.color, AppTheme.accent.withValues(alpha: 0.16));
    expect(on.borderRadius, BorderRadius.circular(AppRadius.chip));
    expect(on.border, isNull);
    final word = _word(tester, Engine.flockWifi);
    expect(word.text, 'Active');
    expect(word.style?.color, AppTheme.accent);
    expect(find.byKey(const ValueKey('engine-pill')), findsNothing);
    expect(rowColor(tester, Engine.flockWifi), isNull);

    final off = wellDeco(tester, Engine.flockBle);
    expect(off.color, p.surfaceLight);
    expect(off.border, isNull);
    final offWord = _word(tester, Engine.flockBle);
    expect(offWord.text, 'Off');
    expect(offWord.style?.color, p.textSecondary);
    await _release(tester);
  });

  testWidgets('pending Starting word is readable on the panel surface', (tester) async {
    await _pump(tester);
    final p = AppTheme.of(tester.element(_cardFinder(Engine.flockWifi)));
    await tester.tap(find.descendant(of: _cardFinder(Engine.flockWifi), matching: find.byType(Switch)));
    await tester.pump();
    final word = _word(tester, Engine.flockWifi);
    expect(word.text, 'Starting');
    expect(AppTheme.contrast(word.style!.color!, p.surface), greaterThanOrEqualTo(4.5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
