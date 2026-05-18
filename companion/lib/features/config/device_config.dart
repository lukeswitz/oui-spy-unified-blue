import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/features/notifications/notification_settings_screen.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DeviceConfigScreen extends ConsumerStatefulWidget {
  const DeviceConfigScreen({super.key});

  @override
  ConsumerState<DeviceConfigScreen> createState() => _DeviceConfigScreenState();
}

class _DeviceConfigScreenState extends ConsumerState<DeviceConfigScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _buzzerEnabled = true;
  int _buzzerVolume = 100;
  bool _ledEnabled = true;
  int _neopixelBrightness = 50;
  int _cooldownMs = 5000;
  int _heartbeatMs = 30000;
  int _rediscoverMs = 30000;
  int _hbActiveMs = 3000;
  bool _loading = true;

  // Device info
  String _fwVersion = '--';
  String _nodeId = '--';
  String _heapFree = '--';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _readDeviceConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _readDeviceConfig() async {
    final ble = ref.read(bleManagerProvider);
    if (!ble.isConnected) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Read hardware config
      final hwChar = ble.getCharacteristic(GattUuids.hardwareConfig);
      if (hwChar != null) {
        final hw = await hwChar.read();
        if (hw.length >= 3) {
          setState(() {
            _buzzerEnabled = hw[0] != 0;
            _ledEnabled = hw[1] != 0;
            _neopixelBrightness = hw[2];
            _buzzerVolume = hw.length >= 4 ? hw[3] : 100;
          });
          DebugLog.log('CONFIG: hw read: buzzer=$_buzzerEnabled vol=$_buzzerVolume led=$_ledEnabled neo=$_neopixelBrightness');
        }
      }

      // Read alert config
      final alertChar = ble.getCharacteristic(GattUuids.alertConfig);
      if (alertChar != null) {
        final al = await alertChar.read();
        if (al.length >= 8) {
          setState(() {
            _cooldownMs = al[0] | (al[1] << 8);
            _heartbeatMs = al[2] | (al[3] << 8);
            _rediscoverMs = al[4] | (al[5] << 8);
            _hbActiveMs = al[6] | (al[7] << 8);
          });
          DebugLog.log('CONFIG: alert read: cool=$_cooldownMs hb=$_heartbeatMs');
        }
      }

      // Read device info
      final infoChar = ble.getCharacteristic(GattUuids.deviceInfo);
      if (infoChar != null) {
        final info = await infoChar.read();
        if (info.isNotEmpty) {
          final nullIdx = info.indexOf(0);
          _fwVersion = String.fromCharCodes(
              nullIdx >= 0 ? info.sublist(0, nullIdx) : info.take(16).toList());
          if (nullIdx >= 0 && nullIdx + 1 < info.length) {
            final rest = info.sublist(nullIdx + 1);
            final nullIdx2 = rest.indexOf(0);
            _nodeId = String.fromCharCodes(
                nullIdx2 >= 0 ? rest.sublist(0, nullIdx2) : rest.take(16).toList());
          }
          DebugLog.log('CONFIG: fw=$_fwVersion node=$_nodeId');
        }
      }
    } catch (e) {
      DebugLog.log('CONFIG: read error: $e');
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text(
                    'CONFIG',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 3,
                          color: t.textDim,
                        ),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppTheme.accent,
                      ),
                    ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.accent,
              unselectedLabelColor: t.textDim,
              indicatorColor: AppTheme.accent,
              labelStyle: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1,
              ),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'APP'),
                Tab(text: 'WATCHLIST'),
                Tab(text: 'IGNORE'),
                Tab(text: 'DETECTIONS'),
                Tab(text: 'HARDWARE'),
                Tab(text: 'ALERTS'),
                Tab(text: 'WIFI'),
                Tab(text: 'FIRMWARE'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAppTab(),
                  const _WatchlistTab(),
                  const _IgnoreListTab(),
                  const _DetectionsTab(),
                  _buildHardwareTab(),
                  _buildAlertsTab(),
                  _buildWifiTab(),
                  _buildFirmwareTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppTab() {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final unitSystem = ref.watch(unitSystemProvider);
    final isImperial = unitSystem == UnitSystem.imperial;
    final t = AppTheme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ConfigSectionHeader(label: 'APPEARANCE'),
        ConfigToggleRow(
          icon: isDark ? Icons.dark_mode : Icons.light_mode,
          label: 'Dark Mode',
          subtitle: isDark ? 'Dark theme active' : 'Light theme active',
          color: AppTheme.accent,
          value: isDark,
          onChanged: (v) {
            ref.read(themeModeProvider.notifier).setMode(
                  v ? ThemeMode.dark : ThemeMode.light,
                );
          },
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'UNITS'),
        ConfigToggleRow(
          icon: isImperial ? Icons.straighten : Icons.square_foot,
          label: 'Imperial Units',
          subtitle: isImperial
              ? 'Distances mi, speed mph, altitude ft'
              : 'Distances km, speed km/h, altitude m',
          color: AppTheme.accent,
          value: isImperial,
          onChanged: (v) {
            ref.read(unitSystemProvider.notifier).setSystem(
                  v ? UnitSystem.imperial : UnitSystem.metric,
                );
          },
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'WARDRIVE — RSSI'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'RSSI change threshold before re-logging a seen device',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const _WardriveRssiRow(isBle: false),
        const _WardriveRssiRow(isBle: true),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'SCAN TIMING'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'Lower values = faster scans, more battery drain',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const _ScanTimingSliders(),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'CHANNEL RANGE'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'WiFi channels to scan. Narrower range = faster per-channel coverage.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const _ChannelRangeSlider(),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'OUI DATABASE'),
        const _OuiDatabaseSection(),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'WIGLE'),
        const _WigleSection(),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'ABOUT'),
        const ConfigInfoRow(
          icon: Icons.info_outline,
          label: 'Version',
          value: '1.0.0',
        ),
        ConfigActionRow(
          icon: Icons.code,
          label: 'Source Code',
          subtitle: 'github.com/colonelpanic/oui-spy',
          onTap: () => _launchUrl('https://github.com/colonelpanic/oui-spy'),
          trailing: Icon(Icons.open_in_new, size: 14, color: t.textDim),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    // url_launcher not added — just copy to clipboard as fallback
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }
  }

  Widget _buildDisconnectedPlaceholder() {
    final t = AppTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bluetooth_disabled, size: 32, color: AppTheme.warning),
              ),
              const SizedBox(height: 14),
              Text(
                'NO NODE CONNECTED',
                style: TextStyle(
                  color: t.textPrimary, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connect an OUI-SPY node to configure hardware settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textDim, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHardwareTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ConfigSectionHeader(label: 'AUDIO'),
        ConfigToggleRow(
          icon: Icons.volume_up,
          label: 'Buzzer',
          subtitle: 'Audible alerts on detections',
          color: const Color(0xFFFFB84A),
          value: _buzzerEnabled,
          onChanged: (v) {
            setState(() => _buzzerEnabled = v);
            _writeHardwareConfig();
          },
        ),
        if (_buzzerEnabled)
          ConfigSliderRow(
            icon: Icons.graphic_eq,
            label: 'Buzzer Volume',
            valueLabel: '$_buzzerVolume',
            min: 1,
            max: 255,
            divisions: 254,
            value: _buzzerVolume.toDouble(),
            color: const Color(0xFFFFB84A),
            onChanged: (v) {
              setState(() => _buzzerVolume = v.round());
              _writeHardwareConfig();
            },
          ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'LIGHTING'),
        ConfigToggleRow(
          icon: Icons.lightbulb,
          label: 'Status LED',
          subtitle: 'Power and activity indicator',
          color: const Color(0xFF4AFF8A),
          value: _ledEnabled,
          onChanged: (v) {
            setState(() => _ledEnabled = v);
            _writeHardwareConfig();
          },
        ),
        ConfigSliderRow(
          icon: Icons.brightness_6,
          label: 'NeoPixel Brightness',
          valueLabel: '$_neopixelBrightness',
          min: 0,
          max: 255,
          divisions: 255,
          value: _neopixelBrightness.toDouble(),
          color: const Color(0xFFB44AFF),
          onChanged: (v) {
            setState(() => _neopixelBrightness = v.round());
            _writeHardwareConfig();
          },
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    final appState = ref.watch(appStateProvider);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const NotificationSettingsBody(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
        ),
        if (appState.isConnected) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ConfigSectionHeader(label: 'FIRMWARE TIMING'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                ConfigNumberField(
                  icon: Icons.hourglass_empty,
                  label: 'Cooldown', suffix: 'ms', value: _cooldownMs,
                  onChanged: (v) { setState(() => _cooldownMs = v); _writeAlertConfig(); },
                ),
                ConfigNumberField(
                  icon: Icons.favorite,
                  label: 'Heartbeat', suffix: 'ms', value: _heartbeatMs,
                  onChanged: (v) { setState(() => _heartbeatMs = v); _writeAlertConfig(); },
                ),
                ConfigNumberField(
                  icon: Icons.refresh,
                  label: 'Rediscover', suffix: 'ms', value: _rediscoverMs,
                  onChanged: (v) { setState(() => _rediscoverMs = v); _writeAlertConfig(); },
                ),
                ConfigNumberField(
                  icon: Icons.bolt,
                  label: 'HB Active', suffix: 'ms', value: _hbActiveMs,
                  onChanged: (v) { setState(() => _hbActiveMs = v); _writeAlertConfig(); },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  final _ssidController = TextEditingController();
  final _passController = TextEditingController();

  Widget _buildWifiTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    final t = AppTheme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ConfigSectionHeader(label: 'STATION MODE'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Text(
            'Connects node to your network for OTA updates, data upload, and remote node communication.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        ConfigTextField(
          icon: Icons.wifi,
          label: 'WiFi SSID',
          controller: _ssidController,
        ),
        ConfigTextField(
          icon: Icons.lock,
          label: 'Password',
          controller: _passController,
          obscure: true,
        ),
        const SizedBox(height: 8),
        ConfigActionRow(
          icon: Icons.save,
          label: 'Save & Connect',
          subtitle: 'Push credentials to node',
          color: AppTheme.success,
          onTap: _writeWifiConfig,
          trailing: const Icon(Icons.arrow_forward, size: 16, color: AppTheme.success),
        ),
        ConfigActionRow(
          icon: Icons.radar,
          label: 'Scan Networks',
          subtitle: 'List nearby access points',
          onTap: _scanNetworks,
        ),
      ],
    );
  }

  void _writeWifiConfig() {
    final ssid = _ssidController.text.trim();
    final pass = _passController.text;
    if (ssid.isEmpty) return;
    DebugLog.log('CONFIG: WiFi STA config: $ssid');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WiFi credentials saved'), backgroundColor: AppTheme.success),
    );
  }

  void _scanNetworks() {
    DebugLog.log('CONFIG: WiFi scan requested');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Network scan requires WiFi command GATT char'), backgroundColor: AppTheme.warning),
    );
  }

  Widget _buildFirmwareTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ConfigSectionHeader(label: 'NODE INFO'),
        ConfigInfoRow(
          icon: Icons.numbers, label: 'Version', value: _fwVersion,
        ),
        ConfigInfoRow(
          icon: Icons.fingerprint, label: 'Node ID', value: _nodeId,
        ),
        ConfigInfoRow(
          icon: Icons.memory, label: 'Free Heap', value: _heapFree,
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'UPDATES'),
        ConfigActionRow(
          icon: Icons.system_update,
          label: 'Check for Update',
          subtitle: 'Compare against latest release',
          onTap: () {},
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'DANGER ZONE'),
        ConfigActionRow(
          icon: Icons.restart_alt,
          label: 'Factory Reset',
          subtitle: 'Erase all settings and reboot',
          destructive: true,
          onTap: () {},
        ),
      ],
    );
  }

  void _writeHardwareConfig() {
    ref.read(bleManagerProvider).writeHardwareConfig(
          buzzer: _buzzerEnabled,
          led: _ledEnabled,
          neopixelBrightness: _neopixelBrightness,
          buzzerVolume: _buzzerVolume,
        );
  }

  void _writeAlertConfig() {
    ref.read(bleManagerProvider).writeAlertConfig(
          cooldownMs: _cooldownMs,
          heartbeatMs: _heartbeatMs,
          rediscoverMs: _rediscoverMs,
          hbActiveMs: _hbActiveMs,
        );
  }
}

