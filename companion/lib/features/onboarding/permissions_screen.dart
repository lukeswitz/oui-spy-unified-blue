import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oui_spy/core/ble/ble_permissions.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';

const kPermissionsOnboardedKey = 'permissions_onboarded_v2';

class PermissionStep {
  const PermissionStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.request,
    this.done,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String body;
  final Future<void> Function(WidgetRef ref) request;
  final Future<bool> Function()? done;
  final String? hint;
}

Future<List<PermissionStep>> pendingPermissionSteps(
  SharedPreferences prefs, [
  List<PermissionStep>? steps,
]) async {
  final all = steps ?? defaultPermissionSteps();
  if (prefs.getKeys().isEmpty) return all;
  if (prefs.getBool(kPermissionsOnboardedKey) ?? false) return const [];
  return [
    for (final step in all)
      if (step.done != null && !await step.done!()) step,
  ];
}

Future<void> _requestBluetooth(WidgetRef ref) async {
  if (Platform.isAndroid) {
    await BlePermissions.requestBluetoothOnly();
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

bool _alwaysRequestIgnored = false;

Future<bool> _askAlwaysIos() async {
  if (await Geolocator.checkPermission() == LocationPermission.denied) {
    await Geolocator.requestPermission();
  }
  final shown = Completer<void>();
  final answered = Completer<void>();
  final listener = AppLifecycleListener(
    onInactive: () {
      if (!shown.isCompleted) shown.complete();
    },
    onResume: () {
      if (shown.isCompleted && !answered.isCompleted) answered.complete();
    },
  );
  try {
    unawaited(ph.Permission.locationAlways.request().catchError((Object e) {
      DebugLog.log('ONBOARD: Always request failed: $e');
      return ph.PermissionStatus.denied;
    }));
    await shown.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    DebugLog.log('ONBOARD: Always prompt shown=${shown.isCompleted}');
    if (!shown.isCompleted) return false;
    await answered.future;
    return true;
  } finally {
    listener.dispose();
  }
}

Future<bool> openAlwaysLocationSettings() async {
  if (Platform.isIOS &&
      !_alwaysRequestIgnored &&
      await Geolocator.checkPermission() != LocationPermission.deniedForever) {
    final answered = await _askAlwaysIos();
    _alwaysRequestIgnored = true;
    if (answered) return false;
  } else if (Platform.isAndroid) {
    var prompted = false;
    final listener = AppLifecycleListener(onInactive: () => prompted = true);
    try {
      final status = await ph.Permission.locationAlways.request();
      if (status.isGranted || prompted) return false;
    } finally {
      listener.dispose();
    }
  }
  await Geolocator.openAppSettings();
  return true;
}

Future<void> _requestLocationAlways(WidgetRef ref) async {
  if (await BlePermissions.alwaysLocationGranted()) return;
  final back = Completer<void>();
  final listener = AppLifecycleListener(onResume: () {
    if (!back.isCompleted) back.complete();
  });
  try {
    final inSettings = await openAlwaysLocationSettings();
    if (inSettings && !await BlePermissions.alwaysLocationGranted()) await back.future;
  } finally {
    listener.dispose();
  }
}

Future<void> _requestNotifications(WidgetRef ref) =>
    ref.read(notificationServiceProvider).init();

List<PermissionStep> defaultPermissionSteps() => [
      PermissionStep(
        icon: Icons.bluetooth,
        title: 'Bluetooth',
        body: 'OUI-APEX uses Bluetooth to find your board and receive what it '
            'detects. This device can also scan for Bluetooth devices around you '
            'on its own.${Platform.isAndroid ? '\n\nOn Android 12 and newer this '
                'permission is called "Nearby devices".' : ''}',
        request: _requestBluetooth,
      ),
      PermissionStep(
        icon: Icons.location_on_outlined,
        title: 'Location',
        body: 'Location puts each detection on the map and records where your '
            'wardrive sessions went. It also lets the app turn the radios off '
            'inside your exclusion zones.\n\n'
            '${Platform.isMacOS ? 'Choose Allow. macOS has one location setting, so this also keeps the map '
                'running in the background.' : 'Choose While Using the App, not Only This Time. The next screen '
                'changes it to all the time, which the map needs.'}',
        request: _requestLocation,
      ),
      if (Platform.isAndroid || Platform.isIOS)
        PermissionStep(
          icon: Icons.my_location,
          title: 'Location all the time',
          body: 'Wardriving with the screen off needs location set to '
              '${Platform.isAndroid ? '"Allow all the time"' : '"Always"'}. Without it, location '
              'stops reaching the app when the screen turns off, so the map and distance stop too.'
              '\n\n${Platform.isAndroid ? 'Continue opens the location page in Settings. Choose Allow all the time, then go back. '
                  'If the app info page opens instead, tap Permissions, then Location first.' : 'Continue shows the prompt. Choose Change to Always Allow. iOS only shows it once, so if Settings '
                  'opens instead, choose Apps, OUI-APEX, Location, then Always, then come back.'}',
          hint: Platform.isAndroid ? 'Settings opens next.' : null,
          request: _requestLocationAlways,
          done: BlePermissions.alwaysLocationGranted,
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
  const PermissionsOnboardingApp({super.key, required this.onDone, required this.steps});

  final VoidCallback onDone;
  final List<PermissionStep> steps;

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
      home: PermissionsScreen(onDone: onDone, steps: steps),
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
  bool _notSet = false;

  void _advance() {
    if (_index == _steps.length - 1) {
      widget.onDone();
      return;
    }
    setState(() {
      _index++;
      _busy = false;
      _notSet = false;
    });
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    final step = _steps[_index];
    try {
      await step.request(ref);
    } catch (e) {
      DebugLog.log('ONBOARD: ${step.title} request failed: $e');
    }
    if (!mounted) return;
    final done = step.done;
    if (done != null && !await done()) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notSet = true;
      });
      return;
    }
    if (!mounted) return;
    _advance();
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
                'OUI-APEX needs ${_steps.length} ${_steps.length == 1 ? 'permission' : 'permissions'} to work. '
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
                _notSet
                    ? 'Not set yet. Wardriving stops when the screen turns off until this is set.'
                    : step.hint ?? 'Your device asks you next. You can change this later in Settings.',
                style: TextStyle(color: _notSet ? AppTheme.error : t.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (_notSet) ...[
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(onPressed: _advance, child: const Text('Skip for now')),
                ),
                const SizedBox(height: 8),
              ],
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
