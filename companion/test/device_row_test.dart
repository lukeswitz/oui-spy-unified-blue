import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/features/devices/devices_screen.dart';

const _isp = Signature(id: 'isp-gw', name: 'Vantiva or Technicolor ISP gateway', kind: SignatureClass.isp);
const _tag = Signature(id: 'airtag', name: 'Apple AirTag / Find My tag', kind: SignatureClass.finder);

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('device rows fit 360dp at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final wifi = ClassifiedDevice(
        Observation(
          key: 'W:1',
          kind: RadioKind.wifi,
          mac: '02:00:00:00:00:01',
          rssi: -91,
          name: 'MyNetwork-with-a-very-long-ssid-name',
          channel: 11,
          authMode: 3,
          hiddenSsid: true,
        ),
        [_isp],
        {'esp32'},
      );
      final ble = ClassifiedDevice(
        Observation(key: 'B:1', kind: RadioKind.ble, mac: '02:00:00:00:00:02', rssi: -94),
        [_tag],
        {'esp32'},
      );
      const guess = Guess('Vantiva or Technicolor ISP gateway', '', Confidence.high);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          deviceRegistryProvider.overrideWith((ref) => DeviceRegistry(vendorOf: (_) => 'Long Vendor Name Incorporated')),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Column(children: [
                DeviceRow(device: wifi, guess: guess),
                DeviceRow(device: ble, guess: guess),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('CH 11', findRichText: true), findsOneWidget);
      expect(find.text('WPA2'), findsOneWidget);
      expect(tester.getTopRight(find.text('-91')).dx, closeTo(340, 0.5));
      expect(find.textContaining('02:00:00:00:00:01', findRichText: true), findsOneWidget);
    });
  }
}
