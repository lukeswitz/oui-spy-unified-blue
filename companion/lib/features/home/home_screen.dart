import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/home/engine_card.dart';
import 'package:oui_spy/features/home/status_bar.dart';
import 'package:oui_spy/theme/app_theme.dart';

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
              child: state.isConnected
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

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = (screenWidth * 0.08).clamp(24.0, 64.0);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            const SizedBox(height: 40),
            _PulsingRadar(active: isConnecting || isReconnecting),
            const SizedBox(height: 28),
            Text(
              'OUI-SPY',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w200,
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
              style: TextStyle(
                color: t.textDim,
                fontSize: 12,
                letterSpacing: 1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            if (isConnecting) ...[
              const _ConnectingIndicator(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(bleManagerProvider).disconnect(),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text(
                    'CANCEL',
                    style: TextStyle(letterSpacing: 2, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                      color: AppTheme.error.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (!isReconnecting)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/onboarding'),
                  icon: const Icon(Icons.bluetooth, size: 16),
                  label: const Text(
                    'CONNECT',
                    style: TextStyle(letterSpacing: 2, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (isReconnecting) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'RECONNECTING…',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(bleManagerProvider).disconnect(),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text(
                    'STOP RECONNECT',
                    style: TextStyle(letterSpacing: 2, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                      color: AppTheme.error.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 48),
            ...Engine.values.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EnginePreviewRow(engine: e),
              ),
            ),
          ],
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
    return Column(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: AppTheme.accent.withValues(alpha: 0.6),
            strokeWidth: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'LINKING',
          style: TextStyle(
            color: AppTheme.accent.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
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
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: engine.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
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
                style: TextStyle(
                  color: engine.color.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                engine.description,
                style: TextStyle(
                  color: t.textDim,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectedView extends ConsumerWidget {
  const _ConnectedView({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);
    
    final pad = 12.0;

    final ble = ref.read(bleManagerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpoolImportBanner(stream: ble.awayImport, pad: pad),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          _SummaryStrip(state: state),
          SizedBox(height: pad),

          _SectionLabel(label: 'WARDRIVE', color: Engine.wardrive.color),
          const SizedBox(height: 6),
          EngineCard(
            engine: Engine.wardrive,
            detectionCount: state.countForEngine(Engine.wardrive),
            isActive: _isEngineOn(Engine.wardrive, state, wd),
            engineState: state.getEngineState(Engine.wardrive),
            lastDetection: state.lastDetectionTime[Engine.wardrive],
            rate: state.detectionRate(Engine.wardrive),
            size: CardSize.hero,
            nodeCount: 0,
          ),

          SizedBox(height: pad),

          _SectionLabel(label: 'FLOCK SAFETY', color: AppTheme.flockBle),
          const SizedBox(height: 6),
          SizedBox(
            height: _mediumCardHeight(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _sizedCard(Engine.flockBle, CardSize.medium, state, wd),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sizedCard(Engine.flockWifi, CardSize.medium, state, wd),
                ),
              ],
            ),
          ),

          SizedBox(height: pad),

          _SectionLabel(label: 'TRACKING', color: AppTheme.detector),
          const SizedBox(height: 6),
          SizedBox(
            height: _mediumCardHeight(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _sizedCard(Engine.detector, CardSize.medium, state, wd),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sizedCard(Engine.foxhunter, CardSize.medium, state, wd),
                ),
              ],
            ),
          ),

          SizedBox(height: pad),

          _SectionLabel(label: 'SPECIALTY', color: AppTheme.skySpy),
          const SizedBox(height: 6),
          _sizedCard(Engine.skySpy, CardSize.compact, state, wd),
          const SizedBox(height: 6),
          _sizedCard(Engine.uniPwn, CardSize.compact, state, wd),
          const SizedBox(height: 6),
          _sizedCard(Engine.pcap, CardSize.compact, state, wd),

          SizedBox(height: pad),

          if (state.recentDetections.isNotEmpty)
            _RecentActivity(state: state),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Determine if engine appears active — accounts for wardrive flock mode.
  double _mediumCardHeight(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 380) return 170;
    if (w < 420) return 180;
    return 190;
  }

  bool _isEngineOn(Engine engine, AppState state, WardriveController wd) {
    if (wd.isActive) {
      if (engine == Engine.wardrive) return true;
      final activeEngines = wd.activeEngines;
      if (activeEngines.contains(engine)) return true;
      if (wd.includesFlock) {
        if (engine == Engine.flockBle || engine == Engine.flockWifi) return true;
      }
    }
    return state.isEngineActive(engine);
  }

  Widget _sizedCard(Engine e, CardSize size, AppState state, WardriveController wd) {
    return EngineCard(
      engine: e,
      detectionCount: state.countForEngine(e),
      isActive: _isEngineOn(e, state, wd),
      engineState: state.getEngineState(e),
      lastDetection: state.lastDetectionTime[e],
      rate: state.detectionRate(e),
      size: size,
      nodeCount: 0,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    
    final activeCount =
        Engine.values.where((e) => state.isEngineActive(e)).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          _StatItem(
            value: '${state.totalDetections}',
            label: 'UNIQUE',
            color: AppTheme.accent,
          ),
          _divider(t),
          _StatItem(
            value: '$activeCount/${Engine.values.length}',
            label: 'ENGINES',
            color: activeCount > 0 ? AppTheme.success : t.textDim,
          ),
          _divider(t),
          _StatItem(
            value: '${state.totalRate}',
            label: '/MIN',
            color: state.totalRate > 0 ? AppTheme.warning : t.textDim,
          ),
          if (state.isManagerConnected) ...[
            _divider(t),
            Builder(builder: (_) {
              final selfId = AppState.canonicalNodeId(state.nodeId);
              final nodeCount = state.liveKnownNodes
                  .where((id) => id != selfId && !state.isManagerNode(id))
                  .length;
              return InkWell(
                onTap: () async {
                  if (state.meshEnabled) {
                    await state.disableMesh();
                  } else {
                    await state.enableMesh(
                        encryption: false, peerMacs: const []);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: _StatItem(
                    icon: Icons.hub,
                    value: state.meshEnabled ? '$nodeCount' : 'OFF',
                    label: 'NODES',
                    color: state.meshEnabled
                        ? (nodeCount > 0
                            ? AppTheme.success
                            : AppTheme.warning)
                        : t.textDim,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _divider(ResolvedTheme t) {
    return Container(
      width: 0.5,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: t.border,
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
    this.icon,
  });
  final String value;
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final recent = state.recentDetections.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'RECENT',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            children: recent.asMap().entries.map((entry) {
              final det = entry.value;
              final isLast = entry.key == recent.length - 1;
              final engineColor = det.engine.color;
              final age = DateTime.now().difference(det.appTimestamp);
              final ageStr = age.inSeconds < 60
                  ? '${age.inSeconds}s'
                  : '${age.inMinutes}m';

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: t.border,
                            width: 0.5,
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: engineColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      det.macAddress.toUpperCase(),
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        det.deviceName.isNotEmpty
                            ? det.deviceName
                            : det.ssid.isNotEmpty
                                ? det.ssid
                                : '<hidden>',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${det.rssi}',
                      style: TextStyle(
                        color: _rssiColor(det.rssi),
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      ageStr,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi > -50) return AppTheme.success;
    if (rssi > -70) return AppTheme.warning;
    return AppTheme.textDim;
  }
}

class _SpoolImportBanner extends StatefulWidget {
  const _SpoolImportBanner({required this.stream, required this.pad});
  final Stream<SpoolImportProgress> stream;
  final double pad;

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
      message = 'Imported ${p.seen} detection(s) while away$suffix';
      color = AppTheme.accent;
      icon = Icons.check_circle_outline;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.pad, widget.pad, widget.pad, 0),
      child: GestureDetector(
        onTap: _dismiss,
        child: _SpoolBanner(color: color, icon: icon, message: message),
      ),
    );
  }
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
