import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/models/session.dart';
import 'package:oui_spy/features/wardrive/wardrive_stats.dart';
import 'package:oui_spy/theme/app_theme.dart';

SessionStats _stats({
  int wifi = 0,
  int wifiTotal = 0,
  int ble = 0,
  int bleTotal = 0,
  int flock = 0,
  int drone = 0,
  int detector = 0,
}) =>
    SessionStats(
      duration: const Duration(minutes: 3, seconds: 7),
      distanceKm: 1.5,
      speedKmh: 30,
      totalDetections: 10,
      uniqueMacs: 8,
      newMacs: 2,
      wifiDetections: wifi,
      wifiTotal: wifiTotal,
      bleDetections: ble,
      bleTotal: bleTotal,
      flockCount: flock,
      droneCount: drone,
      detectorCount: detector,
      detectionsPerKm: 12,
      gpsAccuracy: 5,
      satelliteCount: 9,
    );

Future<void> _pump(WidgetTester tester, Widget child,
    {double width = 360, double scale = 1.0}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('five counts spread edge to edge with 12 padding', (tester) async {
    await _pump(
        tester,
        WardriveStats(
            stats: _stats(
                wifi: 12,
                wifiTotal: 40,
                ble: 3,
                bleTotal: 9,
                flock: 2,
                drone: 1,
                detector: 4)));
    final card = tester.getRect(find.byKey(const Key('wardrive-stats-card')));
    final first = tester.getRect(find.byKey(const Key('count-wifi')));
    final last = tester.getRect(find.byKey(const Key('count-ble')));
    expect(first.left - card.left, 12);
    expect(card.right - last.right, 12);
    expect(find.byKey(const Key('count-flock')), findsOneWidget);
    expect(find.byKey(const Key('count-drone')), findsOneWidget);
    expect(find.byKey(const Key('count-detect')), findsOneWidget);
  });

  testWidgets('two counts still align and zero counts are hidden', (tester) async {
    await _pump(tester, WardriveStats(stats: _stats(wifi: 5, ble: 2)));
    final card = tester.getRect(find.byKey(const Key('wardrive-stats-card')));
    final first = tester.getRect(find.byKey(const Key('count-wifi')));
    final last = tester.getRect(find.byKey(const Key('count-ble')));
    expect(first.left - card.left, 12);
    expect(card.right - last.right, 12);
    expect(find.byKey(const Key('count-flock')), findsNothing);
    expect(find.byKey(const Key('count-drone')), findsNothing);
    expect(find.byKey(const Key('count-detect')), findsNothing);
  });

  testWidgets('wifi total renders beside unique', (tester) async {
    await _pump(tester, WardriveStats(stats: _stats(wifi: 12, wifiTotal: 40)));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('40 total'), findsOneWidget);
  });

  testWidgets('card is fill colored and inset 8 from screen edges', (tester) async {
    await _pump(tester, WardriveStats(stats: _stats(wifi: 1)));
    final ctx = tester.element(find.byKey(const Key('wardrive-stats-card')));
    final p = AppTheme.of(ctx);
    final box = tester.widget<Container>(find.byKey(const Key('wardrive-stats-card')));
    expect((box.decoration as BoxDecoration).color, p.fill);
    final card = tester.getRect(find.byKey(const Key('wardrive-stats-card')));
    expect(card.left, 8);
    expect(360 - card.right, 8);
  });

  testWidgets('no overflow at 320 wide and 1.3 text scale', (tester) async {
    await _pump(
        tester,
        WardriveStats(
            stats: _stats(
                wifi: 1234,
                wifiTotal: 98765,
                ble: 4321,
                bleTotal: 87654,
                flock: 22,
                drone: 11,
                detector: 44)),
        width: 320,
        scale: 1.3);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byKey(const Key('wardrive-stats-card')));
    final last = tester.getRect(find.byKey(const Key('count-ble')));
    expect(card.right - last.right, 12);
  });

  testWidgets('running shows pause and stop wired to callbacks', (tester) async {
    var paused = 0, stopped = 0;
    await _pump(
        tester,
        WardriveRunCard(
          stats: _stats(),
          targets: 'WIFI + FLOCK',
          paused: false,
          onPause: () => paused++,
          onResume: () {},
          onStop: () => stopped++,
        ));
    expect(find.text('Resume'), findsNothing);
    await tester.tap(find.text('Pause'));
    await tester.tap(find.text('Stop'));
    expect(paused, 1);
    expect(stopped, 1);
    expect(find.text('WARDRIVE'), findsOneWidget);
    expect(find.text('WIFI + FLOCK'), findsOneWidget);
  });

  testWidgets('run card is rounded with no border', (tester) async {
    await _pump(
        tester,
        WardriveRunCard(
          stats: _stats(),
          targets: 'WIFI',
          paused: false,
          onPause: () {},
          onResume: () {},
          onStop: () {},
        ));
    final deco = tester.widget<Container>(find.byKey(const Key('wardrive-run-card'))).decoration! as BoxDecoration;
    expect(deco.border, isNull);
    expect(deco.borderRadius, BorderRadius.circular(AppRadius.card));
  });

  testWidgets('stopping keeps metrics and hides buttons', (tester) async {
    await _pump(
        tester,
        WardriveRunCard(
          stats: _stats(),
          targets: 'WIFI',
          paused: false,
          showButtons: false,
          onPause: () {},
          onResume: () {},
          onStop: () {},
        ));
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('SPEED'), findsOneWidget);
    expect(find.text('DET/KM'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets('paused shows resume and stop wired to callbacks', (tester) async {
    var resumed = 0, stopped = 0;
    await _pump(
        tester,
        WardriveRunCard(
          stats: _stats(),
          targets: 'WIFI',
          paused: true,
          onPause: () {},
          onResume: () => resumed++,
          onStop: () => stopped++,
        ));
    expect(find.text('Pause'), findsNothing);
    await tester.tap(find.text('Resume'));
    await tester.tap(find.text('Stop'));
    expect(resumed, 1);
    expect(stopped, 1);
  });
}