class _ScanTimingSliders extends ConsumerWidget {
  const _ScanTimingSliders();

  static const _steps = [50, 100, 150, 200, 250, 300, 350, 400, 500, 800, 1000, 1500, 2000, 3000, 5000];

  int _prevStep(int current) {
    for (int i = _steps.length - 1; i >= 0; i--) {
      if (_steps[i] < current) return _steps[i];
    }
    return _steps.first;
  }

  int _nextStep(int current) {
    for (final s in _steps) {
      if (s > current) return s;
    }
    return _steps.last;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final wd = ref.watch(wardriveProvider);

    return Column(
      children: [
        _TimingRow(
          icon: Icons.wifi, label: 'Ch 1/6/11 dwell',
          value: wd.wifiScanInterval,
          onDown: () => ref.read(wardriveProvider).wifiScanInterval = _prevStep(wd.wifiScanInterval),
          onUp: () => ref.read(wardriveProvider).wifiScanInterval = _nextStep(wd.wifiScanInterval),
        ),
        _TimingRow(
          icon: Icons.wifi, label: 'Other ch dwell',
          value: wd.wifiDwellPerCh,
          onDown: () => ref.read(wardriveProvider).wifiDwellPerCh = _prevStep(wd.wifiDwellPerCh),
          onUp: () => ref.read(wardriveProvider).wifiDwellPerCh = _nextStep(wd.wifiDwellPerCh),
        ),
        _TimingRow(
          icon: Icons.bluetooth, label: 'BLE duration',
          value: wd.bleScanDuration,
          onDown: () => ref.read(wardriveProvider).bleScanDuration = _prevStep(wd.bleScanDuration),
          onUp: () => ref.read(wardriveProvider).bleScanDuration = _nextStep(wd.bleScanDuration),
        ),
        _TimingRow(
          icon: Icons.bluetooth, label: 'BLE interval',
          value: wd.bleScanInterval,
          onDown: () => ref.read(wardriveProvider).bleScanInterval = _prevStep(wd.bleScanInterval),
          onUp: () => ref.read(wardriveProvider).bleScanInterval = _nextStep(wd.bleScanInterval),
        ),
      ],
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onDown,
    required this.onUp,
    this.suffix = 'ms',
  });
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: t.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(
              color: t.textSecondary, fontSize: 12,
            )),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDown,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.remove, size: 16, color: AppTheme.accent),
            ),
          ),
          Container(
            width: 64,
            alignment: Alignment.center,
            child: Text(
              '$value$suffix',
              style: const TextStyle(
                color: AppTheme.accent, fontSize: 12,
                fontFamily: 'monospace', fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onUp,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.add, size: 16, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRangeSlider extends ConsumerWidget {
  const _ChannelRangeSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);

    return Column(
      children: [
        _TimingRow(
          icon: Icons.cell_tower,
          label: 'Start CH',
          value: wd.channelStart,
          suffix: '',
          onDown: () => ref.read(wardriveProvider).channelStart = wd.channelStart - 1,
          onUp: () => ref.read(wardriveProvider).channelStart = wd.channelStart + 1,
        ),
        _TimingRow(
          icon: Icons.cell_tower,
          label: 'End CH',
          value: wd.channelEnd,
          suffix: '',
          onDown: () => ref.read(wardriveProvider).channelEnd = wd.channelEnd - 1,
          onUp: () => ref.read(wardriveProvider).channelEnd = wd.channelEnd + 1,
        ),
      ],
    );
  }
}

class _WardriveRssiRow extends ConsumerWidget {
  const _WardriveRssiRow({required this.isBle});
  final bool isBle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);
    final value = isBle ? wd.bleRssiRelogDb : wd.wifiRssiRelogDb;
    final min = isBle ? 10 : 10;
    final max = isBle ? 50 : 60;

    return _TimingRow(
      icon: isBle ? Icons.bluetooth : Icons.wifi,
      label: isBle ? 'BLE re-log' : 'WiFi re-log',
      value: value,
      suffix: 'dB',
      onDown: () {
        final next = (value - 5).clamp(min, max);
        if (isBle) {
          ref.read(wardriveProvider).bleRssiRelogDb = next;
        } else {
          ref.read(wardriveProvider).wifiRssiRelogDb = next;
        }
      },
      onUp: () {
        final next = (value + 5).clamp(min, max);
        if (isBle) {
          ref.read(wardriveProvider).bleRssiRelogDb = next;
        } else {
          ref.read(wardriveProvider).wifiRssiRelogDb = next;
        }
      },
    );
  }
}

