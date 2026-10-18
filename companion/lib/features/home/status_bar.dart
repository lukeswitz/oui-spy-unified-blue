import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/widgets/command_bar.dart';
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
  HwGpsState _hwGps = const HwGpsState(
      active: false, satellites: 0, source: GpsSource.phone, inUse: false);
  StreamSubscription<HwGpsState>? _hwGpsSub;
  Timer? _uptimeTimer;

  @override
  void initState() {
    super.initState();
    final gps = ref.read(gpsProvider);
    _gpsPosition = gps.lastPosition;
    _hwGps = gps.hwGps;
    _gpsSub = gps.positionStream.listen((pos) {
      if (mounted) setState(() => _gpsPosition = pos);
    });
    _hwGpsSub = gps.hwGpsStream.listen((s) {
      if (mounted) setState(() => _hwGps = s);
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
    _hwGpsSub?.cancel();
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
            icon: _hwGps.inUse ? Icons.memory : Icons.smartphone,
            label: _gpsLabel,
            color: _gpsColor,
          ),
          const Spacer(),
          const _PhoneScanChip(),
          const SizedBox(width: 10),
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
    if (_hwGps.inUse) return AppTheme.gpsGood;
    if (_hwGps.fallback) return AppTheme.warning;
    final quality = _gpsPosition?.quality ?? GpsQuality.none;
    return switch (quality) {
      GpsQuality.good => AppTheme.gpsGood,
      GpsQuality.fair => AppTheme.gpsFair,
      GpsQuality.poor => AppTheme.gpsPoor,
      GpsQuality.none => AppTheme.gpsNone,
    };
  }

  String get _gpsLabel {
    if (_hwGps.inUse) return 'HW ${_hwGps.satellites}sv';
    final pos = _gpsPosition;
    if (pos == null) return _hwGps.fallback ? 'PH --' : '--';
    final acc = '${pos.accuracy.toStringAsFixed(0)}m';
    return _hwGps.fallback ? 'PH $acc' : acc;
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


IconData get _phoneIcon => Platform.isAndroid
    ? Icons.phone_android
    : Platform.isMacOS
        ? Icons.laptop_mac
        : Icons.phone_iphone;

class _PhoneScanChip extends ConsumerWidget {
  const _PhoneScanChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final src = ref.watch(phoneBleSourceProvider);
    const color = AppTheme.detector;
    return Tooltip(
      message: 'Scan with this device',
      child: InkWell(
        onTap: () => showCommandSheet<void>(
          context: context,
          builder: (_) => const _PhoneScanSheet(),
        ),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: src.active ? 0.2 : 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: src.active ? 0.6 : 0.35), width: 0.5),
          ),
          child: Icon(
            src.radioListening ? Icons.wifi_tethering : _phoneIcon,
            size: 16,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _PhoneScanSheet extends ConsumerStatefulWidget {
  const _PhoneScanSheet();

  @override
  ConsumerState<_PhoneScanSheet> createState() => _PhoneScanSheetState();
}

class _PhoneScanSheetState extends ConsumerState<_PhoneScanSheet> {
  bool _showInfo = false;

  static String get _radios =>
      PhoneBleSource.canScanWifi ? 'Bluetooth and Wi-Fi' : 'Bluetooth only';

  static String get _limits => Platform.isAndroid
      ? 'Works with or without a board. Compared with a board: Android allows 4 Wi-Fi scans '
          'every 2 minutes, and 1 every 30 minutes in the background. Bluetooth scans '
          'continuously during a session, or on the BLE duration and interval settings when a board is connected. '
          'No Flock, drone ID, probe-request, deauth or PCAP detection.'
      : 'Bluetooth only, while the app is open. Apple hides device MAC addresses, so these hits '
          'cannot be foxhunted or uploaded to WiGLE. No Wi-Fi, Flock, drone ID or PCAP detection; '
          'those need a board.';

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final src = ref.watch(phoneBleSourceProvider);
    final status = !src.active
        ? _radios
        : !src.bluetoothOn
            ? 'Bluetooth is off'
            : !src.scanning
                ? 'Ready · press START to scan'
                : src.radioListening
                    ? 'Scanning · $_radios'
                    : 'Waiting for the radio · $_radios';
    return CommandSheet(
      title: 'THIS DEVICE',
      trailing: IconButton(
        tooltip: 'Limits',
        icon: Icon(_showInfo ? Icons.info : Icons.info_outline, size: 20, color: t.textDim),
        onPressed: () => setState(() => _showInfo = !_showInfo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConfigToggleRow(
            icon: _phoneIcon,
            label: 'Scan with this device',
            subtitle: status,
            color: AppTheme.detector,
            value: src.active,
            onChanged: src.setActive,
          ),
          if (_showInfo)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(_limits, style: TextStyle(color: t.textDim, fontSize: 13)),
            ),
        ],
      ),
    );
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
