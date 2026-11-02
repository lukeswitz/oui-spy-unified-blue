// ignore_for_file: avoid_print
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Detection _det(int i) => Detection(
      id: 'd$i',
      sessionId: 's',
      nodeId: 'n',
      macAddress: '02:00:${(i >> 16) & 0xff}:${(i >> 8) & 0xff}:${i & 0xff}:01',
      engine: i % 2 == 0 ? Engine.detector : Engine.wardrive,
      method: 'ble_adv',
      rssi: -40 - (i % 50),
      channel: (i % 13) + 1,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.now(),
      deviceName: 'dev $i',
      ssid: i % 2 == 0 ? '' : 'net$i',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('feed rebuild cost in a phone viewport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    final data = [for (var i = 0; i < 500; i++) _det(i)];

    final tick = ValueNotifier(0);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: tick,
            builder: (_, __, ___) => ListView.builder(
              itemCount: data.length,
              itemBuilder: (c, i) =>
                  DetectionRow(key: ValueKey(data[i].id), detection: data[i]),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    const reps = 30;
    final sw = Stopwatch()..start();
    for (var r = 0; r < reps; r++) {
      tick.value = r + 1; // force the ListView to rebuild its visible rows
      await tester.pump();
    }
    sw.stop();
    print('FEED REBUILD (500 rows, phone viewport): '
        '${(sw.elapsedMicroseconds / reps / 1000).toStringAsFixed(2)}ms/rebuild');
    expect(find.byType(DetectionRow), findsWidgets);
  });
}
