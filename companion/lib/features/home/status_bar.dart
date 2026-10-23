import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';
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

    final conn = state.connectionState;
    final lost = conn == NodeConnectionState.reconnecting || conn == NodeConnectionState.disconnected;
    final phoneOn = ref.watch(phoneBleSourceProvider).active;
    final wifiRunning = (ref.watch(wifiAdapterStateProvider).valueOrNull ??
            ref.watch(wifiAdapterControllerProvider).state) ==
        WifiAdapterState.running;
    final softScan = !state.isConnected && (phoneOn || wifiRunning);
    final scanLabel = phoneOn && wifiRunning
        ? 'Phone + USB scan'
        : wifiRunning
            ? 'USB scan'
            : 'Phone scan';
    final statusColor = softScan
        ? AppTheme.accent
        : lost
            ? AppTheme.error
            : conn == NodeConnectionState.ready
                ? AppTheme.accent
                : t.textSecondary;
    final sep = Text(' · ', style: TextStyle(color: t.textSecondary, fontSize: 13));
    final uptime = state.isConnected && state.sessionStartTime != null
        ? _formatUptime(state.sessionUptime)
        : null;
    final nameColor = state.isConnected ? t.textPrimary : t.textDim;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  !state.isConnected && !phoneOn && !wifiRunning
                      ? ''
                      : state.nodeId.isNotEmpty
                          ? state.nodeId
                          : 'OUI-APEX',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: nameColor, fontSize: 28, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: state.isConnected ? 'Switch device' : 'Connect a device',
                icon: Icon(state.isConnected ? Icons.swap_horiz : Icons.devices_outlined),
                color: nameColor,
                onPressed: state.isConnected
                    ? () async {
                        await ref.read(bleManagerProvider).disconnect();
                        if (context.mounted) context.push('/onboarding');
                      }
                    : () => context.push('/onboarding'),
              ),
              const _PhoneScanChip(),
              const _UsbScanChip(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  softScan ? scanLabel : _connectionWord(conn),
                  style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (uptime != null) ...[
                  sep,
                  Text(
                    uptime,
                    style: TextStyle(fontFamily: AppTheme.mono, fontSize: 13, color: t.textSecondary),
                  ),
                ],
                sep,
                Flexible(
                  child: Text(
                    _gpsLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _connectionWord(NodeConnectionState s) {
    return switch (s) {
      NodeConnectionState.ready => 'Live',
      NodeConnectionState.connecting => 'Linking',
      NodeConnectionState.negotiating => 'MTU',
      NodeConnectionState.syncing => 'Sync',
      NodeConnectionState.reconnecting => 'Lost',
      NodeConnectionState.scanning => 'Scan',
      _ => 'Offline',
    };
  }

  String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}min';
    final s = d.inSeconds.remainder(60);
    return '${m}min${s.toString().padLeft(2, '0')}s';
  }

  String get _gpsLabel {
    if (_hwGps.inUse) return 'HW ${_hwGps.satellites}sv';
    final pos = _gpsPosition;
    if (pos == null) return _hwGps.fallback ? 'PH --' : '--';
    final acc = '${pos.accuracy.toStringAsFixed(0)}m';
    return _hwGps.fallback ? 'PH $acc' : acc;
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
    final t = AppTheme.of(context);
    return IconButton(
      tooltip: 'Scan with this device',
      icon: Icon(src.radioListening ? Icons.wifi_tethering : _phoneIcon),
      color: src.active ? AppTheme.detector : t.textDim,
      onPressed: () => showCommandSheet<void>(
        context: context,
        builder: (_) => const _PhoneScanSheet(),
      ),
    );
  }
}

class _UsbScanChip extends ConsumerWidget {
  const _UsbScanChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final st = ref.watch(wifiAdapterStateProvider).valueOrNull ??
        ref.watch(wifiAdapterControllerProvider).state;
    if (st == WifiAdapterState.absent) return const SizedBox.shrink();
    final running = st == WifiAdapterState.running || st == WifiAdapterState.starting;
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 6),
      child: Tooltip(
        message: running ? 'USB adapter scanning' : 'USB adapter connected',
        child: Icon(Icons.usb, size: 22, color: running ? AppTheme.detector : t.textSecondary),
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
