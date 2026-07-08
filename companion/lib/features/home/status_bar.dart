import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';

import 'package:oui_spy/theme/app_theme.dart';

class StatusBar extends ConsumerStatefulWidget {
  const StatusBar({super.key});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  GpsPosition? _gpsPosition;
  StreamSubscription<GpsPosition>? _gpsSub;
  Timer? _uptimeTimer;

  @override
  void initState() {
    super.initState();
    final gps = ref.read(gpsProvider);
    _gpsPosition = gps.lastPosition;
    _gpsSub = gps.positionStream.listen((pos) {
      if (mounted) setState(() => _gpsPosition = pos);
    });
    _uptimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _uptimeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(
          bottom: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Connection chip
          _ConnectionChip(state: state.connectionState),
          const SizedBox(width: 10),
          // Uptime
          if (state.isConnected && state.sessionStartTime != null) ...[
            _InfoChip(
              icon: Icons.timer_outlined,
              label: _formatUptime(state.sessionUptime),
              color: t.textSecondary,
            ),
            const SizedBox(width: 10),
          ],
          // GPS
          _InfoChip(
            icon: Icons.satellite_alt,
            label: _gpsLabel,
            color: _gpsColor,
          ),
          const Spacer(),
          // Device name + node count — tap to switch device
          Flexible(
            child: InkWell(
            onTap: state.isConnected
                ? () async {
                    await ref.read(bleManagerProvider).disconnect();
                    if (context.mounted) context.push('/onboarding');
                  }
                : () => context.push('/onboarding'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                    state.nodeId.isNotEmpty ? state.nodeId : 'OUI-SPY',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      fontFamily: 'monospace',
                      color: state.isConnected
                          ? AppTheme.accent
                          : t.textDim,
                    ),
                  ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    state.isConnected ? Icons.swap_horiz : Icons.devices,
                    size: 12,
                    color: state.isConnected
                        ? AppTheme.accent
                        : t.textDim,
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}min';
    final s = d.inSeconds.remainder(60);
    return '${m}min${s.toString().padLeft(2, '0')}s';
  }

  Color get _gpsColor {
    final quality = _gpsPosition?.quality ?? GpsQuality.none;
    return switch (quality) {
      GpsQuality.good => AppTheme.gpsGood,
      GpsQuality.fair => AppTheme.gpsFair,
      GpsQuality.poor => AppTheme.gpsPoor,
      GpsQuality.none => AppTheme.gpsNone,
    };
  }

  String get _gpsLabel {
    final pos = _gpsPosition;
    if (pos == null) return '--';
    return '${pos.accuracy.toStringAsFixed(0)}m';
  }
}


class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state});
  final NodeConnectionState state;

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final isConnecting = state == NodeConnectionState.connecting ||
        state == NodeConnectionState.negotiating ||
        state == NodeConnectionState.syncing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnecting)
            SizedBox(
              width: 6,
              height: 6,
              child: CircularProgressIndicator(
                color: color,
                strokeWidth: 1.5,
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Color get _color {
    return switch (state) {
      NodeConnectionState.ready => AppTheme.success,
      NodeConnectionState.connecting ||
      NodeConnectionState.negotiating ||
      NodeConnectionState.syncing =>
        AppTheme.warning,
      NodeConnectionState.reconnecting => AppTheme.error,
      _ => AppTheme.textDim,
    };
  }

  String get _label {
    return switch (state) {
      NodeConnectionState.ready => 'LIVE',
      NodeConnectionState.connecting => 'LINKING',
      NodeConnectionState.negotiating => 'MTU',
      NodeConnectionState.syncing => 'SYNC',
      NodeConnectionState.reconnecting => 'LOST',
      NodeConnectionState.scanning => 'SCAN',
      _ => 'OFFLINE',
    };
  }
}


class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
