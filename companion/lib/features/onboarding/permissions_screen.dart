import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/ble/ble_permissions.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';

const kPermissionsOnboardedKey = 'permissions_onboarded';

bool needsPermissionOnboarding(SharedPreferences prefs) => prefs.getKeys().isEmpty;

class PermissionStep {
  const PermissionStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.request,
  });

  final IconData icon;
  final String title;
  final String body;
  final Future<void> Function(WidgetRef ref) request;
}

Future<void> _requestBluetooth(WidgetRef ref) async {
  if (Platform.isAndroid) {
    await BlePermissions.ensureForScan();
    return;
  }
  await FlutterBluePlus.adapterState
      .firstWhere((s) => s != BluetoothAdapterState.unknown)
      .timeout(const Duration(seconds: 60), onTimeout: () => BluetoothAdapterState.unknown);
}

Future<void> _requestLocation(WidgetRef ref) async {
  if (await Geolocator.checkPermission() == LocationPermission.denied) {
    await Geolocator.requestPermission();
  }
}

Future<void> _requestNotifications(WidgetRef ref) =>
    ref.read(notificationServiceProvider).init();

List<PermissionStep> defaultPermissionSteps() => [
      PermissionStep(
        icon: Icons.bluetooth,
        title: 'Bluetooth',
        body: 'OUI-APEX uses Bluetooth to find your board and receive what it '
            'detects. Your phone can also scan for Bluetooth devices around you '
            'on its own.${Platform.isAndroid ? '\n\nOn Android 12 and newer this '
                'permission is called "Nearby devices".' : ''}',
        request: _requestBluetooth,
      ),
      const PermissionStep(
        icon: Icons.location_on_outlined,
        title: 'Location',
        body: 'Location puts each detection on the map and records where your '
            'wardrive sessions went. It also lets the app turn the radios off '
            'inside your exclusion zones.\n\nTo keep wardriving with the screen '
            'off, the app asks for "Always" access later, when you start a session.',
        request: _requestLocation,
      ),
      const PermissionStep(
        icon: Icons.notifications_outlined,
        title: 'Notifications',
        body: 'Notifications tell you when the app finds a tracker, a camera or '
            'something on your watchlist, even while the app is in the background.',
        request: _requestNotifications,
      ),
    ];

class PermissionsOnboardingApp extends ConsumerWidget {
  const PermissionsOnboardingApp({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appStyleProvider);
    final mode = ref.watch(themeModeProvider);
    final brightness = style.brightness ??
        switch (mode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness,
        };
    AppTheme.accent = style.accent;
    AppTheme.mono = style.monoFamily;
    AppTheme.applyBrightness(brightness);
    return MaterialApp(
      title: 'OUI-APEX',
      theme: AppTheme.themeFor(style, brightness),
      debugShowCheckedModeBanner: false,
      home: PermissionsScreen(onDone: onDone),
    );
  }
}

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key, required this.onDone, this.steps});

  final VoidCallback onDone;
  final List<PermissionStep>? steps;

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  late final List<PermissionStep> _steps = widget.steps ?? defaultPermissionSteps();
  int _index = 0;
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    final step = _steps[_index];
    try {
      await step.request(ref);
    } catch (e) {
      DebugLog.log('ONBOARD: ${step.title} request failed: $e');
    }
    if (!mounted) return;
    if (_index == _steps.length - 1) {
      widget.onDone();
      return;
    }
    setState(() {
      _index++;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final step = _steps[_index];
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OUI-APEX needs ${_steps.length} permissions to work. '
                'Step ${_index + 1} of ${_steps.length}.',
                style: TextStyle(color: t.textDim, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: EdgeInsets.only(right: i == _steps.length - 1 ? 0 : 6),
                        color: i <= _index ? AppTheme.accent : t.border,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Icon(step.icon, size: 64, color: AppTheme.accent),
              const SizedBox(height: 20),
              DPageTitle(step.title),
              const SizedBox(height: 12),
              Text(
                step.body,
                style: TextStyle(color: t.textSecondary, fontSize: 16, height: 1.4),
              ),
              const Spacer(),
              Text(
                'Your phone asks you next. You can change this later in Settings.',
                style: TextStyle(color: t.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _continue,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
