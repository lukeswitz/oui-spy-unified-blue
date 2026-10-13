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
import 'package:oui_spy/features/wardrive/wardrive_screen.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/theme/app_theme.dart';

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
    if (AppTheme.accent != style.accent) {
      AppTheme.accent = style.accent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (context as Element).visitChildren(_rebuildAll);
      });
    }
    final fixed = style.brightness;
    return MaterialApp.router(
      title: 'OUI-SPY',
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
                    color: const Color(0xFF1E2A28),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => ref.read(routerProvider).push('/engine/pcap'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.fiber_manual_record, color: Color(0xFF4AFFCC), size: 12),
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
                                style: const TextStyle(
                                  color: Color(0xFF4AFFCC),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            const Icon(Icons.open_in_new, color: Colors.white70, size: 14),
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

  void _onNavTap(int i) {
    final alreadyHere = _routes[i] == GoRouterState.of(context).uri.path;
    if (i == _configIndex && alreadyHere) {
      ref.read(configMenuWantedProvider.notifier).state = true;
    }
    if (!alreadyHere) {
      context.go(_routes[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _routes.indexOf(location);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.of(context).border, width: 0.5)),
        ),
        child: BottomNavigationBar(
        currentIndex: index < 0 ? 0 : index,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'Detections',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      )),
    );
  }
}
