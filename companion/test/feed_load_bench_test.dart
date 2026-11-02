// ignore_for_file: avoid_print
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _mac(int i) => '02:00:${(i >> 24) & 0xff}:${(i >> 16) & 0xff}:'
    '${(i >> 8) & 0xff}:${i & 0xff}';

Future<void> _drain(BleManager ble, int n) async {
  var got = 0;
  final sub = ble.detections.listen((_) => got++);
  for (var i = 0; i < n; i++) {
    ble.addPhoneDetection(_mac(i), 'dev$i', -40 - (i % 50), const []);
  }
  var spins = 0;
  while (got < n && spins++ < n * 4) {
    await Future<void>.delayed(Duration.zero);
  }
  await sub.cancel();
  // let the coalesced-notify timer flush so none is pending at test end
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (c) async => '.');
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (c) async => null);

  Future<(AppState, BleManager)> build() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final app = c.read(appStateProvider);
    final ble = c.read(bleManagerProvider);
    return (app, ble);
  }

  // RC1: time the real AppState ingest path (_upsertDetection + dedupe index).
  for (final n in const [250, 500, 1000, 2000]) {
    test('INGEST n=$n', () async {
      final (app, ble) = await build();
      final sw = Stopwatch()..start();
      await _drain(ble, n);
      sw.stop();
      final held = app.recentDetections.length;
      print('INGEST n=$n held=$held  ${sw.elapsedMilliseconds}ms '
          '(${(sw.elapsedMicroseconds / n).toStringAsFixed(1)}us/det)');
      expect(held, lessThanOrEqualTo(AppState.maxRecentDetections));
    });
  }

  // RC-A: how many UI notifies (= full FeedScreen rebuilds) N detections cause.
  for (final n in const [500, 1000]) {
    test('NOTIFY n=$n', () async {
      final (app, ble) = await build();
      var notifies = 0;
      app.addListener(() => notifies++);
      await _drain(ble, n);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      print('NOTIFY n=$n  rebuilds=$notifies');
      expect(notifies, lessThan(n ~/ 10));
    });
  }

  // RC2: time the exact sort+group work FeedScreen.build() runs per rebuild.
  for (final n in const [250, 500]) {
    test('BUILD-OPS n=$n', () async {
      final (app, ble) = await build();
      await _drain(ble, n);
      final src = app.recentDetections;
      final sw = Stopwatch()..start();
      const reps = 200;
      for (var r = 0; r < reps; r++) {
        final sorted = List<Detection>.from(src)
          ..sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));
        final groups = groupDronesByUavId(sorted);
        final feedItems = <Object>[...sorted, ...groups];
        feedItems.sort((a, b) {
          DateTime ts(Object o) => o is Detection
              ? o.appTimestamp
              : (o as DroneGroup).representative.appTimestamp;
          return ts(b).compareTo(ts(a));
        });
      }
      sw.stop();
      print('BUILD-OPS n=${src.length}  '
          '${(sw.elapsedMicroseconds / reps).toStringAsFixed(0)}us/rebuild');
      expect(src, isNotEmpty);
    });
  }
}
