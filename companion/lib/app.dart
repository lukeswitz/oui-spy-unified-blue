import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/features/config/device_config.dart';
import 'package:oui_spy/features/engines/detector_screen.dart';
import 'package:oui_spy/features/engines/foxhunter_screen.dart';
import 'package:oui_spy/features/engines/skyspy_screen.dart';
import 'package:oui_spy/features/engines/unipwn_screen.dart';
import 'package:oui_spy/features/export/export_screen.dart';
import 'package:oui_spy/features/feed/feed_screen.dart';
import 'package:oui_spy/features/home/home_screen.dart';
import 'package:oui_spy/features/onboarding/scan_screen.dart';
import 'package:oui_spy/features/pcap/pcap_screen.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/features/wardrive/wardrive_screen.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/notifications/live_activity_service.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
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
            path: '/feed',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FeedScreen(),
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(bleManagerProvider).disconnectQuiet();
      if (state == AppLifecycleState.detached) {
        ref.read(liveActivityServiceProvider).endAll();
        ref.read(notificationServiceProvider).cancelAll();
      }
    } else if (state == AppLifecycleState.resumed) {
      ref.read(bleManagerProvider).reconnectPrimary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'OUI-SPY',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _GlobalPcapBannerOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
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
                left: 12, right: 12, bottom: kBottomNavigationBarHeight + 76,
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
                                    return 'AUTO-PCAP${nodeTag} ${s.mode == 1 ? "BLE" : "WiFi"} · ${s.autoTriggerEngineName.toUpperCase()} ${s.autoTriggerMacStr} — ${(s.autoRemainingMs / 1000).ceil()}s left, ${_humanBytes(s.bytesWritten)}';
                                  }
                                  if (s.autoRemainingMs > 0) {
                                    return 'AUTO-PCAP${nodeTag} ${s.mode == 1 ? "BLE" : "WiFi"} — ${(s.autoRemainingMs / 1000).ceil()}s left, ${_humanBytes(s.bytesWritten)}';
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

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  static const _routes = ['/home', '/feed', '/wardrive', '/config'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          context.go(_routes[index]);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'FEED',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.drive_eta),
            label: 'WARDRIVE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'CONFIG',
          ),
        ],
      ),
    );
  }
}
