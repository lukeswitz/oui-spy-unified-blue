// Copyright (c) 2026 Luke Switzer
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
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

  test('board APs that carry the SSID only in the wardrive extension group too', () {
    Detection ap(String mac, int rssi) => Detection(
          id: mac,
          sessionId: 's',
          nodeId: 'n',
          macAddress: mac,
          engine: Engine.wardrive,
          method: 'wifi_ap',
          rssi: rssi,
          channel: 6,
          deviceTimestampMs: 0,
          appTimestamp: DateTime(2026),
          ssid: '',
          wardrive: const WardriveExtension(ssid: 'MyNetwork', authMode: 3),
        );
    final g = groupBySsid([ap('0a:bb:cc:dd:ee:01', -70), ap('0a:bb:cc:dd:ee:02', -60)],
        (d) => '${d.macAddress}|${d.engine.name}');
    expect(g.rows, hasLength(1));
    expect(g.macs[g.rows.single], hasLength(2));
    expect(g.rows.single.rssi, -60);
  });

  test('a board wifi_client record decodes with the AP it talks to', () {
    final b = List<int>.filled(80, 0);
    b[0] = Engine.wardrive.index;
    b.setRange(1, 7, [0x0a, 0xbb, 0xcc, 0xdd, 0xee, 0x09]);
    b[7] = 0xc4;
    b[8] = 6;
    b[13] = 2;
    b[74] = 0x0a;
    b.setRange(75, 80, [0xbb, 0xcc, 0xdd, 0xee, 0x01]);
    final d = BleProtocol.decodeDetection(b, sessionId: 's', nodeId: 'n', appTimestamp: DateTime(2026));
    expect(d.method, 'wifi_client');
    expect(d.macAddress, '0a:bb:cc:dd:ee:09');
    expect(d.channel, 6);
    expect(BleProtocol.clientApOf(b), '0a:bb:cc:dd:ee:01');
    final ap = List<int>.from(b)..[13] = 0;
    expect(BleProtocol.clientApOf(ap), isNull);
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

  test('with SSID grouping on, clients of every BSSID indent under the SSID row', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final app = c.read(appStateProvider);
    final ble = c.read(bleManagerProvider);

    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:01', 'MyNetwork', -80, 1, 3);
    ble.addPhoneWifiDetection('0A:BB:CC:DD:EE:02', 'MyNetwork', -70, 6, 3);
    ble.addPhoneWifiDetection('0a:bb:cc:dd:ee:09', '', -60, 1, 0, client: true, ap: '0A:BB:CC:DD:EE:01');
    ble.addPhoneWifiDetection('0a:bb:cc:dd:ee:08', '', -61, 6, 0, client: true, ap: '0A:BB:CC:DD:EE:02');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final g = groupBySsid(app.recentDetections, app.dedupeKey);
    String rowKey(Detection d) => g.keyOf[d] ?? app.dedupeKey(d);
    final nested = nestUnderParents(g.rows, rowKey, (d) {
      final ap = app.apKeyFor(d);
      return ap == null ? null : g.groupOf[ap] ?? ap;
    });
    final order = nested.rows.map((d) => d.macAddress).toList();
    final net = order.indexWhere((m) => m == '0a:bb:cc:dd:ee:01' || m == '0a:bb:cc:dd:ee:02');
    expect(order, hasLength(3));
    expect(order.sublist(net + 1).toSet(), {'0a:bb:cc:dd:ee:09', '0a:bb:cc:dd:ee:08'});
    expect(nested.parentOf, hasLength(2));
  });
}
