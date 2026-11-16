import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (c) async => '.');
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);

  test('Live keeps one row per BSSID; SSID grouping is a view option', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final app = c.read(appStateProvider);
    final ble = c.read(bleManagerProvider);

    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:01', '', -82, 1, 0);
    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:01', 'MyNetwork', -80, 1, 3);
    ble.addPhoneWifiDetection('0e:bb:cc:dd:ee:02', 'MyNetwork', -78, 1, 3);
    ble.addPhoneWifiDetection('0E:BB:CC:DD:EE:02', '', -79, 1, 0);
    ble.addPhoneWifiDetection('02:00:00:00:00:01', '', -70, 6, 3);
    ble.addPhoneWifiDetection('02:00:00:00:00:02', '', -71, 6, 3);
    ble.addPhoneDetection('AA:BB:CC:DD:EE:01', '', -60, const []);
    ble.addPhoneDetection('aa:bb:cc:dd:ee:01', '', -61, const []);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final rows = app.recentDetections;
    expect(rows.where((d) => d.ssid == 'MyNetwork'), hasLength(2));
    expect(rows.where((d) => d.ssid.isEmpty && d.method == 'wifi_ap'), hasLength(2));
    expect(rows.where((d) => d.method == 'ble_adv'), hasLength(1));

    final g = groupBySsid(rows, app.dedupeKey);
    final net = g.rows.where((d) => d.ssid == 'MyNetwork').toList();
    expect(net, hasLength(1));
    expect(g.macs[net.single]!.toSet(), {'0a:bb:cc:dd:ee:01', '0e:bb:cc:dd:ee:02'});
    expect(net.single.rssi, -78);
    expect(g.keyOf[net.single], 'ssid:MyNetwork|wardrive');
    expect(g.rows, hasLength(rows.length - 1));
  });

  test('grouping 5000 BSSIDs of 50 SSIDs stays linear', () {
    final now = DateTime(2026);
    final rows = [
      for (var i = 0; i < 5000; i++)
        Detection(
          id: '$i',
          sessionId: 's',
          nodeId: 'n',
          macAddress: '0a:bb:cc:${(i >> 8).toRadixString(16).padLeft(2, '0')}:${(i & 255).toRadixString(16).padLeft(2, '0')}:01',
          engine: Engine.wardrive,
          method: 'wifi_ap',
          rssi: -50 - i % 40,
          channel: 6,
          deviceTimestampMs: 0,
          appTimestamp: now,
          ssid: 'MyNetwork${i % 50}',
        ),
    ];
    final sw = Stopwatch()..start();
    final g = groupBySsid(rows, (d) => '${d.macAddress}|${d.engine.name}');
    sw.stop();
    expect(g.rows, hasLength(50));
    expect(g.macs.values.every((m) => m.length == 100), isTrue);
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test('clients nest directly under the AP row they talk to', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final app = c.read(appStateProvider);
    final ble = c.read(bleManagerProvider);

    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:01', 'MyNetwork', -80, 1, 3);
    ble.addPhoneWifiDetection('0a:bb:cc:dd:ee:09', '', -60, 1, 0, client: true, ap: '0A:BB:CC:DD:EE:01');
    ble.addPhoneWifiDetection('0a:bb:cc:dd:ee:08', '', -61, 1, 0, client: true, ap: '0a:bb:cc:dd:ee:77');
    ble.addPhoneWifiDetection('0e:bb:cc:dd:ee:02', 'OtherNet', -70, 6, 3);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final nested = nestUnderParents(app.recentDetections, app.dedupeKey, app.apKeyFor);
    final order = nested.rows.map((d) => d.macAddress).toList();
    final ap = order.indexOf('0a:bb:cc:dd:ee:01');
    expect(order[ap + 1], '0a:bb:cc:dd:ee:09');
    expect(nested.parentOf.keys.map((d) => d.macAddress), ['0a:bb:cc:dd:ee:09']);
    expect(order, hasLength(4));
  });
}