class _WigleSection extends ConsumerStatefulWidget {
  const _WigleSection();

  @override
  ConsumerState<_WigleSection> createState() => _WigleSectionState();
}

class _WigleSectionState extends ConsumerState<_WigleSection> {
  final _nameController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final wigle = ref.watch(wigleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.language, size: 16, color: AppTheme.warning),
            const SizedBox(width: 6),
            Text(
              'WIGLE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: t.textDim,
                  ),
            ),
            const Spacer(),
            if (wigle.isLoggedIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 10, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text('LINKED', style: TextStyle(
                      color: AppTheme.success, fontSize: 8,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5,
                    )),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Link your WiGLE account to upload wardrive data and track your rank.',
          style: TextStyle(color: t.textDim, fontSize: 11),
        ),
        const SizedBox(height: 12),

        if (wigle.isLoggedIn) ...[
          _WigleStatsCard(stats: wigle.stats),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(wigleProvider).refreshStats(),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('REFRESH', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout, size: 14),
                  label: const Text('UNLINK', style: TextStyle(fontSize: 10, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.key, size: 14, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Text('API Credentials', style: TextStyle(
                      color: t.textPrimary, fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Get your API Name and Token from wigle.net/account',
                  style: TextStyle(color: t.textDim, fontSize: 10),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'API Name',
                    labelStyle: TextStyle(color: t.textDim, fontSize: 12),
                    prefixIcon: Icon(Icons.person_outline, size: 16, color: t.textDim),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'API Token',
                    labelStyle: TextStyle(color: t.textDim, fontSize: 12),
                    prefixIcon: Icon(Icons.vpn_key_outlined, size: 16, color: t.textDim),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken ? Icons.visibility_off : Icons.visibility,
                        size: 16, color: t.textDim,
                      ),
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _testing || wigle.isLoading ? null : _testAndLogin,
                    icon: _testing || wigle.isLoading
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Icon(Icons.rocket_launch, size: 16),
                    label: Text(
                      _testing || wigle.isLoading ? 'TESTING...' : 'TEST & LINK',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
                if (wigle.error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 14, color: AppTheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            wigle.error!,
                            style: const TextStyle(color: AppTheme.error, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _testAndLogin() async {
    final name = _nameController.text.trim();
    final token = _tokenController.text.trim();
    if (name.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both API Name and Token')),
      );
      return;
    }

    setState(() => _testing = true);
    final success = await ref.read(wigleProvider).login(name, token);
    if (mounted) {
      setState(() => _testing = false);
      if (success) {
        final stats = ref.read(wigleProvider).stats;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.success,
            content: Text('Linked as ${stats?.userName ?? name} (rank #${stats?.rank ?? '?'})'),
          ),
        );
      }
    }
  }

  void _confirmLogout(BuildContext context) {
    final t = AppTheme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.background,
        title: Text('Unlink WiGLE?', style: TextStyle(color: t.textPrimary)),
        content: Text(
          'This removes stored credentials. You can re-link anytime.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(wigleProvider).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('UNLINK'),
          ),
        ],
      ),
    );
  }
}

