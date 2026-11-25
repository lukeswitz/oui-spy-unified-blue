// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/ota/mesh_firmware.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/features/config/mesh_firmware_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mesh_firmware_test.dart' show FakeLink, image;

class _FakePhoneSource extends ChangeNotifier implements PhoneBleSource {
  @override
  bool get active => false;

  @override
  bool get radioListening => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shows the loaded image, its SHA-256 and the empty node list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = MeshFirmwareController(FakeLink())..image = image();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      phoneBleSourceProvider.overrideWith((ref) => _FakePhoneSource()),
      meshFirmwareProvider.overrideWith((ref) => controller),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.darkTheme, home: const MeshFirmwareScreen()),
    ));
    await tester.pump();
    expect(find.text('FIRMWARE OVER THE MESH'), findsOneWidget);
    expect(find.text('ESP32-S3 (id 9)'), findsOneWidget);
    expect(find.textContaining('SHA-256  '), findsOneWidget);
    expect(find.text('No node heard on the mesh yet.'), findsOneWidget);
    expect(find.text('Pick a node'), findsOneWidget);
    expect(find.textContaining('Connect a manager'), findsOneWidget);
  });
}
