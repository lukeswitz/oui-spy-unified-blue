import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (c) async => '.');
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);

  test('one Live row per network name, BSSIDs collected; hidden and BLE stay per MAC', () async {
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

    final net = app.recentDetections.where((d) => d.ssid == 'MyNetwork').toList();
    expect(net, hasLength(1));
    expect(app.macsFor(net.single), {'0a:bb:cc:dd:ee:01', '0e:bb:cc:dd:ee:02'});
    expect(app.recentDetections.where((d) => d.ssid.isEmpty && d.method == 'wifi_ap'), hasLength(2));
    expect(app.recentDetections.where((d) => d.method == 'ble_adv'), hasLength(1));
  });
}
