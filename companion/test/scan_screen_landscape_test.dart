// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/link/usb_autoconnect.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/onboarding/scan_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Fbp extends FlutterBluePlusPlatform {
  @override
  Future<BmBluetoothAdapterState> getAdapterState(BmBluetoothAdapterStateRequest request) async =>
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connect screen fits a landscape phone with paired boards', (tester) async {
    FlutterBluePlusPlatform.instance = _Fbp();
    SharedPreferences.setMockInitialValues({
      'pairedBoards': [
        for (var i = 1; i <= 4; i++) 'AA:BB:CC:DD:EE:0$i|OUI-SPY',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(915, 412));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      usbAutoConnectProvider.overrideWith((ref) => UsbAutoConnect(ref.read(bleManagerProvider))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const ScanScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PAIRED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final button = find.byType(ElevatedButton);
    await tester.ensureVisible(button);
    await tester.pump();
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(412));
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpWidget(const SizedBox());
  });
}
