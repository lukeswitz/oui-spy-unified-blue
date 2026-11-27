// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/signature_sets.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/signatures/signature_sources_prompt.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Ble extends BleManager {
  _Ble({required this.ready, this.ext});

  final bool ready;
  bool? ext;
  final writes = <bool>[];

  @override
  NodeConnectionState get currentConnectionState =>
      ready ? NodeConnectionState.ready : NodeConnectionState.disconnected;

  @override
  Stream<NodeConnectionState> get connectionState => const Stream.empty();

  @override
  Future<bool?> readFlockExtendedOui() async => ext;

  @override
  Future<bool> setFlockExtendedOui(bool on) async {
    writes.add(on);
    ext = on;
    return true;
  }
}

class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final v = await signatureSourcesPromptVersion(ref);
              if (v != null && context.mounted) await showSignatureSourcesPrompt(context, ref, v);
            },
            child: const Text('open'),
          ),
        ),
      );
}

Future<(ProviderContainer, _Ble, List<Uri>)> _pump(WidgetTester tester, {required bool ready, bool? ext, String? seen}) async {
  SharedPreferences.setMockInitialValues({kSignatureSourcesSeenKey: ?seen});
  PackageInfo.setMockInitialValues(
      appName: 'OUI-APEX', packageName: 'oui_spy', version: '0.7.0', buildNumber: '1', buildSignature: '');
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('sources_prompt');
  addTearDown(() => dir.deleteSync(recursive: true));
  final asked = <Uri>[];
  final ble = _Ble(ready: ready, ext: ext);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    bleManagerProvider.overrideWithValue(ble),
    signatureSetsProvider.overrideWith((ref) => SignatureSets(
          fetch: (u) async {
            asked.add(u);
            return '{"fleets": []}';
          },
          dir: () async => dir,
          builtIn: () async => const [],
        )),
  ]);
  addTearDown(c.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: AppTheme.darkTheme, home: const _Host()),
  ));
  await tester.runAsync(() => c.read(signatureSetsProvider).loaded);
  return (c, ble, asked);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  for (var i = 0; i < 20 && find.text('Signature sources').evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

SwitchListTile _tile(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

void main() {
  testWidgets('lists every source, all off, extended OUI locked off without a board', (tester) async {
    final (c, ble, asked) = await _pump(tester, ready: false);
    await _open(tester);
    expect(find.text('OUI-APEX catalog'), findsOneWidget);
    expect(find.text('My signatures'), findsOneWidget);
    for (final s in ['Fieldwatch stock catalog', 'Home Assistant Bluetooth devices', 'Extended Flock OUI set']) {
      expect(_tile(tester, s).value, isFalse, reason: s);
    }
    expect(_tile(tester, 'Extended Flock OUI set').onChanged, isNull);
    expect(find.textContaining('Needs a connected board'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(c.read(sharedPreferencesProvider).getString(kSignatureSourcesSeenKey), '0.7.0');
    expect(c.read(signatureSetsProvider).enabledCount, 0);
    expect(asked, isEmpty);
    expect(ble.writes, isEmpty);
  });

  testWidgets('Save turns on the picked sets and the board extended OUI set', (tester) async {
    final (c, ble, asked) = await _pump(tester, ready: true, ext: false);
    await _open(tester);
    final ext = _tile(tester, 'Extended Flock OUI set');
    expect(ext.value, isFalse);
    expect(ext.onChanged, isNotNull);
    expect(find.textContaining('Saved on the board'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Home Assistant Bluetooth devices'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Extended Flock OUI set'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 50 && (asked.isEmpty || c.read(signatureSetsProvider).busy.isNotEmpty); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final sets = c.read(signatureSetsProvider).sets;
    expect(sets.firstWhere((s) => s.id == 'home-assistant').enabled, isTrue);
    expect(sets.firstWhere((s) => s.id == 'fieldwatch').enabled, isFalse);
    expect(asked.single.path, endsWith('homeassistant/generated/bluetooth.py'));
    expect(ble.writes, [true]);
    expect(c.read(sharedPreferencesProvider).getString(kSignatureSourcesSeenKey), '0.7.0');
  });

  testWidgets('does not ask again for a version already answered', (tester) async {
    await _pump(tester, ready: false, seen: '0.7.0');
    await tester.tap(find.text('open'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Signature sources'), findsNothing);
  });
}
