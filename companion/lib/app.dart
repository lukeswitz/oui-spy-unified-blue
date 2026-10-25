import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/features/config/config_menu_state.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/features/detections/detections_screen.dart';
import 'package:oui_spy/features/engines/detector_screen.dart';
import 'package:oui_spy/features/engines/foxhunter_screen.dart';
import 'package:oui_spy/features/engines/skyspy_screen.dart';
import 'package:oui_spy/features/engines/unipwn_screen.dart';
import 'package:oui_spy/features/export/export_screen.dart';
import 'package:oui_spy/features/home/home_screen.dart';
import 'package:oui_spy/features/onboarding/scan_screen.dart';
import 'package:oui_spy/features/pcap/pcap_screen.dart';
import 'package:oui_spy/features/pcap/pcap_library_screen.dart';
import 'package:oui_spy/features/sdr/sdr_screen.dart';
import 'package:oui_spy/features/wardrive/wardrive_screen.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';

final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/detections',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DetectionsScreen(),
            ),
          ),
          GoRoute(
            path: '/wardrive',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WardriveScreen(),
            ),
          ),
          GoRoute(
            path: '/config',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DeviceConfigScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/engine/detector',
        builder: (context, state) => const DetectorScreen(),
      ),
      GoRoute(
        path: '/engine/foxhunter',
        builder: (context, state) => const FoxhunterScreen(),
      ),
      GoRoute(
        path: '/engine/skyspy',
        builder: (context, state) => const SkySpyScreen(),
      ),
      GoRoute(
        path: '/engine/unipwn',
        builder: (context, state) => const UnipwnScreen(),
      ),
      GoRoute(
        path: '/export',
        builder: (context, state) => const ExportScreen(),
      ),
      GoRoute(
        path: '/engine/pcap',
        builder: (context, state) => const PcapScreen(),
      ),
      GoRoute(
        path: '/pcap/library',
        builder: (context, state) => const PcapLibraryScreen(),
      ),
      GoRoute(
        path: '/sdr',
        builder: (context, state) => const SdrScreen(),
      ),
    ],
  );
});

class OuiSpyApp extends ConsumerStatefulWidget {
  const OuiSpyApp({super.key});

  @override
  ConsumerState<OuiSpyApp> createState() => _OuiSpyAppState();
}

class _OuiSpyAppState extends ConsumerState<OuiSpyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(configMenuWantedProvider.notifier).state = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      ref.read(wardriveProvider).finalizeForShutdown();
      ref.read(bleManagerProvider).disconnectQuiet();
      ref.read(liveActivityServiceProvider).endAll();
      ref.read(notificationServiceProvider).cancelAll();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(bleManagerProvider).resyncOnResume();
      ref.read(notificationServiceProvider).refreshPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final style = ref.watch(appStyleProvider);
    ref.watch(use24HourTimeProvider); // loads AppTime.use24Hour at startup
    final fixed = style.brightness;
    final effective = fixed ??
        switch (themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness,
        };
    final accentChanged = AppTheme.accent != style.accent || AppTheme.mono != style.monoFamily;
    if (accentChanged) {
      AppTheme.accent = style.accent;
      AppTheme.mono = style.monoFamily;
    }
    if (AppTheme.applyBrightness(effective) | accentChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (context as Element).visitChildren(_rebuildAll);
      });
    }
    return MaterialApp.router(
      title: 'OUI-APEX',
      theme: AppTheme.themeFor(style, fixed ?? Brightness.light),
      darkTheme: AppTheme.themeFor(style, fixed ?? Brightness.dark),
      themeMode: fixed == null ? themeMode : (fixed == Brightness.dark ? ThemeMode.dark : ThemeMode.light),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _GlobalPcapBannerOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}

void _rebuildAll(Element e) {
  e.markNeedsBuild();
  e.visitChildren(_rebuildAll);
}

