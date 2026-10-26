import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_provider.dart';
import 'package:oui_spy/features/config/config_menu_state.dart';
import 'package:oui_spy/features/detections/detections_screen.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/home/engine_card.dart';
import 'package:oui_spy/features/home/status_bar.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_spec_row.dart';
import 'package:oui_spy/widgets/d/d_stats_strip.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: state.isConnected ||
                      ref.watch(phoneBleSourceProvider).active ||
                      (ref.watch(sdrPresentProvider).valueOrNull ?? false) ||
                      const {
                        WifiAdapterState.present,
                        WifiAdapterState.starting,
                        WifiAdapterState.running,
                      }.contains(ref.watch(wifiAdapterStateProvider).valueOrNull ??
                          ref.watch(wifiAdapterControllerProvider).state)
                  ? _ConnectedView(state: state)
                  : _DisconnectedView(state: state),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectedView extends ConsumerWidget {
  const _DisconnectedView({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final isConnecting =
        state.connectionState == NodeConnectionState.connecting ||
            state.connectionState == NodeConnectionState.negotiating ||
            state.connectionState == NodeConnectionState.syncing;
    final isReconnecting =
        state.connectionState == NodeConnectionState.reconnecting;

    final hPad = (MediaQuery.sizeOf(context).width * 0.08).clamp(24.0, 64.0);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            _PulsingRadar(active: isConnecting || isReconnecting),
            const SizedBox(height: 28),
            Text(
              'OUI-APEX',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isConnecting
                  ? 'Establishing BLE link...'
                  : isReconnecting
                      ? 'Searching for your OUI-SPY…'
                      : 'Multi-engine RF intelligence',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textDim, fontSize: 12, letterSpacing: 1),
            ),
            const SizedBox(height: 40),
            if (isConnecting) ...[
              const _ConnectingIndicator(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(bleManagerProvider).disconnect(),
                  icon: const Icon(Icons.close, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error),
                  ),
                  label: const Text('CANCEL'),
                ),
              ),
            ] else if (!isReconnecting)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/onboarding'),
                  icon: const Icon(Icons.bluetooth, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(color: AppTheme.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                  ),
                  label: const Text('CONNECT', style: TextStyle(letterSpacing: 2, fontSize: 13)),
                ),
              ),
            if (isReconnecting) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const DEyebrow('RECONNECTING…'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(bleManagerProvider).disconnect(),
                  icon: const Icon(Icons.close, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error),
                  ),
                  label: const Text('STOP RECONNECT'),
                ),
              ),
            ],
            const SizedBox(height: 48),
            for (final e in Engine.values) _EnginePreviewRow(engine: e),
            const SizedBox(height: 8),
            const _WardriveAccountsStrip(),
          ],
          ),
        ),
      ),
    );
  }
}

class _PulsingRadar extends StatefulWidget {
  const _PulsingRadar({required this.active});
  final bool active;

  @override
  State<_PulsingRadar> createState() => _PulsingRadarState();
}

class _PulsingRadarState extends State<_PulsingRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return SizedBox(
      width: 80,
      height: 80,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = widget.active ? _controller.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accent.withValues(
                      alpha: widget.active ? 0.06 + pulse * 0.12 : 0.06,
                    ),
                    width: 0.5,
                  ),
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accent.withValues(
                      alpha: widget.active ? 0.1 + pulse * 0.15 : 0.08,
                    ),
                    width: 0.5,
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withValues(
                    alpha: widget.active ? 0.06 + pulse * 0.06 : 0.04,
                  ),
                ),
                child: Icon(
                  Icons.radar,
                  size: 18,
                  color: widget.active ? AppTheme.accent : t.textDim,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectingIndicator extends StatelessWidget {
  const _ConnectingIndicator();

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            color: t.textPrimary,
            strokeWidth: 1.5,
          ),
        ),
        const SizedBox(width: 10),
        const DEyebrow('LINKING'),
      ],
    );
  }
}