class _WigleStatsCard extends StatelessWidget {
  const _WigleStatsCard({this.stats});
  final WigleUserStats? stats;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final s = stats;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.accent)),
            const SizedBox(width: 8),
            Text('Loading stats...', style: TextStyle(color: t.textDim, fontSize: 11)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.account_circle, size: 20, color: AppTheme.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.userName,
                  style: TextStyle(
                    color: t.textPrimary, fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events, size: 12, color: AppTheme.accent),
                    const SizedBox(width: 4),
                    Text('#${s.rank}', style: const TextStyle(
                      color: AppTheme.accent, fontSize: 12,
                      fontWeight: FontWeight.w700, fontFamily: 'monospace',
                    )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WigleStat(
                icon: Icons.wifi, label: 'WiFi',
                value: _formatCount(s.discoveredWiFi),
                color: AppTheme.accent,
              ),
              _WigleStat(
                icon: Icons.bluetooth, label: 'BT',
                value: _formatCount(s.discoveredBt),
                color: const Color(0xFF4A9EFF),
              ),
              _WigleStat(
                icon: Icons.cell_tower, label: 'Cell',
                value: _formatCount(s.discoveredCell),
                color: AppTheme.success,
              ),
              _WigleStat(
                icon: Icons.trending_up, label: 'Month',
                value: '#${s.monthRank}',
                color: AppTheme.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

class _WigleStat extends StatelessWidget {
  const _WigleStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(
            color: t.textPrimary, fontSize: 11,
            fontWeight: FontWeight.w700, fontFamily: 'monospace',
          )),
          Text(label, style: TextStyle(
            color: t.textDim, fontSize: 8,
            fontWeight: FontWeight.w600, letterSpacing: 0.5,
          )),
        ],
      ),
    );
  }
}

class _IgnoreListTab extends ConsumerWidget {
  const _IgnoreListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final allowlist = ref.watch(ignoreListProvider);
    final entries = allowlist.entries;