class _GlobalPcapBannerOverlay extends ConsumerWidget {
  const _GlobalPcapBannerOverlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleManagerProvider);
    final p = AppTheme.of(context);
    return StreamBuilder(
      stream: ble.pcapStats,
      initialData: ble.latestPcapStats,
      builder: (context, snap) {
        final s = snap.data;
        final showing = s != null && s.state == 1;
        return Stack(
          children: [
            Positioned.fill(child: child),
            if (showing)
              Positioned(
                left: 12, right: 12, bottom: kBottomNavigationBarHeight + 8,
                child: SafeArea(
                  top: false,
                  child: Material(
                    color: p.fill,
                    shape: Border.all(color: p.fillBorder),
                    child: InkWell(
                      onTap: () => ref.read(routerProvider).push('/engine/pcap'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: p.mark, size: 12),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                () {
                                  final nodeTag = s.sourceNodeId.isNotEmpty
                                      ? ' @${s.sourceNodeId}'
                                      : '';
                                  if (s.isAutoTriggered) {
                                    return 'AUTO-PCAP$nodeTag ${s.mode == 1 ? "BLE" : "WiFi"} · ${s.autoTriggerEngineName.toUpperCase()} ${s.autoTriggerMacStr} — ${(s.autoRemainingMs / 1000).ceil()}s left, ${_humanBytes(s.bytesWritten)}';
                                  }
                                  if (s.autoRemainingMs > 0) {
                                    return 'AUTO-PCAP$nodeTag ${s.mode == 1 ? "BLE" : "WiFi"} — ${(s.autoRemainingMs / 1000).ceil()}s left, ${_humanBytes(s.bytesWritten)}';
                                  }
                                  return 'PCAP ${s.mode == 1 ? "BLE" : "WiFi"} — ${s.uptimeMs ~/ 1000}s, ${_humanBytes(s.bytesWritten)}';
                                }(),
                                style: TextStyle(
                                  color: p.onFill,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            Icon(Icons.open_in_new, color: p.onFillDim, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _humanBytes(int n) {
    if (n < 1024) return '${n}B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
    return '${(n / 1024 / 1024).toStringAsFixed(2)}MB';
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _routes = ['/home', '/detections', '/wardrive', '/config'];
  static const _configIndex = 3;
  bool _sdrAutoOpened = false;

  void _onNavTap(int i) {
    final alreadyHere = _routes[i] == GoRouterState.of(context).uri.path;
    if (i == _configIndex && alreadyHere) {
      ref.read(configMenuWantedProvider.notifier).state = true;
    }
    if (!alreadyHere) {
      context.go(_routes[i]);
    }
  }

  Future<void> _askMuteNoisy(({String key, int count, int total}) p) async {
    final notif = ref.read(notificationServiceProvider);
    final label = NotificationService.muteLabel(p.key);
    final t = AppTheme.of(context);
    final mute = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Lots of alerts', style: TextStyle(color: t.textPrimary)),
        content: Text(
          '${p.total} notifications in the last minute, ${p.count} from $label. '
          'Turn off $label notifications? Detections are still logged.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Turn off $label')),
        ],
      ),
    );
    notif.resolveNoisy(mute ?? false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationServiceProvider.select((n) => n.noisyPrompt), (prev, p) {
      if (p != null && prev == null) _askMuteNoisy(p);
    });
    ref.listen(sdrPresentProvider, (prev, next) {
      final now = next.valueOrNull ?? false;
      if (!now) {
        _sdrAutoOpened = false;
        return;
      }
      if (!_sdrAutoOpened && GoRouterState.of(context).uri.path != '/sdr') {
        _sdrAutoOpened = true;
        context.push('/sdr');
      }
    });
    ref.listen(wifiAdapterStateProvider, (prev, next) {
      if (next.valueOrNull == WifiAdapterState.error &&
          prev?.valueOrNull != WifiAdapterState.error) {
        final t = AppTheme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('USB adapter needs access — unplug and replug it, then start again.'),
            backgroundColor: t.surface,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
    final location = GoRouterState.of(context).uri.path;
    final index = _routes.indexOf(location);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.of(context).rule)),
            ),
            child: BottomNavigationBar(
        currentIndex: index < 0 ? 0 : index,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            label: 'Detections',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
            ),
          ),
          if (index >= 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FractionallySizedBox(
                alignment: Alignment(-1 + 2 * index / (_routes.length - 1), 0),
                widthFactor: 1 / _routes.length,
                child: Container(
                  key: const ValueKey('nav-active-bar'),
                  height: 2,
                  color: AppTheme.of(context).textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