class _EnginePreviewRow extends StatelessWidget {
  const _EnginePreviewRow({required this.engine});
  final Engine engine;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: engine.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(engine.icon, size: 14, color: engine.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  engine.label,
                  style: TextStyle(color: engine.color, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  engine.description,
                  maxLines: 2,
                  style: TextStyle(color: t.textDim, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedView extends ConsumerWidget {
  const _ConnectedView({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);
    final ble = ref.read(bleManagerProvider);
    final recent = state.recentDetections.take(5).toList();
    final sessionEngines = <Engine>{
      if (wd.isRunning)
        for (final t in wd.selectedTargets) ...t.engines(wd.radio),
    };
    final activeCount = Engine.values
        .where((e) => state.isEngineActive(e) || sessionEngines.contains(e))
        .length;
    final selfId = AppState.canonicalNodeId(state.nodeId);
    final nodeCount = state.liveKnownNodes
        .where((id) => id != selfId && !state.isManagerNode(id))
        .length;
    final stats = <(String, String)>[
      ('${state.totalDetections}', 'Unique'),
      ('$activeCount/${Engine.values.length}', 'Engines'),
      ('${state.totalRate}', 'Per min'),
      if (state.isManagerConnected) (state.meshEnabled ? '$nodeCount' : 'OFF', 'Nodes'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpoolImportBanner(stream: ble.awayImport),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DStatsStrip(
                        items: stats,
                        onTap: (i) {
                          if (stats[i].$2 != 'Nodes') return;
                          ref.read(configSectionRequestProvider.notifier).state = 'NODE';
                          context.go('/config');
                        },
                      ),
                      DSectionHeader(
                        label: 'Scan',
                        trailing: Text(
                          wd.radioTransition != null
                              ? '${wd.radioTransition![0].toUpperCase()}${wd.radioTransition!.substring(1)}…'
                              : switch (wd.state) {
                                  WardriveState.idle => 'Idle',
                                  WardriveState.running => 'Running',
                                  WardriveState.paused => 'Paused',
                                },
                          style: TextStyle(
                            color: wd.state == WardriveState.running && wd.radioTransition == null
                                ? AppTheme.accent
                                : AppTheme.of(context).textSecondary,
                          ),
                        ),
                      ),
                      _panel(context, 'scan', const [
                        _UsbScanSources(),
                        SessionTargets(),
                        SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: SessionStartButton(),
                        ),
                      ]),
                      const DSectionHeader(label: 'Safety'),
                      _engineGroup(context, 'safety', [Engine.flockWifi, Engine.flockBle], state, wd),
                      const DSectionHeader(label: 'Tracking'),
                      _engineGroup(context, 'tracking', [Engine.detector, Engine.skySpy], state, wd),
                      const DSectionHeader(label: 'Specialty'),
                      _engineGroup(context, 'specialty', [Engine.foxhunter, Engine.uniPwn, Engine.pcap], state, wd),
                      if (recent.isNotEmpty) ...[
                        DSectionHeader(
                          label: 'Recent activity',
                          trailing: TextButton(
                            onPressed: () {
                              ref.read(detectionsViewProvider.notifier).state =
                                  DetectionsView.live;
                              context.go('/detections');
                            },
                            child: const Text('All'),
                          ),
                        ),
                        _panel(context, 'recent', [
                          for (final d in recent)
                            DetectionRow(
                              key: ValueKey(d.id),
                              detection: d,
                              divider: false,
                              horizontal: 14,
                            ),
                        ], indent: 14),
                      ],
                      const _WardriveAccountsStrip(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context, String id, List<Widget> rows, {double indent = 62}) {
    final t = AppTheme.of(context);
    return Container(
      key: ValueKey('group-$id'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: indent, color: t.border),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _engineGroup(BuildContext context, String id, List<Engine> engines, AppState state, WardriveController wd) {
    return _panel(context, id, [for (final e in engines) _engineCard(e, state, wd)]);
  }

  bool _isEngineOn(Engine engine, AppState state, WardriveController wd) {
    if (wd.isActive && (engine == Engine.wardrive || wd.ownsEngine(engine))) return true;
    return state.isEngineActive(engine);
  }

  Widget _engineCard(Engine e, AppState state, WardriveController wd) {
    return EngineCard(
      engine: e,
      detectionCount: state.countForEngine(e),
      isActive: _isEngineOn(e, state, wd),
      engineState: state.getEngineState(e),
      lastDetection: state.lastDetectionTime[e],
      rate: state.detectionRate(e),
      nodeCount: 0,
    );
  }
}

class _SpoolImportBanner extends StatefulWidget {
  const _SpoolImportBanner({required this.stream});
  final Stream<SpoolImportProgress> stream;

  @override
  State<_SpoolImportBanner> createState() => _SpoolImportBannerState();
}

class _SpoolImportBannerState extends State<_SpoolImportBanner> {
  SpoolImportProgress? _p;
  StreamSubscription<SpoolImportProgress>? _sub;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(_onEvent);
  }

  void _onEvent(SpoolImportProgress p) {
    // Only the settled result is shown — no progress churn.
    if (!p.done && !p.aborted) return;
    if (p.done && !p.aborted && p.seen == 0) return;
    _hold?.cancel();
    _hold = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _p = null);
    });
    setState(() => _p = p);
  }

  void _dismiss() {
    _hold?.cancel();
    setState(() => _p = null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const SizedBox.shrink();
    final String message;
    final Color color;
    final IconData icon;
    if (p.aborted) {
      message = 'Import interrupted — will retry on reconnect';
      color = AppTheme.error;
      icon = Icons.sync_problem;
    } else {
      final suffix = p.dropped > 0
          ? ' (buffer was full, oldest ${p.dropped} dropped)'
          : '';
      final breakdown = _spoolBreakdown(p.byEngine);
      message = 'Imported ${p.seen} detection(s) while away'
          '${breakdown.isNotEmpty ? ' — $breakdown' : ''}$suffix';
      color = AppTheme.accent;
      icon = Icons.check_circle_outline;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GestureDetector(
        onTap: () {
          ProviderScope.containerOf(context, listen: false).read(detectionsViewProvider.notifier).state =
              DetectionsView.live;
          context.go('/detections');
          _dismiss();
        },
        child: _SpoolBanner(color: color, icon: icon, message: message),
      ),
    );
  }
}

String _spoolBreakdown(Map<String, int> byEngine) {
  if (byEngine.isEmpty) return '';
  const label = {
    'flockBle': 'flock',
    'flockWifi': 'flock',
    'skySpy': 'drone',
    'detector': 'detector',
    'wardrive': 'wardrive',
    'foxhunter': 'foxhunt',
  };
  final tally = <String, int>{};
  byEngine.forEach((k, v) {
    final name = label[k] ?? k;
    tally[name] = (tally[name] ?? 0) + v;
  });
  final parts = tally.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return parts.map((e) => '${e.value} ${e.key}').join(' · ');
}

class _SpoolBanner extends StatelessWidget {
  const _SpoolBanner({
    required this.color,
    required this.icon,
    required this.message,
  });
  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.close, size: 16, color: t.textDim),
        ],
      ),
    );
  }
}

