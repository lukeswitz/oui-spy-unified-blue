import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/gps/gps_types.dart';
import 'package:oui_spy/core/models/node.dart';
import 'package:oui_spy/theme/app_theme.dart';

class StatusBar extends ConsumerStatefulWidget {
  const StatusBar({super.key});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  GpsPosition? _gpsPosition;
  StreamSubscription<GpsPosition>? _gpsSub;
  int _nodeCount = 0;

  @override
  void initState() {
    super.initState();
    final gps = ref.read(gpsProvider);
    _gpsPosition = gps.lastPosition;
    _gpsSub = gps.positionStream.listen((pos) {
      if (mounted) setState(() => _gpsPosition = pos);
    });
    _loadNodeCount();
  }

  Future<void> _loadNodeCount() async {
    final db = ref.read(databaseProvider);
    final connectedId = ref.read(bleManagerProvider).connectedDeviceId;
    final nodes = await db.getAllNodes();
    final count = nodes.where((n) => n.id != connectedId).length;
    if (mounted) setState(() => _nodeCount = count);
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _StatusDot(color: _connectionColor(state.connectionState), label: _connectionLabel(state.connectionState)),
          const SizedBox(width: 16),
          _StatusDot(color: _gpsColor, label: _gpsLabel),
          if (state.totalDetections > 0) ...[
            const SizedBox(width: 16),
            Text(
              '${state.totalDetections}',
              style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () async {
              await context.push('/nodes');
              _loadNodeCount();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.nodeId.isNotEmpty ? state.nodeId : 'OUI-SPY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 2,
                        color: state.isConnected ? AppTheme.accent : AppTheme.textDim,
                      ),
                ),
                if (_nodeCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+$_nodeCount',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.devices, size: 12,
                    color: state.isConnected ? AppTheme.accent : AppTheme.textDim),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _connectionColor(NodeConnectionState s) {
    return switch (s) {
      NodeConnectionState.ready => AppTheme.success,
      NodeConnectionState.connecting || NodeConnectionState.negotiating || NodeConnectionState.syncing => AppTheme.warning,
      NodeConnectionState.reconnecting => AppTheme.error,
      _ => AppTheme.textDim,
    };
  }

  String _connectionLabel(NodeConnectionState s) {
    return switch (s) {
      NodeConnectionState.ready => 'CONNECTED',
      NodeConnectionState.connecting => 'CONNECTING',
      NodeConnectionState.negotiating => 'MTU',
      NodeConnectionState.syncing => 'SYNCING',
      NodeConnectionState.reconnecting => 'RECONNECTING',
      NodeConnectionState.scanning => 'SCANNING',
      _ => 'DISCONNECTED',
    };
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
    if (pos == null) return 'NO GPS';
    return '${pos.accuracy.toStringAsFixed(0)}m';
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color, letterSpacing: 1,
            )),
      ],
    );
  }
}