    return Column(
      children: [
        // Header + add button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                'IGNORE LIST',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 2,
                      color: t.textDim,
                    ),
              ),
              const Spacer(),
              Text(
                '${entries.where((e) => e.enabled).length} active',
                style: TextStyle(
                  color: t.textDim, fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showAddDialog(context, ref),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.add, size: 18, color: AppTheme.accent),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            'Matching devices are silently excluded from the feed, '
            'CSV exports, database logging, and alerts.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const Divider(height: 1),
        // Entry list
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 36, color: t.textDim),
                      const SizedBox(height: 12),
                      Text('NO ENTRIES', style: TextStyle(
                        color: t.textDim, fontSize: 12,
                        fontWeight: FontWeight.w700, letterSpacing: 2,
                      )),
                      const SizedBox(height: 6),
                      Text(
                        'Tap + to add SSIDs, MACs, or OUIs\nthat should never be logged.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textDim, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _IgnoreEntryTile(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final valueController = TextEditingController();
    final labelController = TextEditingController();
    IgnoreType selectedType = IgnoreType.ssid;
    IgnoreScope selectedScope = IgnoreScope.both;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final hintText = switch (selectedType) {
            IgnoreType.ssid => 'MyHomeNetwork',
            IgnoreType.mac => 'AA:BB:CC:DD:EE:FF',
            IgnoreType.oui => 'AA:BB:CC',
          };

          return AlertDialog(
            backgroundColor: t.surface,
            title: Text('Add to Ignore List', style: TextStyle(color: t.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type selector
                  Text('MATCH TYPE', style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                  const SizedBox(height: 6),
                  Row(
                    children: IgnoreType.values.map((type) {
                      final isSelected = selectedType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedType = type),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: type != IgnoreType.oui ? 6 : 0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.accent.withValues(alpha: 0.5)
                                    : t.border,
                              ),
                            ),
                            child: Center(
                              child: Text(type.label, style: TextStyle(
                                color: isSelected ? AppTheme.accent : t.textSecondary,
                                fontSize: 11, fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              )),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Value field
                  TextField(
                    controller: valueController,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontFamily: selectedType == IgnoreType.ssid
                          ? null
                          : 'monospace',
                      fontSize: 14,
                    ),
                    textCapitalization: selectedType == IgnoreType.ssid
                        ? TextCapitalization.none
                        : TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: hintText,
                      labelText: selectedType.label,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Label field
                  TextField(
                    controller: labelController,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Home Router',
                      labelText: 'Label (optional)',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Scope selector
                  Text('APPLIES TO', style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                  const SizedBox(height: 6),
                  Row(
                    children: IgnoreScope.values.map((scope) {
                      final isSelected = selectedScope == scope;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedScope = scope),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: scope != IgnoreScope.ble ? 6 : 0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.accent.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.accent.withValues(alpha: 0.5)
                                    : t.border,
                              ),
                            ),
                            child: Center(
                              child: Text(scope.label, style: TextStyle(
                                color: isSelected ? AppTheme.accent : t.textSecondary,
                                fontSize: 10, fontWeight: FontWeight.w600,
                              )),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  final raw = valueController.text.trim();
                  if (raw.isEmpty) return;
                  final normalized = IgnoreEntry.normalize(selectedType, raw);
                  ref.read(ignoreListProvider).add(IgnoreEntry(
                    type: selectedType,
                    value: normalized,
                    scope: selectedScope,
                    label: labelController.text.trim(),
                  ));
                  Navigator.pop(ctx);
                },
                child: const Text('ADD'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IgnoreEntryTile extends ConsumerWidget {
  const _IgnoreEntryTile({required this.entry});
  final IgnoreEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final isEnabled = entry.enabled;

    final IconData typeIcon = switch (entry.type) {
      IgnoreType.ssid => Icons.wifi,
      IgnoreType.mac => Icons.fingerprint,
      IgnoreType.oui => Icons.radar,
    };

    final Color scopeColor = switch (entry.scope) {
      IgnoreScope.wifi => AppTheme.wardrive,
      IgnoreScope.ble => const Color(0xFF4A9EFF),
      IgnoreScope.both => AppTheme.accent,
    };

    return Dismissible(
      key: ValueKey('${entry.type.name}:${entry.value}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
      ),
      onDismissed: (_) => ref.read(ignoreListProvider).remove(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isEnabled ? t.border : t.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: (isEnabled ? AppTheme.accent : t.textDim).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                typeIcon,
                size: 16,
                color: isEnabled ? AppTheme.accent : t.textDim,
              ),
            ),
            const SizedBox(width: 10),
            // Value + label + scope
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.type == IgnoreType.ssid
                        ? entry.value
                        : entry.value.toUpperCase(),
                    style: TextStyle(
                      color: isEnabled ? t.textPrimary : t.textDim,
                      fontSize: 13,
                      fontFamily: entry.type == IgnoreType.ssid
                          ? null
                          : 'monospace',
                      fontWeight: FontWeight.w600,
                      letterSpacing: entry.type == IgnoreType.ssid
                          ? 0
                          : 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isEnabled ? AppTheme.accent : t.textDim)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.type.label,
                          style: TextStyle(
                            color: isEnabled ? AppTheme.accent : t.textDim,
                            fontSize: 8, fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Scope badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isEnabled ? scopeColor : t.textDim)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.scope.label,
                          style: TextStyle(
                            color: isEnabled ? scopeColor : t.textDim,
                            fontSize: 8, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (entry.label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.label,
                            style: TextStyle(color: t.textDim, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Toggle switch
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: isEnabled,
                onChanged: (v) =>
                    ref.read(ignoreListProvider).toggleEnabled(entry, enabled: v),
                activeTrackColor: AppTheme.accent.withValues(alpha: 0.3),
                activeColor: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _WatchlistTab extends ConsumerWidget {
  const _WatchlistTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final watchlist = ref.watch(watchlistProvider);
    final entries = watchlist.entries;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
          child: Row(
            children: [
              Icon(Icons.radar, size: 14, color: AppTheme.detector),
              const SizedBox(width: 6),
              Text(
                'WATCHLIST',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 2,
                      color: t.textDim,
                    ),
              ),
              const Spacer(),
              Text(
                '${entries.length} target${entries.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: t.textDim, fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showAddDialog(context, ref),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.detector.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.detector.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.add,
                      size: 18, color: AppTheme.detector),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            'Detector engine alerts when any of these OUI prefixes or full '
            'MAC addresses are seen. Used for runtime detection and CSV import '
            'reclassification.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !watchlist.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radar, size: 36, color: t.textDim),
                          const SizedBox(height: 12),
                          Text('NO TARGETS', style: TextStyle(
                            color: t.textDim, fontSize: 12,
                            fontWeight: FontWeight.w700, letterSpacing: 2,
                          )),
                          const SizedBox(height: 6),
                          Text(
                            'Tap + to add an OUI prefix\nor full MAC to watch.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: t.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: entries.length,
                      itemBuilder: (_, i) =>
                          _WatchlistEntryTile(entry: entries[i]),
                    ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final idController = TextEditingController();
    final descController = TextEditingController();
    WatchlistMatchType matchType = WatchlistMatchType.oui;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isHex = matchType != WatchlistMatchType.name;
          final hint = switch (matchType) {
            WatchlistMatchType.oui => 'AA:BB:CC',
            WatchlistMatchType.fullMac => 'AA:BB:CC:DD:EE:FF',
            WatchlistMatchType.name => 'penguin*',
          };
          final label = switch (matchType) {
            WatchlistMatchType.oui => 'OUI prefix (3 bytes)',
            WatchlistMatchType.fullMac => 'Full MAC address',
            WatchlistMatchType.name => 'Device name (supports * and ?)',
          };
          return AlertDialog(
            backgroundColor: t.surface,
            title: Text('Add Watchlist Target',
                style: TextStyle(color: t.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MATCH TYPE', style: TextStyle(
                    color: t.textDim, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
                  const SizedBox(height: 6),
                  Row(
                    children: WatchlistMatchType.values.map((type) {
                      final selected = matchType == type;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: type == WatchlistMatchType.values.last
                                ? 0
                                : 6,
                          ),
                          child: _MatchTypeChip(
                            label: switch (type) {
                              WatchlistMatchType.oui => 'OUI',
                              WatchlistMatchType.fullMac => 'FULL MAC',
                              WatchlistMatchType.name => 'NAME',
                            },
                            selected: selected,
                            onTap: () =>
                                setDialogState(() => matchType = type),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: idController,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontFamily: isHex ? 'monospace' : null,
                      fontSize: 14,
                    ),
                    textCapitalization: isHex
                        ? TextCapitalization.characters
                        : TextCapitalization.none,
                    decoration: InputDecoration(
                      hintText: hint,
                      labelText: label,
                    ),
                  ),
                  if (matchType == WatchlistMatchType.name) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Use * for any sequence, ? for one character. '
                      'Match is case-insensitive.',
                      style: TextStyle(color: t.textDim, fontSize: 10),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: descController,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Flock Safety',
                      labelText: 'Label (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  final raw = idController.text.trim();
                  if (raw.isEmpty) return;
                  String identifier;
                  if (matchType == WatchlistMatchType.name) {
                    identifier = raw;
                  } else {
                    final hex = _normalizeHex(raw);
                    if (matchType == WatchlistMatchType.fullMac &&
                        hex.length != 12) return;
                    if (matchType == WatchlistMatchType.oui &&
                        hex.length < 6) return;
                    identifier = _formatMac(
                      hex,
                      matchType == WatchlistMatchType.fullMac ? 6 : 3,
                    );
                  }
                  ref.read(watchlistProvider).add(WatchlistEntry(
                        identifier: identifier,
                        matchType: matchType,
                        description: descController.text.trim(),
                      ));
                  Navigator.pop(ctx);
                },
                child: const Text('ADD'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _normalizeHex(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
  }

  static String _formatMac(String hex, int byteCount) {
    final n = (byteCount * 2).clamp(0, hex.length);
    final h = hex.substring(0, n);
    final buf = StringBuffer();
    for (int i = 0; i < h.length; i++) {
      if (i > 0 && i.isEven) buf.write(':');
      buf.write(h[i]);
    }
    return buf.toString();
  }
}

class _MatchTypeChip extends StatelessWidget {
  const _MatchTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.detector.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? AppTheme.detector.withValues(alpha: 0.5)
                : t.border,
          ),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: selected ? AppTheme.detector : t.textSecondary,
            fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          )),
        ),
      ),
    );
  }
}

class _WatchlistEntryTile extends ConsumerWidget {
  const _WatchlistEntryTile({required this.entry});
  final WatchlistEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final isHex = !entry.isName;
    final IconData icon = switch (entry.matchType) {
      WatchlistMatchType.oui => Icons.radar,
      WatchlistMatchType.fullMac => Icons.fingerprint,
      WatchlistMatchType.name => Icons.badge_outlined,
    };
    return Dismissible(
      key: ValueKey('wl:${entry.matchType.name}:${entry.identifier}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
      ),
      onDismissed: (_) => ref.read(watchlistProvider).remove(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.detector.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: AppTheme.detector,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHex
                        ? entry.identifier.toUpperCase()
                        : entry.identifier,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontFamily: isHex ? 'monospace' : null,
                      fontWeight: FontWeight.w600,
                      letterSpacing: isHex ? 0.5 : 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.detector.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.matchType.label,
                          style: const TextStyle(
                            color: AppTheme.detector,
                            fontSize: 8, fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (entry.description.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.description,
                            style: TextStyle(color: t.textDim, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DetSort { time, rssi, mac }

class _DetectionsTab extends ConsumerStatefulWidget {
  const _DetectionsTab();

  @override
  ConsumerState<_DetectionsTab> createState() => _DetectionsTabState();
}

class _DetectionsTabState extends ConsumerState<_DetectionsTab> {
  List<Map<String, dynamic>> _detections = [];
  bool _loading = true;
  bool _rescanning = false;
  _DetSort _sort = _DetSort.time;
  bool _ascending = false;
  String? _engineFilter; // null = all, 'flock', 'detector'
  bool _showMap = false;
  final _mapController = MapController();

  Future<void> _rescan() async {
    final db = ref.read(databaseProvider);
    final watchlist =
        List<WatchlistEntry>.from(ref.read(watchlistProvider).entries);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _rescanning = true);
    try {
      final res = await WigleCsvRescan.rescanAll(db, watchlist: watchlist);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.success,
        content: Text(
          'Rescanned ${res.sessionsScanned} sessions, '
          '${res.rowsScanned} rows, ${res.rowsUpdated} reclassified '
          '(${res.newDetectorMacs} detector, ${res.newFlockMacs} flock)',
        ),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.error,
        content: Text('Rescan failed: $e'),
      ));
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getFlockDetectorDetections();
    if (mounted) setState(() { _detections = rows; _loading = false; });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _detections;
    if (_engineFilter == 'flock') {
      list = list.where((d) {
        final e = d['engine'] as String;
        return e == 'flockBle' || e == 'flockWifi';
      }).toList();
    } else if (_engineFilter == 'detector') {
      list = list.where((d) => d['engine'] == 'detector').toList();
    }

    final cmp = switch (_sort) {
      _DetSort.time => (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['appTimestamp'] as int).compareTo(b['appTimestamp'] as int),
      _DetSort.rssi => (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['rssi'] as int).compareTo(b['rssi'] as int),
      _DetSort.mac => (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['macAddress'] as String).compareTo(b['macAddress'] as String),
    };

    list.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));
    return list;
  }

  Color _engineColor(String engine) => switch (engine) {
    'flockBle' => AppTheme.flockBle,
    'flockWifi' => AppTheme.flockWifi,
    'detector' => AppTheme.detector,
    _ => AppTheme.accent,
  };

  String _engineLabel(String engine) => switch (engine) {
    'flockBle' => 'FLOCK BLE',
    'flockWifi' => 'FLOCK WiFi',
    'detector' => 'DETECTOR',
    _ => engine,
  };

  void _toggleSort(_DetSort s) {
    setState(() {
      if (_sort == s) {
        _ascending = !_ascending;
      } else {
        _sort = s;
        _ascending = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(
        color: AppTheme.accent, strokeWidth: 2));
    }

    if (_detections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 36, color: t.textDim),
            const SizedBox(height: 12),
            Text('NO DETECTIONS', style: TextStyle(
              color: t.textDim, fontSize: 12,
              fontWeight: FontWeight.w700, letterSpacing: 2,
            )),
            const SizedBox(height: 6),
            Text(
              'Run a wardrive with Flock or Detector engines to see detections here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textDim, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final items = _filtered;
    final flockCount = _detections.where((d) {
      final e = d['engine'] as String;
      return e == 'flockBle' || e == 'flockWifi';
    }).length;
    final detectorCount = _detections.where((d) => d['engine'] == 'detector').length;

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _FilterChip(
                label: 'ALL (${_detections.length})',
                selected: _engineFilter == null,
                color: AppTheme.accent,
                onTap: () => setState(() => _engineFilter = null),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'FLOCK ($flockCount)',
                selected: _engineFilter == 'flock',
                color: AppTheme.flockBle,
                onTap: () => setState(() =>
                    _engineFilter = _engineFilter == 'flock' ? null : 'flock'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'DETECT ($detectorCount)',
                selected: _engineFilter == 'detector',
                color: AppTheme.detector,
                onTap: () => setState(() =>
                    _engineFilter = _engineFilter == 'detector' ? null : 'detector'),
              ),
            ],
          ),
        ),
        // Sort buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              Text('SORT', style: TextStyle(
                color: t.textDim, fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
              const SizedBox(width: 8),
              _SortBtn(
                label: 'TIME', active: _sort == _DetSort.time,
                ascending: _ascending,
                onTap: () => _toggleSort(_DetSort.time),
              ),
              const SizedBox(width: 4),
              _SortBtn(
                label: 'RSSI', active: _sort == _DetSort.rssi,
                ascending: _ascending,
                onTap: () => _toggleSort(_DetSort.rssi),
              ),
              const SizedBox(width: 4),
              _SortBtn(
                label: 'MAC', active: _sort == _DetSort.mac,
                ascending: _ascending,
                onTap: () => _toggleSort(_DetSort.mac),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showMap = !_showMap),
                child: Icon(
                  _showMap ? Icons.list : Icons.map,
                  size: 16,
                  color: _showMap ? AppTheme.accent : t.textDim,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _rescanning ? null : _rescan,
                child: _rescanning
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppTheme.accent,
                        ),
                      )
                    : Icon(Icons.youtube_searched_for,
                        size: 16, color: AppTheme.detector),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: Icon(Icons.refresh, size: 16, color: t.textDim),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Detection list or map
        Expanded(
          child: _showMap
              ? _buildMapView(items, t)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _DetectionRow(
                    data: items[i],
                    engineColor: _engineColor(items[i]['engine'] as String),
                    engineLabel: _engineLabel(items[i]['engine'] as String),
                    onShowMap: () => _showOnMap(items[i]),
                    onFoxhunt: () => _startFoxhunt(items[i]),
                    onDelete: _load,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMapView(List<Map<String, dynamic>> items, ResolvedTheme t) {
    final geoItems = items
        .where((d) => d['latitude'] != null && d['longitude'] != null)
        .toList();

    if (geoItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 36, color: t.textDim),
            const SizedBox(height: 12),
            Text('NO GPS DATA', style: TextStyle(
              color: t.textDim, fontSize: 12,
              fontWeight: FontWeight.w700, letterSpacing: 2,
            )),
            const SizedBox(height: 6),
            Text(
              'None of the current detections have location data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textDim, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final mapStyle = ref.watch(mapStyleProvider);

    // Compute bounds to fit all markers
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final d in geoItems) {
      final lat = d['latitude'] as double;
      final lon = d['longitude'] as double;
      minLat = min(minLat, lat);
      maxLat = max(maxLat, lat);
      minLon = min(minLon, lon);
      maxLon = max(maxLon, lon);
    }
    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    final bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));

    final markers = geoItems.map((d) {
      final lat = d['latitude'] as double;
      final lon = d['longitude'] as double;
      final engineStr = d['engine'] as String;
      final color = _engineColor(engineStr);
      final mac = (d['macAddress'] as String).toUpperCase();

      return Marker(
        point: LatLng(lat, lon),
        width: 28,
        height: 28,
        child: GestureDetector(
          onTap: () => _showMarkerSheet(d),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.25),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.8),
                  border: Border.all(color: color, width: 1.5),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    // Fit bounds after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && geoItems.length > 1) {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40),
        ));
      }
    });

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: geoItems.length == 1 ? 16 : 13,
        backgroundColor: mapStyle.isDark
            ? const Color(0xFF0A0A0A)
            : const Color(0xFFE8E8EE),
      ),
      children: [
        TileLayer(
          urlTemplate: mapStyle.urlTemplate,
          userAgentPackageName: 'tech.colonelpanic.ouispy',
          maxZoom: 19,
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  void _showMarkerSheet(Map<String, dynamic> det) {
    final t = AppTheme.of(context);
    final mac = (det['macAddress'] as String).toUpperCase();
    final engineStr = det['engine'] as String;
    final deviceName = det['deviceName'] as String? ?? '';
    final ssid = det['ssid'] as String? ?? '';
    final rssi = det['rssi'] as int;
    final channel = det['channel'] as int? ?? 0;
    final method = det['detectionMethod'] as String? ?? '';
    final ts = DateTime.fromMillisecondsSinceEpoch(det['appTimestamp'] as int);
    final timeStr = DateFormat('MMM d HH:mm').format(ts);
    final vendor = ref.read(ouiLookupProvider).lookup(mac);
    final lat = det['latitude'] as double?;
    final lon = det['longitude'] as double?;

    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: _engineColor(engineStr),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(mac, style: TextStyle(
                    color: t.textPrimary, fontSize: 14,
                    fontFamily: 'monospace', fontWeight: FontWeight.w600,
                  )),
                ),
              ],
            ),
            if (vendor != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 18),
                child: Text(vendor, style: TextStyle(
                  color: _engineColor(engineStr).withValues(alpha: 0.8),
                  fontSize: 12,
                )),
              ),
            if (deviceName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 18),
                child: Text(deviceName, style: TextStyle(
                  color: t.textSecondary, fontSize: 11,
                )),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _markerDetailRow('Engine', _engineLabel(engineStr), t),
                  if (method.isNotEmpty) _markerDetailRow('Method', method, t),
                  _markerDetailRow('RSSI', '$rssi dBm', t),
                  if (channel > 0) _markerDetailRow('Channel', '$channel', t),
                  if (ssid.isNotEmpty) _markerDetailRow('SSID', ssid, t),
                  _markerDetailRow('Time', timeStr, t),
                  if (lat != null && lon != null)
                    _markerDetailRow('Location',
                        '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}', t),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: mac));
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('MAC copied'),
                          backgroundColor: t.surface,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(Icons.copy, size: 14, color: t.textDim),
                    label: Text('Copy MAC', style: TextStyle(
                      color: t.textSecondary, fontSize: 11,
                    )),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startFoxhunt(det);
                    },
                    icon: const Icon(Icons.gps_fixed, size: 14,
                        color: AppTheme.foxhunter),
                    label: const Text('Foxhunt', style: TextStyle(
                      color: AppTheme.foxhunter, fontSize: 11,
                    )),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _markerDetailRow(String label, String value, ResolvedTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(
              color: t.textDim, fontSize: 10, fontWeight: FontWeight.w500,
            )),
          ),
          Expanded(
            child: Text(value, style: TextStyle(
              color: t.textPrimary, fontSize: 10, fontFamily: 'monospace',
            )),
          ),
        ],
      ),
    );
  }

  void _showOnMap(Map<String, dynamic> det) {
    final lat = det['latitude'] as double?;
    final lon = det['longitude'] as double?;
    final sid = det['sessionId'] as String;

    final wd = ref.read(wardriveProvider);
    if (wd.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop active wardrive first')),
      );
      return;
    }

    wd.loadSession(sid).then((_) {
      if (lat != null && lon != null) {
        wd.requestZoom(lat, lon);
      }
      if (context.mounted) context.go('/wardrive');
    });
  }

  void _startFoxhunt(Map<String, dynamic> det) {
    final mac = det['macAddress'] as String;
    final channel = det['channel'] as int? ?? 0;

    ref.read(appStateProvider).setFoxhunterTarget(
      mac,
      channel: channel,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.foxhunter,
          content: Text('Foxhunting ${mac.toUpperCase().substring(0, 8)}...'),
        ),
      );
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.25),
          ),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? color : color.withValues(alpha: 0.6),
          fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
        )),
      ),
    );
  }
}

