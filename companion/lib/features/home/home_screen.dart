import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/models/node.dart';
import 'package:oui_spy/features/home/engine_card.dart';
import 'package:oui_spy/features/home/status_bar.dart';
import 'package:oui_spy/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
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

// ---------------------------------------------------------------------------
// Disconnected — welcoming landing with branding + connect CTA
// ---------------------------------------------------------------------------

class _DisconnectedView extends StatelessWidget {
  const _DisconnectedView({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final isConnecting =
        state.connectionState == NodeConnectionState.connecting ||
            state.connectionState == NodeConnectionState.negotiating ||
            state.connectionState == NodeConnectionState.syncing;

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = (screenWidth * 0.08).clamp(24.0, 64.0);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Animated radar icon
            _PulsingRadar(active: isConnecting),
            const SizedBox(height: 32),
            // App title
            const Text(
              'OUI-SPY',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isConnecting
                  ? 'Establishing BLE connection...'
                  : 'Multi-engine RF intelligence platform',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // Connect button or spinner
            if (isConnecting)
              const _ConnectingIndicator()
            else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/onboarding'),
                  icon: const Icon(Icons.bluetooth, size: 18),
                  label: const Text('CONNECT DEVICE'),
                ),
              ),
            // Reconnecting banner
            if (state.connectionState == NodeConnectionState.reconnecting) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sync_problem, size: 14, color: AppTheme.error),
                    SizedBox(width: 8),
                    Text(
                      'CONNECTION LOST — RECONNECTING',
                      style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 11,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 48),
            // Feature highlights
            const _FeatureRow(
              icon: Icons.radar,
              color: AppTheme.detector,
              title: 'Detect',
              subtitle: 'BLE watchlist & Flock Safety',
            ),
            const SizedBox(height: 16),
            const _FeatureRow(
              icon: Icons.flight,
              color: AppTheme.skySpy,
              title: 'Track',
              subtitle: 'FAA Remote ID drone detection',
            ),
            const SizedBox(height: 16),
            const _FeatureRow(
              icon: Icons.smart_toy,
              color: AppTheme.uniPwn,
              title: 'Exploit',
              subtitle: 'Unitree robot security testing',
            ),
            const SizedBox(height: 16),
            const _FeatureRow(
              icon: Icons.drive_eta,
              color: Color(0xFFFFFF4A),
              title: 'Wardrive',
              subtitle: 'WiGLE-compatible RF capture',
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
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = widget.active ? _controller.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accent.withValues(
                        alpha: widget.active ? 0.1 + pulse * 0.15 : 0.08),
                    width: 1,
                  ),
                ),
              ),
              // Middle ring
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accent.withValues(
                        alpha: widget.active ? 0.15 + pulse * 0.2 : 0.12),
                    width: 1,
                  ),
                ),
              ),
              // Inner filled circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withValues(
                      alpha: widget.active ? 0.08 + pulse * 0.08 : 0.06),
                ),
                child: Icon(
                  Icons.radar,
                  size: 24,
                  color: widget.active
                      ? AppTheme.accent
                      : AppTheme.textDim,
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
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            color: AppTheme.accent,
            strokeWidth: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'CONNECTING',
          style: TextStyle(
            color: AppTheme.accent.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Connected — responsive engine grid with live stats
// ---------------------------------------------------------------------------

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossCount = width > 600 ? 4 : (width > 400 ? 2 : 2);
        final pad = (width * 0.03).clamp(8.0, 16.0);

        return SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick stats strip
              if (state.totalDetections > 0) _QuickStats(state: state),
              if (state.totalDetections > 0) SizedBox(height: pad),
              // BLE Radio section
              _SectionHeader(
                label: 'BLE RADIO',
                subtitle: 'Shared scan — all run simultaneously',
                icon: Icons.bluetooth,
                color: AppTheme.accent,
              ),
              const SizedBox(height: 8),
              _EngineGrid(
                engines: const [
                  Engine.detector,
                  Engine.flockBle,
                  Engine.foxhunter,
                  Engine.uniPwn,
                ],
                state: state,
                crossCount: crossCount,
                width: width,
              ),
              const SizedBox(height: 20),
              // WiFi Radio section
              _SectionHeader(
                label: 'WIFI RADIO',
                subtitle: 'Exclusive — only one at a time',
                icon: Icons.wifi,
                color: AppTheme.warning,
              ),
              const SizedBox(height: 8),
              _EngineGrid(
                engines: const [Engine.flockWifi, Engine.skySpy],
                state: state,
                crossCount: crossCount,
                width: width,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final activeCount =
        Engine.values.where((e) => state.isEngineActive(e)).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(
        children: [
          _StatChip(
            value: '${state.totalDetections}',
            label: 'DETECTIONS',
            color: AppTheme.accent,
          ),
          const SizedBox(width: 20),
          _StatChip(
            value: '$activeCount',
            label: 'ACTIVE',
            color: AppTheme.success,
          ),
          if (state.meshEnabled) ...[
            const SizedBox(width: 20),
            _StatChip(
              value: '${state.meshConnectedPeers}',
              label: 'MESH',
              color: AppTheme.flockBle,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _EngineGrid extends StatelessWidget {
  const _EngineGrid({
    required this.engines,
    required this.state,
    required this.crossCount,
    required this.width,
  });
  final List<Engine> engines;
  final AppState state;
  final int crossCount;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Compute aspect ratio based on available card width
    final spacing = 8.0;
    final cardWidth = (width - spacing * (crossCount - 1)) / crossCount;
    // Target ~110px card height on mobile, taller on wider screens
    final targetHeight = cardWidth < 180 ? 110.0 : 120.0;
    final aspectRatio = cardWidth / targetHeight;

    return GridView.count(
      crossAxisCount: crossCount,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: aspectRatio,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: engines
          .map((e) => EngineCard(
                engine: e,
                detectionCount: state.countForEngine(e),
                isActive: state.isEngineActive(e),
                engineState: state.getEngineState(e),
              ))
          .toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
