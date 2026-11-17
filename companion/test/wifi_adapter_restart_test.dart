import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/link/wifi_adapter.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ouispy/wifiadapter');
  const d = WifiAdapterDevice(id: '/dev/bus/usb/001/002', vendorId: 0x0e8d, productId: 0x7612, name: 'MT7612U');
  final starts = <String>[];

  setUp(() {
    starts.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') starts.add((call.arguments as Map)['id'] as String);
      return call.method == 'start' ? true : null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('START right after STOP restarts the adapter', () async {
    final c = WifiAdapterController(BleManager());
    expect(await c.start(d), isTrue);
    expect(c.isActive(d.id), isTrue);

    final stopping = c.stop();
    final restarted = c.start(d);
    await stopping;
    expect(await restarted, isTrue);

    expect(starts, [d.id, d.id]);
    expect(c.isActive(d.id), isTrue);
  });
}
