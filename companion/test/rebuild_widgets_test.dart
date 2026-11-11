import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/features/engines/detection_rules.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child, {double width = 360}) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(body: SizedBox(width: width, child: child)),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('CommandHeader stays one line with many chips at phone width', (tester) async {
    await tester.pumpWidget(_host(CommandHeader(
      title: 'DEVICES',
      count: '12/340',
      chips: [for (var i = 0; i < 8; i++) CommandActiveChip(label: 'FILTER $i', color: AppTheme.accent, onClear: () {})],
    )));
    expect(tester.takeException(), isNull);
    final title = tester.getTopLeft(find.text('DEVICES')).dy;
    final count = tester.getTopLeft(find.text('12/340')).dy;
    expect((title - count).abs(), lessThan(4));
  });

  testWidgets('WatchlistPanel shows empty state, then entries; SignaturesPanel renders', (tester) async {
    await tester.pumpWidget(_host(const SingleChildScrollView(
      child: Column(children: [WatchlistPanel(), SignaturesPanel()]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('No targets. Add one or import a list.'), findsOneWidget);
    expect(find.text('SIGNATURES'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(WatchlistPanel)));
    await container.read(watchlistProvider).importText('40:48:6E,Nokia router\nAA:BB:CC:DD:EE:FF,My tag');
    await tester.pumpAndSettle();
    expect(find.text('40:48:6E'), findsOneWidget);
    expect(find.text('Nokia router'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('40:48:6E'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Target'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
  });

  testWidgets('Add Target dismissed by tapping outside closes without errors', (tester) async {
    await tester.pumpWidget(_host(const WatchlistPanel()));
    await tester.tap(find.byTooltip('Add target'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '00:11');
    await tester.tapAt(const Offset(5, 5));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(find.text('Add Target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add Target saves an OUI with its description', (tester) async {
    await tester.pumpWidget(_host(const WatchlistPanel()));
    await tester.tap(find.byTooltip('Add target'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '00:11:22');
    await tester.enterText(find.byType(TextField).at(1), 'Bench cam');
    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(WatchlistPanel)));
    final e = container.read(watchlistProvider).entries.single;
    expect(e.identifier.toUpperCase(), '00:11:22');
    expect(e.description, 'Bench cam');
    expect(tester.takeException(), isNull);
  });
}