class _SortBtn extends StatelessWidget {
  const _SortBtn({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });
  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? AppTheme.accent.withValues(alpha: 0.4) : t.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              color: active ? AppTheme.accent : t.textDim,
              fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
            if (active) ...[
              const SizedBox(width: 2),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 9, color: AppTheme.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetectionRow extends ConsumerWidget {
  const _DetectionRow({
    required this.data,
    required this.engineColor,
    required this.engineLabel,
    required this.onShowMap,
    required this.onFoxhunt,
    required this.onDelete,
  });
  final Map<String, dynamic> data;
  final Color engineColor;
  final String engineLabel;
  final VoidCallback onShowMap;
  final VoidCallback onFoxhunt;
  final VoidCallback onDelete;

  void _showCopySheet(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final mac = (data['macAddress'] as String).toUpperCase();
    final deviceName = data['deviceName'] as String? ?? '';
    final ssid = data['ssid'] as String? ?? '';
    final vendor = ref.read(ouiLookupProvider).lookup(mac);
    final lat = data['latitude'] as double?;
    final lon = data['longitude'] as double?;

    final items = <(String, String)>[
      ('MAC', mac),
      if (deviceName.isNotEmpty) ('Name', deviceName),
      if (ssid.isNotEmpty) ('SSID', ssid),
      if (vendor != null) ('Vendor', vendor),
      if (lat != null && lon != null)
        ('Location', '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COPY', style: TextStyle(
              color: t.textDim, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 2,
            )),
            const SizedBox(height: 8),
            for (final (label, value) in items)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.copy, size: 14, color: t.textDim),
                title: Text(label, style: TextStyle(color: t.textDim, fontSize: 10)),
                subtitle: Text(value, style: TextStyle(
                  color: t.textPrimary, fontSize: 12, fontFamily: 'monospace',
                )),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$label copied'),
                      backgroundColor: t.surface,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
              title: const Text('Delete Detection',
                  style: TextStyle(color: AppTheme.error, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                final db = ref.read(databaseProvider);
                final id = data['id'] as int;
                db.deleteDetectionById(id).then((_) {
                  onDelete();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Detection removed'),
                      backgroundColor: t.surface,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final mac = (data['macAddress'] as String).toUpperCase();
    final rssi = data['rssi'] as int;
    final channel = data['channel'] as int? ?? 0;
    final method = data['detectionMethod'] as String? ?? '';
    final ts = DateTime.fromMillisecondsSinceEpoch(data['appTimestamp'] as int);
    final timeStr = DateFormat('MMM d HH:mm').format(ts);
    final hasGps = data['latitude'] != null && data['longitude'] != null;
    final deviceName = data['deviceName'] as String? ?? '';
    final vendor = ref.read(ouiLookupProvider).lookup(mac);
    final rssiNorm = ((rssi + 100) / 70).clamp(0.0, 1.0);
    final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _showCopySheet(context, ref);
        }
      },
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showCopySheet(context, ref);
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          // ── Top section: MAC + engine + RSSI ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Engine accent dot
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(top: 4, right: 10),
                  decoration: BoxDecoration(
                    color: engineColor,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: engineColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    )],
                  ),
                ),
                // MAC
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mac, style: TextStyle(
                        color: t.textPrimary, fontSize: 15,
                        fontFamily: 'monospace', fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      )),
                      if (vendor != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(vendor, style: TextStyle(
                            color: engineColor.withValues(alpha: 0.8), fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ), overflow: TextOverflow.ellipsis),
                        ),
                      if (deviceName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(deviceName, style: TextStyle(
                            color: t.textSecondary, fontSize: 12,
                          ), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                // RSSI
                Text('$rssi', style: TextStyle(
                  color: rssiColor, fontSize: 20,
                  fontFamily: 'monospace', fontWeight: FontWeight.w800,
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Middle: metadata row ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                // Engine badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: engineColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(engineLabel, style: TextStyle(
                    color: engineColor, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5,
                  )),
                ),
                const SizedBox(width: 8),
                // Method
                if (method.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.textDim.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_methodLabel(method), style: TextStyle(
                      color: t.textSecondary, fontSize: 10,
                      fontWeight: FontWeight.w600,
                    )),
                  ),
                if (channel > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.cell_tower, size: 14, color: t.textDim),
                  const SizedBox(width: 3),
                  Text('$channel', style: TextStyle(
                    color: t.textSecondary, fontSize: 12,
                    fontFamily: 'monospace', fontWeight: FontWeight.w600,
                  )),
                ],
                const Spacer(),
                // Timestamp
                Icon(Icons.access_time, size: 12, color: t.textDim),
                const SizedBox(width: 4),
                Text(timeStr, style: TextStyle(
                  color: t.textDim, fontSize: 11,
                  fontFamily: 'monospace',
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Bottom: action buttons ──
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                // Map button
                Expanded(
                  child: GestureDetector(
                    onTap: hasGps ? onShowMap : null,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.place,
                            size: 16,
                            color: hasGps ? AppTheme.accent : t.textDim.withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 6),
                          Text('MAP', style: TextStyle(
                            color: hasGps ? AppTheme.accent : t.textDim.withValues(alpha: 0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(width: 0.5, height: 20, color: t.border),
                // Foxhunt button
                Expanded(
                  child: GestureDetector(
                    onTap: onFoxhunt,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gps_fixed, size: 16, color: AppTheme.foxhunter),
                          SizedBox(width: 6),
                          Text('FOXHUNT', style: TextStyle(
                            color: AppTheme.foxhunter,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  String _methodLabel(String method) => switch (method) {
    'oui_addr1' => 'ADDR1 (DST)',
    'oui_addr2' => 'ADDR2 (SRC)',
    'oui_addr3' => 'ADDR3 (BSSID)',
    'wildcard_probe' => 'PROBE REQ',
    'oui_match' => 'BLE OUI',
    'name_match' => 'BLE NAME',
    'mfg_id' => 'MFG DATA',
    'raven_uuid' => 'RAVEN UUID',
    'watchlist' => 'WATCHLIST',
    'ble_watchlist' => 'BLE WATCHLIST',
    'wifi_watchlist' => 'WIFI WATCHLIST',
    'ble_proximity' => 'BLE PROXIMITY',
    'wifi_proximity' => 'WIFI PROXIMITY',
    _ => method.toUpperCase(),
  };
}

class _OuiDatabaseSection extends ConsumerStatefulWidget {
  const _OuiDatabaseSection();

  @override
  ConsumerState<_OuiDatabaseSection> createState() => _OuiDatabaseSectionState();
}

class _OuiDatabaseSectionState extends ConsumerState<_OuiDatabaseSection> {
  bool _updating = false;
  String? _status;

  Future<void> _checkUpdate() async {
    setState(() {
      _updating = true;
      _status = null;
    });
    try {
      final oui = ref.read(ouiLookupProvider);
      final updated = await oui.checkForUpdate();
      setState(() {
        _updating = false;
        _status = updated
            ? 'Updated to ${oui.entryCount} vendors'
            : 'Already up to date (${oui.entryCount} vendors)';
      });
    } catch (e) {
      setState(() {
        _updating = false;
        _status = 'Update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final oui = ref.read(ouiLookupProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OUI DATABASE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'MAC vendor lookup database (Ringmast4r/OUI-Master-Database)',
          style: TextStyle(color: t.textDim, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.storage, size: 14, color: t.textSecondary),
            const SizedBox(width: 8),
            Text(
              '${oui.entryCount} vendors loaded',
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
            if (oui.lastUpdated != null) ...[
              const SizedBox(width: 8),
              Text(
                'updated ${_formatDate(oui.lastUpdated!)}',
                style: TextStyle(color: t.textDim, fontSize: 10),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _updating ? null : _checkUpdate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updating)
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppTheme.accent,
                    ),
                  )
                else
                  const Icon(Icons.refresh, size: 14, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  _updating ? 'Checking...' : 'Check for Update',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!, style: TextStyle(color: t.textSecondary, fontSize: 11)),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d ago';
  }
}