class _WardriveAccountsStrip extends ConsumerWidget {
  const _WardriveAccountsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wigle = ref.watch(wigleProvider);
    final wdg = ref.watch(wdgwarsProvider);
    if (!wigle.isLoggedIn && !wdg.isLoggedIn) return const SizedBox.shrink();

    void open() {
      ProviderScope.containerOf(context, listen: false).read(configSectionRequestProvider.notifier).state = 'DATA';
      context.go('/config');
    }

    final t = AppTheme.of(context);
    final rows = <Widget>[];
    if (wigle.isLoggedIn) {
      final s = wigle.stats;
      rows.add(DSpecRow(
        label: 'WiGLE',
        mono: true,
        divider: false,
        onTap: open,
        value: wigle.rateLimited
            ? WigleApi.rateLimitMessage
            : s == null
            ? 'Loading…'
            : '#${s.rank} · ${_fmt(s.discoveredWiFi)} WiFi · ${_fmt(s.discoveredBt)} BT',
      ));
    }
    if (wdg.isLoggedIn) {
      final s = wdg.stats;
      rows.add(DSpecRow(
        label: 'WDGWars',
        mono: true,
        divider: false,
        onTap: open,
        value: s == null
            ? 'Loading…'
            : '${_fmt(s.total)} devices${s.gang.isNotEmpty ? ' · ${s.gang}' : ''}',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DSectionHeader(
          label: 'Wardrive accounts',
          trailing: TextButton(onPressed: open, child: const Text('Full stats')),
        ),
        Container(
          key: const ValueKey('group-accounts'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, indent: 14, color: t.border),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

class _UsbScanSources extends ConsumerWidget {
  const _UsbScanSources();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wifiState = ref.watch(wifiAdapterStateProvider).valueOrNull ??
        ref.watch(wifiAdapterControllerProvider).state;
    final ctl = ref.read(wifiAdapterControllerProvider);
    final sdrState = ref.watch(sdrStateProvider).valueOrNull ?? SdrState.idle;
    final sdrActive = sdrState == SdrState.running || sdrState == SdrState.starting;
    final sdrPresent = ref.watch(sdrPresentProvider).valueOrNull ?? false;
    final selected = ref.watch(usbAdapterScanProvider);
    final wifiRunning =
        wifiState == WifiAdapterState.running || wifiState == WifiAdapterState.starting;

    final tiles = <Widget>[
      for (final d in ctl.devices)
        _SourceTile(
          icon: Icons.wifi,
          title: d.name.isNotEmpty ? d.name : 'USB Wi-Fi',
          subtitle: wifiRunning ? 'Scanning' : 'USB ${d.vidPid}',
          on: selected,
          trailing: Switch(
            value: selected,
            onChanged: (v) {
              ref.read(usbAdapterScanProvider.notifier).state = v;
              if (!v && wifiRunning) ctl.stop();
            },
          ),
        ),
      if (sdrPresent || sdrActive)
        _SourceTile(
          icon: Icons.sensors,
          title: 'RTL-SDR',
          subtitle: sdrActive ? 'Scanning' : 'Connected · open to scan',
          on: sdrActive,
          trailing: TextButton(
            onPressed: () => context.push('/sdr'),
            child: const Text('OPEN', style: TextStyle(fontSize: 11, letterSpacing: 1)),
          ),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    required this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool on;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final iconColor = on ? AppTheme.accent : t.textSecondary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(color: t.textDim, fontSize: 10, fontFamily: AppTheme.mono)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

