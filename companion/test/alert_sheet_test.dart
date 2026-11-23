import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/alerts/alerts_view.dart';
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

void main() {
  testWidgets('an alert sheet shows the device rows and a Map button', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertNode(NodesCompanion.insert(id: 'default', name: 'n', macAddress: 'AA:BB:CC:DD:EE:FF', createdAt: 0));
    await db.insertSession(SessionsCompanion.insert(id: 's1', name: 's1', nodeId: 'default', startedAt: 1000));
    final d = Detection(
      id: '0',
      sessionId: 's1',
      nodeId: 'OUISPY-AB12',
      macAddress: '02:00:00:00:00:07',
      engine: Engine.detector,
      method: 'tracker',
      rssi: -61,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      count: 9,
      latitude: 51.4779,
      longitude: -0.0015,
    );
    await db.insertDetectionRow(detectionCompanion(d, 's1'), ext: detectionExt(d));
    for (final at in [3000, 5000]) {
      await db.insertClassAlert(
        macAddress: d.macAddress,
        deviceName: '',
        alertClass: 'tracker',
        title: 'Finder tags: test',
        reason: 'Board detector: test',
        isBle: true,
        rssi: -61,
        channel: 0,
        alertedAt: at,
        sessionId: 's1',
      );
    }
    final row = (await db.getClassAlertMaps()).single;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
      databaseProvider.overrideWithValue(db),
    ]);
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showAlertSheet(context, ref, row, false),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      await tester.tap(find.text('open'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('alert-map')), findsOneWidget);
    expect(find.text('Device details'), findsOneWidget);
    for (final s in ['Detector · BLE', '-61 dBm', '9', '51.47790, -0.00150', 'Times', 'First', 'Source', 'Session']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await tester.pumpWidget(const SizedBox());
    container.read(deviceRegistryProvider).dispose();
    await db.close();
  });
}
