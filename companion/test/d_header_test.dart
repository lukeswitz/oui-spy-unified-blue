// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/home/status_bar.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get radioListening => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(WidgetTester tester, NodeConnectionState s,
    {String nodeId = '', double width = 360, double scale = 1.0, WifiAdapterState? usb}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
    if (usb != null) ...[
      wifiAdapterStateProvider.overrideWith((ref) => Stream.value(usb)),
      sdrPresentProvider.overrideWith((ref) => Stream.value(false)),
    ],
  ]);
  final app = container.read(appStateProvider);
  app.connectionState = s;
  app.nodeId = nodeId;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: StatusBar()),
    ),
  ));
  await tester.pump();
  return container;
}

void main() {
  testWidgets('section header shows its label and trailing, no number', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: DSectionHeader(label: 'Specialty', trailing: Text('All'))),
    ));
    expect(find.text('Specialty'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('03'), findsNothing);
    final style = tester.widget<Text>(find.text('Specialty')).style!;
    expect(style.fontSize, 17);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.color, AppTheme.of(tester.element(find.text('Specialty'))).textPrimary);
  });

  testWidgets('every connection state has its word', (tester) async {
    const words = {
      NodeConnectionState.ready: 'Live',
      NodeConnectionState.connecting: 'Linking',
      NodeConnectionState.negotiating: 'MTU',
      NodeConnectionState.syncing: 'Sync',
      NodeConnectionState.reconnecting: 'Lost',
      NodeConnectionState.scanning: 'Scan',
      NodeConnectionState.disconnected: 'Offline',
    };
    for (final e in words.entries) {
      await _pump(tester, e.key);
      expect(find.text(e.value), findsOneWidget, reason: e.key.name);
    }
  });

  testWidgets('Lost and Offline use the error color, Live the accent', (tester) async {
    await _pump(tester, NodeConnectionState.reconnecting);
    expect(tester.widget<Text>(find.text('Lost')).style!.color, AppTheme.error);
    await _pump(tester, NodeConnectionState.disconnected);
    expect(tester.widget<Text>(find.text('Offline')).style!.color, AppTheme.error);
    await _pump(tester, NodeConnectionState.ready);
    expect(tester.widget<Text>(find.text('Live')).style!.color, AppTheme.accent);
  });

  testWidgets('OUI-APEX is the 28pt title with or without a node name', (tester) async {
    await _pump(tester, NodeConnectionState.ready, nodeId: 'MyNode');
    final s = tester.widget<Text>(find.text('OUI-APEX')).style!;
    expect(s.fontSize, 28);
    expect(s.fontWeight, FontWeight.w600);
    expect(find.text('MyNode'), findsNothing);
    await _pump(tester, NodeConnectionState.ready);
    expect(find.text('OUI-APEX'), findsOneWidget);
  });

  testWidgets('long node name ellipsizes at 320', (tester) async {
    await _pump(tester, NodeConnectionState.ready, nodeId: 'N' * 40, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('long node name at 320 and 1.3 text scale does not overflow', (tester) async {
    await _pump(tester, NodeConnectionState.ready, nodeId: 'N' * 40, width: 320, scale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('USB chip is detector color while scanning, secondary when idle', (tester) async {
    await _pump(tester, NodeConnectionState.disconnected, usb: WifiAdapterState.running);
    await tester.pump();
    expect(tester.widget<Icon>(find.byIcon(Icons.usb)).color, AppTheme.detector);
    await _pump(tester, NodeConnectionState.disconnected, usb: WifiAdapterState.present);
    await tester.pump();
    final t = AppTheme.of(tester.element(find.byIcon(Icons.usb)));
    expect(tester.widget<Icon>(find.byIcon(Icons.usb)).color, t.textSecondary);
  });

  testWidgets('offline with scan label fits 320', (tester) async {
    await _pump(tester, NodeConnectionState.disconnected, width: 320);
    expect(tester.takeException(), isNull);
  });
}
