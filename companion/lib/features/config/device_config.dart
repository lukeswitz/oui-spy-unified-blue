import 'dart:async';
import 'dart:math';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/features/config/ota_progress_stepper.dart';
import 'package:oui_spy/features/notifications/notification_settings_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
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

  bool _flockExtendedOui = false;
  bool _offlineScanEnabled = false;
  bool _offlineGpsTag = false;
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

  StreamSubscription<NodeConnectionState>? _connStateSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _offlineGpsTag =
        ref.read(sharedPreferencesProvider).getBool('offlineGpsTagEnabled') ?? false;
    _readDeviceConfig();
    final ble = ref.read(bleManagerProvider);
    _connStateSub = ble.connectionState.listen((s) {
      if (s == NodeConnectionState.ready) {
        DebugLog.log('CONFIG: reconnect detected, re-reading device info');
        _readDeviceConfig();
      }
    });
  }

  @override
  void dispose() {
    _connStateSub?.cancel();
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
            _flockExtendedOui = hw.length >= 5 && hw[4] != 0;
            _offlineScanEnabled = hw.length > 5 && hw[5] != 0;
          });
          ref.read(sharedPreferencesProvider)
              .setBool('offlineScanEnabled', _offlineScanEnabled);
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
          final segs = <List<int>>[];
          int segStart = 0;
          for (int i = 0; i < info.length; i++) {
            if (info[i] == 0) { segs.add(info.sublist(segStart, i)); segStart = i + 1; }
          }
          if (segStart < info.length) segs.add(info.sublist(segStart));
          if (segs.length >= 5) {
            final bytes = int.tryParse(String.fromCharCodes(segs[4]).trim());
            if (bytes != null) _heapFree = '${(bytes / 1024).round()} KB';
          }
          DebugLog.log('CONFIG: fw=$_fwVersion node=$_nodeId heap=$_heapFree');
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
                Tab(text: 'MESH'),
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
                  _buildMeshTab(),
                  _buildFirmwareTab(),
                ],
              ),
            ),
          ],
        ),
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
        const ConfigSectionHeader(label: 'CONNECTION'),
        const _AutoConnectToggle(),

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
        const ConfigSectionHeader(label: 'DATA & BACKUP'),
        ConfigActionRow(
          icon: Icons.import_export,
          label: 'Export & Database Backup',
          subtitle: 'WiGLE/JSON/KML export, full DB backup & restore',
          onTap: () => context.push('/export'),
          trailing: Icon(Icons.chevron_right, size: 18, color: t.textDim),
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'ABOUT'),
        const _VersionRow(),
        ConfigActionRow(
          icon: Icons.code,
          label: 'Source Code',
          subtitle: 'github.com/lukeswitz/oui-spy-unified-blue',
          onTap: () => _launchUrl('https://github.com/lukeswitz/oui-spy-unified-blue'),
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
    final ota = ref.read(otaServiceProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: ota.otaActive,
      builder: (context, otaActive, _) {
        if (otaActive) return _buildOtaReconnecting(t);
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
      },
    );
  }

  Widget _buildOtaReconnecting(ResolvedTheme t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_alt,
                  size: 30, color: AppTheme.accent),
            ),
            const SizedBox(height: 14),
            Text('UPDATING FIRMWARE',
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            const SizedBox(height: 6),
            Text(
              'Device is applying the update and rebooting. It reconnects on '
              'its own — keep it powered.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textDim, fontSize: 11),
            ),
            const SizedBox(height: 18),
            const OtaProgressStepper(
              model: OtaStepperModel(
                  activeIndex: 4, detail: 'Rebooting + reconnecting…'),
            ),
          ],
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

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'FLOCK DETECTION'),
        ConfigToggleRow(
          icon: Icons.lan,
          label: 'Extended Repo OUI set',
          subtitle: 'Double the OUIs, expect false postives.',
          color: const Color(0xFFFF6B6B),
          value: _flockExtendedOui,
          onChanged: (v) {
            setState(() => _flockExtendedOui = v);
            _writeHardwareConfig();
          },
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'OFFLINE SCAN (EXPERIMENTAL)'),
        ConfigToggleRow(
          icon: Icons.cloud_off,
          label: 'Keep scanning while disconnected (EXPERIMENTAL)',
          subtitle: 'EXPERIMENTAL — may be unstable. Node keeps scanning when the app is closed; detections import on reconnect.',
          color: const Color(0xFF4AB8FF),
          value: _offlineScanEnabled,
          onChanged: (v) {
            setState(() => _offlineScanEnabled = v);
            _writeHardwareConfig();
          },
        ),
        if (_offlineScanEnabled)
          ConfigToggleRow(
            icon: Icons.my_location,
            label: 'Tag away detections with last GPS',
            subtitle: 'Detections seen while away get the phone\'s last-known location (approximate).',
            color: const Color(0xFF4AB8FF),
            value: _offlineGpsTag,
            onChanged: (v) {
              setState(() => _offlineGpsTag = v);
              ref.read(sharedPreferencesProvider).setBool('offlineGpsTagEnabled', v);
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

  Future<void> _wifiDisconnect() async {
    try {
      await ref.read(bleManagerProvider).wifiDisconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi disconnected'), backgroundColor: AppTheme.warning),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _confirmWipeWifi() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe WiFi credentials?'),
        content: const Text(
          'Device will disconnect from WiFi and forget SSID + password. '
          'You will need to re-enter them to use WiFi OTA again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('WIPE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(bleManagerProvider).wifiWipeCreds();
      _ssidController.clear();
      _passController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi credentials wiped'), backgroundColor: AppTheme.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _writeWifiConfig() async {
    final ssid = _ssidController.text.trim();
    final pass = _passController.text;
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID required'), backgroundColor: AppTheme.warning),
      );
      return;
    }
    final ble = ref.read(bleManagerProvider);
    if (ble.wifiConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firmware too old — no WiFi config characteristic. Flash latest via webflasher.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    try {
      await ble.writeWifiConfig(ssid, pass);
      DebugLog.log('CONFIG: WiFi creds pushed: $ssid');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved. Connecting to AP (up to 20s)...'),
          backgroundColor: AppTheme.success,
        ),
      );
      // Poll the live status — firmware brings up STA on save.
      for (int i = 0; i < 12; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final r = await ble.readWifiConfig();
        DebugLog.log('CONFIG: WiFi poll ${i+1}: connected=${r.connected} ssid=${r.ssid} ip=${r.ip}');
        if (r.connected) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected: ${r.ssid} · ${r.ip} · ${r.rssi}dBm'),
              backgroundColor: AppTheme.success,
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved, but could not connect — verify creds/range'),
          backgroundColor: AppTheme.warning,
        ),
      );
    } catch (e) {
      DebugLog.log('CONFIG: WiFi config write failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Widget _buildMeshTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    final t = AppTheme.of(context);
    final modeEnc = appState.meshEnabled && appState.meshEncryption;
    final modePlain = appState.meshEnabled && !appState.meshEncryption;
    final modeOff = !appState.meshEnabled;
    final maxPeers = modeEnc ? 6 : (modePlain ? 12 : 0);
    final keyHex = appState.meshKeyFingerprint;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ConfigSectionHeader(label: 'MODE'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Text(
            'ESP-NOW peer slot limits per Espressif: 6 encrypted OR 12 unencrypted. Broadcast skips the peer table.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        _MeshModeTile(
          label: 'OFF',
          subtitle: 'Mesh disabled — single-node operation',
          selected: modeOff,
          onTap: () => appState.disableMesh(),
        ),
        _MeshModeTile(
          label: 'BROADCAST (PLAINTEXT)',
          subtitle: 'No peer table. Unlimited nodes hear every packet. ch=1',
          selected: modePlain,
          onTap: () => appState.enableMesh(
            encryption: false,
            peerMacs: const [],
          ),
        ),
        _MeshModeTile(
          label: 'ENCRYPTED (AES-256-GCM)',
          subtitle: 'Up to 6 unicast peers. Shared key. Per ESP-NOW limit.',
          selected: modeEnc,
          onTap: () async {
            if (appState.meshKey == null) {
              await appState.generateMeshKey();
            }
            await appState.enableMesh(
              encryption: true,
              peerMacs: const [],
            );
          },
        ),
        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'STATUS'),
        ConfigInfoRow(
          icon: Icons.hub,
          label: 'State',
          value: modeEnc
              ? 'ENCRYPTED'
              : modePlain
                  ? 'BROADCAST'
                  : 'OFF',
        ),
        ConfigInfoRow(
          icon: Icons.swap_vert,
          label: 'TX / RX',
          value: '${appState.meshTxCount} / ${appState.meshRxCount}',
        ),
        ConfigInfoRow(
          icon: Icons.group,
          label: 'Peer slots',
          value: modeOff
              ? '—'
              : '${appState.liveKnownNodes.where((n) => n.isNotEmpty && n != appState.nodeId).length} / $maxPeers',
        ),
        ConfigInfoRow(
          icon: Icons.sensors,
          label: 'Nodes heard',
          value: appState.liveKnownNodes
              .where((n) => n.isNotEmpty && n != appState.nodeId)
              .length
              .toString(),
        ),
        if (modeEnc) ...[
          const SizedBox(height: 16),
          const ConfigSectionHeader(label: 'KEY'),
          ConfigInfoRow(
            icon: Icons.key,
            label: 'Fingerprint',
            value: keyHex.isEmpty ? '(no key)' : keyHex,
          ),
          ConfigActionRow(
            icon: Icons.autorenew,
            label: 'Generate New Key',
            subtitle: 'Rotates the shared mesh key on this manager',
            onTap: () async {
              await appState.generateMeshKey();
              await appState.enableMesh(
                encryption: true,
                peerMacs: const [],
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'NODES'),
        ..._buildNodeManageRows(appState),
      ],
    );
  }

  List<Widget> _buildNodeManageRows(AppState appState) {
    final perNode = appState.detectionsPerSourceNode;
    final live = appState.liveKnownNodes;
    final all = <String>{...appState.knownNodes, ...live};
    if (appState.nodeId.isEmpty && !appState.isConnected) all.add('LOCAL');
    if (all.isEmpty) {
      return [
        const ConfigInfoRow(
          icon: Icons.hub_outlined,
          label: 'No nodes yet',
          value: '',
        ),
      ];
    }
    int sortFn(String a, String b) {
      if (a == 'LOCAL') return -1;
      if (b == 'LOCAL') return 1;
      if (a == appState.nodeId) return -1;
      if (b == appState.nodeId) return 1;
      return a.compareTo(b);
    }
    final liveIds = all.where((id) => live.contains(id) || id == appState.nodeId).toList()
      ..sort(sortFn);
    final offlineIds = all.where((id) => !live.contains(id) && id != appState.nodeId).toList()
      ..sort(sortFn);
    Widget row(String id, {required bool online}) {
      final dets = perNode[id] ?? 0;
      final label = appState.labelForNode(id);
      final hasCustom = appState.nodeLabels.containsKey(id);
      final isSelf = id == appState.nodeId && id != 'LOCAL';
      final parts = <String>[
        if (hasCustom) id,
        if (isSelf) 'this device',
        online ? 'LIVE' : 'offline',
        '$dets dets',
      ];
      return ConfigActionRow(
        icon: isSelf ? Icons.smartphone : (online ? Icons.memory : Icons.memory_outlined),
        label: label,
        subtitle: parts.join('  ·  '),
        onTap: () => _renameNodeDialog(appState, id),
      );
    }
    final widgets = <Widget>[];
    for (final id in liveIds) widgets.add(row(id, online: true));
    if (offlineIds.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(const ConfigSectionHeader(label: 'OFFLINE'));
      for (final id in offlineIds) widgets.add(row(id, online: false));
    }
    return widgets;
  }

  Future<void> _renameNodeDialog(AppState appState, String id) async {
    final controller = TextEditingController(text: appState.nodeLabels[id] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename $id'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            hintText: 'Custom label (blank = reset)',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          if (id != 'LOCAL' && id != appState.nodeId)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__forget__'),
              child: const Text('FORGET', style: TextStyle(color: AppTheme.error)),
            ),
          if (appState.nodeLabels.containsKey(id))
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('CLEAR'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == '__forget__') {
      appState.forgetNode(id);
      return;
    }
    appState.setNodeLabel(id, result.trim());
  }

  Widget _buildFirmwareTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    final isMgr = ref.read(bleManagerProvider).isManagerConnected;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        ConfigSectionHeader(label: isMgr ? 'MANAGER INFO' : 'NODE INFO'),
        ConfigInfoRow(
          icon: Icons.numbers, label: 'Version', value: _fwVersion,
        ),
        ConfigInfoRow(
          icon: Icons.fingerprint,
          label: isMgr ? 'Manager ID' : 'Node ID',
          value: _nodeId,
        ),
        ConfigInfoRow(
          icon: Icons.memory, label: 'Free Heap', value: _heapFree,
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'WIFI NETWORK'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Text(
            'Device joins your network to download firmware over WiFi. Set once — used by the WiFi update below.',
            style: TextStyle(color: AppTheme.of(context).textDim, fontSize: 11),
          ),
        ),
        _WifiStatusPanel(),
        const SizedBox(height: 12),
        _WifiEnableToggle(),
        const SizedBox(height: 12),
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
        Row(
          children: [
            Expanded(
              child: ConfigCompactButton(
                icon: Icons.save,
                label: 'Save',
                color: AppTheme.success,
                onTap: _writeWifiConfig,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ConfigCompactButton(
                icon: Icons.link_off,
                label: 'Disconnect',
                onTap: _wifiDisconnect,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ConfigCompactButton(
                icon: Icons.delete_forever,
                label: 'Wipe',
                destructive: true,
                onTap: _confirmWipeWifi,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'UPDATES'),
        _OtaSection(currentVersion: _fwVersion),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'DANGER ZONE'),
        ConfigActionRow(
          icon: Icons.refresh,
          label: 'Reboot Device',
          subtitle: 'Restart firmware without erasing settings',
          onTap: _confirmReboot,
        ),
        ConfigActionRow(
          icon: Icons.restart_alt,
          label: 'Factory Reset',
          subtitle: 'Erase all settings and reboot',
          destructive: true,
          onTap: _confirmFactoryReset,
        ),
      ],
    );
  }

  Future<void> _confirmReboot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reboot device?'),
        content: const Text('Device will restart. BLE will reconnect automatically.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REBOOT'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bleManagerProvider).rebootDevice();
  }

  Future<void> _confirmFactoryReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factory reset?'),
        content: const Text(
          'This will ERASE all settings (watchlists, WiFi credentials, '
          'hardware config, mesh keys) and reboot the device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('ERASE & REBOOT'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bleManagerProvider).factoryReset();
  }

  void _writeHardwareConfig() {
    ref.read(bleManagerProvider).writeHardwareConfig(
          buzzer: _buzzerEnabled,
          led: _ledEnabled,
          neopixelBrightness: _neopixelBrightness,
          buzzerVolume: _buzzerVolume,
          extendedOui: _flockExtendedOui,
          offlineScan: _offlineScanEnabled,
        );
    ref.read(sharedPreferencesProvider)
        .setBool('offlineScanEnabled', _offlineScanEnabled);
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

  static const _steps = [50, 100, 110, 150, 200, 250, 300, 350, 400, 500, 800, 1000, 1500, 2000, 3000, 5000];

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

class _AutoConnectToggle extends ConsumerStatefulWidget {
  const _AutoConnectToggle();

  @override
  ConsumerState<_AutoConnectToggle> createState() => _AutoConnectToggleState();
}

class _AutoConnectToggleState extends ConsumerState<_AutoConnectToggle> {
  late bool _value =
      ref.read(sharedPreferencesProvider).getBool('autoConnectEnabled') ?? false;

  Future<void> _set(bool v) async {
    setState(() => _value = v);
    await ref.read(sharedPreferencesProvider).setBool('autoConnectEnabled', v);
  }

  @override
  Widget build(BuildContext context) {
    return ConfigToggleRow(
      icon: _value ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
      label: 'Auto-connect on launch',
      subtitle: _value
          ? 'Reconnects to the last OUI-SPY device at startup'
          : 'Connect manually from the home screen',
      color: AppTheme.accent,
      value: _value,
      onChanged: _set,
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
            WatchlistMatchType.serviceUuid => '0xFD5F',
          };
          final label = switch (matchType) {
            WatchlistMatchType.oui => 'OUI prefix (3 bytes)',
            WatchlistMatchType.fullMac => 'Full MAC address',
            WatchlistMatchType.name => 'Device name (supports * and ?)',
            WatchlistMatchType.serviceUuid => 'BLE 16-bit service UUID',
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
                              WatchlistMatchType.serviceUuid => 'UUID',
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
                  if (matchType == WatchlistMatchType.serviceUuid) ...[
                    const SizedBox(height: 6),
                    Text(
                      '16-bit BLE service UUID advertised by the device '
                      '(e.g. 0xFD5F). Matched on-device by detector nodes.',
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
                  } else if (matchType == WatchlistMatchType.serviceUuid) {
                    final hex = raw
                        .replaceFirst(
                            RegExp(r'^0x', caseSensitive: false), '')
                        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
                    if (hex.isEmpty || hex.length > 4) return;
                    identifier = '0x${hex.toUpperCase().padLeft(4, '0')}';
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
    final isEnabled = entry.enabled;
    final IconData icon = switch (entry.matchType) {
      WatchlistMatchType.oui => Icons.radar,
      WatchlistMatchType.fullMac => Icons.fingerprint,
      WatchlistMatchType.name => Icons.badge_outlined,
      WatchlistMatchType.serviceUuid => Icons.bluetooth_searching,
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
          border: Border.all(
            color: isEnabled ? t.border : t.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: (isEnabled ? AppTheme.detector : t.textDim)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 16,
                color: isEnabled ? AppTheme.detector : t.textDim,
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
                      color: isEnabled ? t.textPrimary : t.textDim,
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
                          color: (isEnabled ? AppTheme.detector : t.textDim)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          entry.matchType.label,
                          style: TextStyle(
                            color: isEnabled ? AppTheme.detector : t.textDim,
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
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: isEnabled,
                onChanged: (v) =>
                    ref.read(watchlistProvider).toggleEnabled(entry, enabled: v),
                activeTrackColor: AppTheme.detector.withValues(alpha: 0.3),
                activeColor: AppTheme.detector,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DetSort {
  time('TIME'),
  rssi('RSSI'),
  mac('MAC');

  const _DetSort(this.label);
  final String label;
}

enum _RadioSel { all, ble, wifi }

/// 0 = BLE, 1 = WiFi, 2 = unknown — for a raw DB detection row.
int _detRadioRank(Map<String, dynamic> d) {
  final method = (d['detectionMethod'] as String?) ?? '';
  if (isBleMethod(method)) return 0;
  if (isWifiMethod(method)) return 1;
  final engine = (d['engine'] as String?) ?? '';
  if (engine == 'flockBle' || engine == 'detector') return 0;
  if (engine == 'flockWifi') return 1;
  final ch = (d['channel'] as int?) ?? 0;
  return (ch >= 1 && ch <= 14) ? 1 : 0;
}

/// Detection-method label — the exact text shown on each detections-tab row.
String _detMethodLabel(String method) => switch (method) {
  'oui_addr1' => 'ADDR1 (DST)',
  'oui_addr2' => 'ADDR2 (SRC)',
  'oui_addr3' => 'ADDR3 (BSSID)',
  'ssid' => 'SSID',
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
  bool _noGpsOnly = false;
  _RadioSel _radioFilter = _RadioSel.all;
  String? _methodFilter; // null = all, else a raw detectionMethod string
  bool _showMap = false;
  bool _pcapExpanded = true;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  String _search = '';
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

  Future<void> _clearAll() async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all detections?'),
        content: Text('Permanently deletes ${_detections.length} detection(s) from the database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await db.clearFlockDetectorDetections();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      backgroundColor: AppTheme.success,
      content: Text('Cleared $n detection(s)'),
    ));
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadPcapExpanded();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPcapExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool('pcaps_panel_expanded');
    if (v != null && mounted && v != _pcapExpanded) {
      setState(() => _pcapExpanded = v);
    }
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
    } else if (_engineFilter == 'drone') {
      list = list.where((d) => d['engine'] == 'skySpy').toList();
    }

    if (_noGpsOnly) {
      list = list
          .where((d) => d['latitude'] == null || d['longitude'] == null)
          .toList();
    }

    if (_radioFilter != _RadioSel.all) {
      final wantRank = _radioFilter == _RadioSel.ble ? 0 : 1;
      list = list.where((d) => _detRadioRank(d) == wantRank).toList();
    }

    if (_methodFilter != null) {
      list = list
          .where((d) => (d['detectionMethod'] as String?) == _methodFilter)
          .toList();
    }

    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final mac = (d['macAddress'] as String?)?.toLowerCase() ?? '';
        final name = (d['deviceName'] as String?)?.toLowerCase() ?? '';
        final ssid = (d['ssid'] as String?)?.toLowerCase() ?? '';
        final method = (d['detectionMethod'] as String?)?.toLowerCase() ?? '';
        final engine = (d['engine'] as String?)?.toLowerCase() ?? '';
        return mac.contains(q) || name.contains(q) || ssid.contains(q) ||
            method.contains(q) || engine.contains(q);
      }).toList();
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
    'skySpy' => AppTheme.skySpy,
    _ => AppTheme.accent,
  };

  String _engineLabel(String engine) => switch (engine) {
    'flockBle' => 'FLOCK BLE',
    'flockWifi' => 'FLOCK WiFi',
    'detector' => 'DETECTOR',
    'skySpy' => 'DRONE',
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

  Future<void> _showPicker<T>({
    required String title,
    required List<(T, String)> options,
    required T current,
    required ValueChanged<T> onSelected,
  }) {
    final t = AppTheme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: t.textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (val, lbl) in options)
                      ListTile(
                        title: Text(lbl,
                            style: TextStyle(
                                color: val == current
                                    ? AppTheme.accent
                                    : t.textPrimary,
                                fontSize: 14,
                                fontWeight: val == current
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        trailing: val == current
                            ? const Icon(Icons.check,
                                size: 18, color: AppTheme.accent)
                            : null,
                        onTap: () {
                          onSelected(val);
                          Navigator.pop(ctx);
                        },
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

  Future<void> _pickRadio() => _showPicker<_RadioSel>(
        title: 'RADIO',
        current: _radioFilter,
        options: const [
          (_RadioSel.all, 'ALL'),
          (_RadioSel.ble, 'BLE'),
          (_RadioSel.wifi, 'WIFI'),
        ],
        onSelected: (v) => setState(() => _radioFilter = v),
      );

  Future<void> _pickMethod() {
    final methods = _detections
        .map((d) => (d['detectionMethod'] as String?) ?? '')
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => _detMethodLabel(a).compareTo(_detMethodLabel(b)));
    return _showPicker<String?>(
      title: 'METHOD',
      current: _methodFilter,
      options: [
        (null, 'ALL'),
        for (final m in methods) (m, _detMethodLabel(m)),
      ],
      onSelected: (v) => setState(() => _methodFilter = v),
    );
  }

  static final _csvTs = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

  static String _csvEscape(String v) {
    if (v.isEmpty) return '';
    if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  String _buildCsv(List<Map<String, dynamic>> items) {
    const cols = <String>[
      'timestamp_utc', 'session_id', 'engine', 'method',
      'mac', 'device_name', 'ssid', 'rssi_dbm', 'channel',
      'lat', 'lon',
    ];
    final buf = StringBuffer()..writeln(cols.join(','));
    for (final d in items) {
      final tsMs = d['appTimestamp'] as int?;
      final ts = tsMs == null
          ? ''
          : _csvTs.format(DateTime.fromMillisecondsSinceEpoch(tsMs).toUtc());
      final lat = d['latitude'];
      final lon = d['longitude'];
      final row = <String>[
        ts,
        (d['sessionId'] as String?) ?? '',
        (d['engine'] as String?) ?? '',
        (d['detectionMethod'] as String?) ?? '',
        (d['macAddress'] as String?) ?? '',
        (d['deviceName'] as String?) ?? '',
        (d['ssid'] as String?) ?? '',
        (d['rssi']?.toString()) ?? '',
        (d['channel']?.toString()) ?? '',
        lat == null ? '' : lat.toString(),
        lon == null ? '' : lon.toString(),
      ].map(_csvEscape).toList();
      buf.writeln(row.join(','));
    }
    return buf.toString();
  }

  Future<void> _exportCsv(
      BuildContext context, List<Map<String, dynamic>> items) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = _buildCsv(items);
      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/oui_spy_detections_$ts.csv');
      await file.writeAsString(csv);
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 100, 100);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'OUI-SPY Detections Export (${items.length} detections)',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
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
              'Run a wardrive with Flock, Detector, or Sky Spy engines to see detections here.',
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
    final droneCount = _detections.where((d) => d['engine'] == 'skySpy').length;
    final noGpsCount = _detections
        .where((d) => d['latitude'] == null || d['longitude'] == null)
        .length;

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _FilterChip(
                label: 'ALL (${_detections.length})',
                selected: _engineFilter == null && !_noGpsOnly,
                color: AppTheme.accent,
                onTap: () => setState(() {
                  _engineFilter = null;
                  _noGpsOnly = false;
                }),
              ),
              _FilterChip(
                label: 'FLOCK ($flockCount)',
                selected: _engineFilter == 'flock',
                color: AppTheme.flockBle,
                onTap: () => setState(() =>
                    _engineFilter = _engineFilter == 'flock' ? null : 'flock'),
              ),
              _FilterChip(
                label: 'DETECT ($detectorCount)',
                selected: _engineFilter == 'detector',
                color: AppTheme.detector,
                onTap: () => setState(() =>
                    _engineFilter = _engineFilter == 'detector' ? null : 'detector'),
              ),
              _FilterChip(
                label: 'DRONES ($droneCount)',
                selected: _engineFilter == 'drone',
                color: AppTheme.skySpy,
                onTap: () => setState(() =>
                    _engineFilter = _engineFilter == 'drone' ? null : 'drone'),
              ),
              _FilterChip(
                label: 'NO GPS ($noGpsCount)',
                selected: _noGpsOnly,
                color: AppTheme.gpsNone,
                onTap: () => setState(() => _noGpsOnly = !_noGpsOnly),
              ),
            ],
          ),
        ),
        // Radio + method filter dropdowns
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: _DetDropdown(
                  icon: Icons.cell_tower,
                  label: 'RADIO',
                  value: switch (_radioFilter) {
                    _RadioSel.all => 'ALL',
                    _RadioSel.ble => 'BLE',
                    _RadioSel.wifi => 'WIFI',
                  },
                  active: _radioFilter != _RadioSel.all,
                  onTap: _pickRadio,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DetDropdown(
                  icon: Icons.tune,
                  label: 'METHOD',
                  value: _methodFilter == null
                      ? 'ALL'
                      : _detMethodLabel(_methodFilter!),
                  active: _methodFilter != null,
                  onTap: _pickMethod,
                ),
              ),
            ],
          ),
        ),
        // Sort buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text('SORT', style: TextStyle(
                color: t.textSecondary, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
              const SizedBox(width: 8),
              for (final s in _DetSort.values) ...[
                _SortBtn(
                  label: s.label,
                  active: _sort == s,
                  ascending: _ascending,
                  onTap: () => _toggleSort(s),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              GestureDetector(
                onTap: items.isEmpty ? null : () => _exportCsv(context, items),
                child: Icon(
                  Icons.ios_share,
                  size: 16,
                  color: items.isEmpty
                      ? t.textDim.withValues(alpha: 0.4)
                      : AppTheme.accent,
                ),
              ),
              const SizedBox(width: 12),
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
                onTap: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    _search = '';
                  }
                }),
                child: Icon(
                  _searchOpen ? Icons.search_off : Icons.search,
                  size: 16,
                  color: (_searchOpen || _search.isNotEmpty)
                      ? AppTheme.accent
                      : t.textDim,
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
                    : Icon(Icons.refresh, size: 16, color: AppTheme.detector),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _detections.isEmpty ? null : _clearAll,
                child: Icon(
                  Icons.delete_sweep,
                  size: 16,
                  color: _detections.isEmpty
                      ? t.textDim.withValues(alpha: 0.4)
                      : AppTheme.error,
                ),
              ),
            ],
          ),
        ),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(fontSize: 12, color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: 'MAC, name, SSID, method…',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: t.border),
                  ),
                ),
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          flex: 3,
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
        const Divider(height: 1, thickness: 1),
        if (_pcapExpanded)
          Expanded(
            flex: 2,
            child: _PcapInlineSection(
              onExpandedChanged: (v) => setState(() => _pcapExpanded = v),
            ),
          )
        else
          _PcapInlineSection(
            onExpandedChanged: (v) => setState(() => _pcapExpanded = v),
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
    final timeStr = DateFormat('MMM d yyyy HH:mm').format(ts);
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.22)
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.55),
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Text(label, style: TextStyle(
          color: color,
          fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3,
        )),
      ),
    );
  }
}

class _DetDropdown extends StatelessWidget {
  const _DetDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.12)
              : t.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppTheme.accent : t.border,
            width: active ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: active ? AppTheme.accent : t.textDim),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(
              color: t.textDim, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
            const SizedBox(width: 6),
            Expanded(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? AppTheme.accent : t.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: t.textDim),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.18)
              : t.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppTheme.accent : t.border,
            width: active ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              color: active ? AppTheme.accent : t.textSecondary,
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5,
            )),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 13, color: AppTheme.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _droneTransportShort(String method) => switch (method) {
      'odid_ble' => 'BLE',
      'odid_nan' => 'NAN',
      'odid_beacon' => 'BEACON',
      _ => method.toUpperCase(),
    };

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
    final timeStr = DateFormat('MMM d yyyy HH:mm').format(ts);
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
                      if ((data['uavId'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('UAS-ID ${data['uavId']}', style: TextStyle(
                            color: engineColor, fontSize: 12,
                            fontFamily: 'monospace', fontWeight: FontWeight.w600,
                          ), overflow: TextOverflow.ellipsis),
                        ),
                      if (data['engine'] == 'skySpy' &&
                          (((data['memberMacs'] as List?)?.length ?? 1) > 1 ||
                              ((data['transports'] as List?)?.length ?? 0) > 1))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${(data['memberMacs'] as List).length} MACs · '
                            '${(data['transports'] as List).map((m) => _droneTransportShort(m as String)).join(' · ')}',
                            style: TextStyle(
                              color: t.textDim, fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.textDim.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_detMethodLabel(method),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary, fontSize: 10,
                          fontWeight: FontWeight.w600,
                        )),
                    ),
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
                if ((data['authMode'] as int? ?? 0) > 0) ...[
                  const SizedBox(width: 8),
                  _ConfigAuthPill(authMode: data['authMode'] as int),
                ],
                if (!hasGps) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.location_off, size: 12, color: AppTheme.gpsNone),
                  const SizedBox(width: 3),
                  Text('NO GPS', style: TextStyle(
                    color: AppTheme.gpsNone, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5,
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

enum _FleetStatus { queued, active, done, failed }

class _FleetItem {
  _FleetItem({required this.id, required this.label, required this.isManager});
  final String id;
  final String label;
  final bool isManager;
  _FleetStatus status = _FleetStatus.queued;
  String detail = 'Queued';
}

class _OtaSection extends ConsumerStatefulWidget {
  const _OtaSection({required this.currentVersion});
  final String currentVersion;

  @override
  ConsumerState<_OtaSection> createState() => _OtaSectionState();
}

class _OtaSectionState extends ConsumerState<_OtaSection> {
  OtaRelease? _availableRelease;
  OtaProgress? _progress;
  StreamSubscription<OtaProgress>? _sub;
  StreamSubscription<({int status, int bytesRead})>? _wifiSub;
  String? _checkStatus;
  bool _wifiConfigured = false;
  String _wifiSsid = '';
  int _wifiBytesRead = 0;
  int? _wifiStatus;
  Timer? _wifiPoll;
  OtaRelease? _nodeRelease;
  String? _nodeStatus;
  List<_FleetItem> _fleet = const [];
  bool _fleetRunning = false;
  bool _mgrReconnecting = false;
  bool _autoWifiUpdate = true;
  static const String _autoWifiPrefKey = 'ota_auto_wifi_update';
  String _nodeBoard = 'xiao_s3';
  static const String _nodeBoardPrefKey = 'ota_node_board';
  static const List<String> _nodeBoards = ['xiao_s3', 's3_devkitc'];

  @override
  void initState() {
    super.initState();
    final ota = ref.read(otaServiceProvider);
    _sub = ota.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    _wifiSub = ref.read(bleManagerProvider).wifiOtaUpdates.listen((evt) {
      if (mounted) {
        setState(() {
          _wifiStatus = evt.status;
          _wifiBytesRead = evt.bytesRead;
        });
      }
    });
    _readWifiState();
    _loadAutoWifi();
    _loadNodeBoard();
    // Poll WiFi status every 3s so user sees connection state change
    _wifiPoll = Timer.periodic(const Duration(seconds: 3), (_) => _readWifiState());
  }

  Future<void> _loadAutoWifi() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_autoWifiPrefKey);
    if (v != null && mounted) setState(() => _autoWifiUpdate = v);
  }

  Future<void> _setAutoWifi(bool v) async {
    setState(() => _autoWifiUpdate = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoWifiPrefKey, v);
  }

  Future<void> _loadNodeBoard() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_nodeBoardPrefKey);
    if (v != null && _nodeBoards.contains(v) && mounted) {
      setState(() => _nodeBoard = v);
    }
  }

  Future<void> _setNodeBoard(String v) async {
    setState(() => _nodeBoard = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nodeBoardPrefKey, v);
  }

  /// When the user has opted into auto-connect, enable WiFi STA on the manager
  /// before a WiFi OTA so it joins the saved network for the download (and
  /// rejoins after the reboot). No-op without saved credentials.
  Future<void> _ensureWifiForUpdate() async {
    return;
  }

  Future<void> _readWifiState() async {
    try {
      final res = await ref.read(bleManagerProvider).readWifiConfig();
      if (!mounted) return;
      setState(() {
        _wifiConfigured = res.hasCreds;
        _wifiSsid = res.ssid;
      });
    } on Exception catch (e) {
      // Older firmware: char absent — leave _wifiConfigured = false
      DebugLog.log('OTA: wifi status read failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wifiSub?.cancel();
    _wifiPoll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checkStatus = 'Checking...';
      _availableRelease = null;
    });
    try {
      final ota = ref.read(otaServiceProvider);
      final ble = ref.read(bleManagerProvider);
      final pair = await ota.fetchLatestPair(
        board: ble.board,
        role: ble.role,
        includeNode: ble.isManagerConnected,
        nodeBoard: _nodeBoard,
      );
      if (!mounted) return;
      final primary = pair.primary;
      String status;
      OtaRelease? avail;
      if (pair.error != null) {
        status = pair.error!;
      } else if (primary == null) {
        status = 'No matching firmware in the latest release.';
      } else {
        final cur = OtaService.parseVersion(widget.currentVersion) ?? [0, 0, 0];
        final newer = OtaService.compareVersion(primary.version, cur) > 0;
        avail = newer ? primary : null;
        status = newer
            ? 'Update available: ${primary.tag}'
            : 'Already up to date (${primary.tag})';
      }
      setState(() {
        _availableRelease = avail;
        _nodeRelease = pair.node;
        _checkStatus = status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkStatus = 'Check failed: $e');
    }
  }

  List<Widget> _buildNodeUpdateSection(ResolvedTheme t, bool busy) {
    final ble = ref.read(bleManagerProvider);
    if (!ble.isManagerConnected) return const [];
    final appState = ref.watch(appStateProvider);
    final nodes = appState.liveKnownNodes
        .where((n) => n.isNotEmpty && n != appState.nodeId)
        .toList()
      ..sort();
    final cur = OtaService.parseVersion(widget.currentVersion);
    final nodeNewer = _nodeRelease != null &&
        cur != null &&
        OtaService.compareVersion(_nodeRelease!.version, cur) > 0;

    return [
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Icon(Icons.hub_outlined, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
            Text('REMOTE NODES',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_nodeRelease != null)
              Text(
                  nodeNewer
                      ? 'latest ${_nodeRelease!.tag}'
                      : 'latest ${_nodeRelease!.tag} · On latest version',
                  style: TextStyle(
                      color: nodeNewer ? AppTheme.accent : t.textDim,
                      fontSize: 10)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(
          children: [
            Text('Node board',
                style: TextStyle(color: t.textSecondary, fontSize: 11)),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _nodeBoard,
              isDense: true,
              dropdownColor: t.surface,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              underline: const SizedBox.shrink(),
              items: [
                for (final b in _nodeBoards)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (busy || _fleetRunning)
                  ? null
                  : (v) {
                      if (v == null || v == _nodeBoard) return;
                      _setNodeBoard(v);
                      _check();
                    },
            ),
          ],
        ),
      ),
      if (nodes.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('No live nodes. Power them on and Check for Update.',
              style: TextStyle(color: t.textDim, fontSize: 11)),
        )
      else if (_nodeRelease == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Tap Check for Update to fetch the latest node firmware.',
              style: TextStyle(color: t.textDim, fontSize: 11)),
        ),
      for (final id in nodes)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(
            children: [
              Icon(Icons.sensors, size: 14, color: t.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(appState.labelForNode(id),
                    style: TextStyle(color: t.textPrimary, fontSize: 12)),
              ),
              Builder(builder: (_) {
                final v = appState.nodeFwVersion(id);
                final outdated = v != null &&
                    _nodeRelease != null &&
                    OtaService.compareVersion(_nodeRelease!.version,
                            OtaService.parseVersion(v) ?? const [0]) >
                        0;
                return Text(
                  v == null ? 'v?' : 'v$v',
                  style: TextStyle(
                    color: outdated ? AppTheme.accent : t.textSecondary,
                    fontSize: 11,
                    fontWeight: outdated ? FontWeight.w700 : FontWeight.w400,
                  ),
                );
              }),
            ],
          ),
        ),
      if (nodes.isNotEmpty && _nodeRelease != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: ElevatedButton.icon(
            onPressed: (busy || _fleetRunning) ? null : _updateNodes,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            icon: const Icon(Icons.wifi, size: 16),
            label: Text(
                'Update ${nodes.length} node${nodes.length == 1 ? '' : 's'} over WiFi'),
          ),
        ),
      if (_nodeStatus != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(_nodeStatus!,
              style: TextStyle(color: t.textSecondary, fontSize: 11)),
        ),
    ];
  }

  Future<void> _installWifi() async {
    final release = _availableRelease;
    if (release == null) return;
    final ota = ref.read(otaServiceProvider);
    await _ensureWifiForUpdate();
    await ota.performWifiUpdate(release);
  }

  /// Fleet WiFi update: the manager broadcasts its saved WiFi creds + the node
  /// firmware URL to every node over mesh. Each node saves the creds, reboots
  /// into WiFi-OTA mode, joins the network, downloads + flashes itself, then
  /// rejoins the mesh. The phone stays on the manager (BLE) the whole time.
  /// Nodes go offline from the mesh while they self-update.
  Future<bool> _pushWifiFleet(_FleetItem nodesItem) async {
    final ble = ref.read(bleManagerProvider);
    final nodeRelease = _nodeRelease;
    if (nodeRelease == null) return false;
    if (!_wifiConfigured) {
      setState(() {
        nodesItem.status = _FleetStatus.failed;
        nodesItem.detail =
            'Manager has no saved WiFi — set creds in the WIFI NETWORK section first.';
      });
      return false;
    }
    setState(() {
      nodesItem.status = _FleetStatus.active;
      nodesItem.detail = 'Pushing WiFi creds + update to nodes…';
    });
    final done = Completer<bool>();
    final sub = ble.fleetOtaUpdates.listen((e) {
      if (!mounted) return;
      setState(() {
        if (e.phase == 2) {
          nodesItem.status = _FleetStatus.done;
          nodesItem.detail =
              'Pushed — nodes rebooting to self-update over WiFi (~60–90s). '
              'They drop off mesh, then rejoin when done.';
          if (!done.isCompleted) done.complete(true);
        } else if (e.phase == 0x80) {
          nodesItem.status = _FleetStatus.failed;
          nodesItem.detail =
              'Manager has no saved WiFi — set creds in the WIFI NETWORK section first.';
          if (!done.isCompleted) done.complete(false);
        } else if (e.phase == 0x81) {
          nodesItem.status = _FleetStatus.failed;
          nodesItem.detail = 'WiFi creds + URL too long for one mesh packet.';
          if (!done.isCompleted) done.complete(false);
        }
      });
    });
    try {
      await ble.triggerFleetWifiOta(nodeRelease.assetUrl);
      return await done.future
          .timeout(const Duration(seconds: 20), onTimeout: () {
        if (mounted) {
          setState(() {
            nodesItem.status = _FleetStatus.done;
            nodesItem.detail =
                'Update pushed — nodes reboot to self-update over WiFi (~60–90s).';
          });
        }
        return true;
      });
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _updateNodes() async {
    final ble = ref.read(bleManagerProvider);
    final ota = ref.read(otaServiceProvider);
    final managerId = ble.connectedDeviceId;
    if (_nodeRelease == null) {
      setState(() => _nodeStatus = 'Tap "Check for Update" first.');
      return;
    }
    if (managerId == null) {
      setState(() => _nodeStatus = 'Manager not connected.');
      return;
    }
    final appState = ref.read(appStateProvider);
    final nodeIds = appState.liveKnownNodes
        .where((n) => n.isNotEmpty && n != appState.nodeId)
        .toList();
    final nodesItem = _FleetItem(
        id: 'nodes',
        label: nodeIds.isEmpty ? 'Nodes' : 'Nodes (${nodeIds.length})',
        isManager: false);
    setState(() {
      _fleet = [nodesItem];
      _fleetRunning = true;
    });
    ota.markOtaActive(ttl: const Duration(minutes: 3));
    try {
      await _pushWifiFleet(nodesItem);
    } finally {
      ota.clearOtaActive();
      if (mounted) setState(() => _fleetRunning = false);
    }
  }

  Future<void> _updateAll() async {
    final ble = ref.read(bleManagerProvider);
    final ota = ref.read(otaServiceProvider);
    final mgrRelease = _availableRelease;
    final nodeRelease = _nodeRelease;
    final managerId = ble.connectedDeviceId;
    if (managerId == null) {
      setState(() => _checkStatus = 'Manager not connected.');
      return;
    }
    if (mgrRelease == null && nodeRelease == null) {
      setState(() => _checkStatus = 'Tap "Check for Update" first.');
      return;
    }
    final appState = ref.read(appStateProvider);
    final nodeIds = appState.liveKnownNodes
        .where((n) => n.isNotEmpty && n != appState.nodeId)
        .toList();
    final hasNodes = nodeRelease != null;
    final hasMgr = mgrRelease != null;

    final fleet = <_FleetItem>[
      if (hasNodes)
        _FleetItem(
            id: 'nodes',
            label: nodeIds.isEmpty ? 'Nodes' : 'Nodes (${nodeIds.length})',
            isManager: false),
      if (hasMgr)
        _FleetItem(
            id: 'manager',
            label: 'Manager ${appState.labelForNode(appState.nodeId)}',
            isManager: true),
    ];
    setState(() {
      _fleet = fleet;
      _fleetRunning = true;
      _mgrReconnecting = false;
    });
    ota.markOtaActive(ttl: const Duration(minutes: 8));

    try {
      if (hasNodes) {
        await _pushWifiFleet(fleet.first);
        // Let the manager finish broadcasting creds+URL to the nodes before it
        // reboots into its own WiFi update below (the push runs ~3.5s on-device).
        await Future<void>.delayed(const Duration(seconds: 6));
      }

      if (hasMgr) {
        final mgr = fleet.firstWhere((f) => f.isManager);
        setState(() {
          mgr.status = _FleetStatus.active;
          mgr.detail = 'Updating manager…';
        });
        final mok = await ota.performWifiUpdate(mgrRelease);
        if (!mok) {
          setState(() {
            mgr.status = _FleetStatus.failed;
            mgr.detail = 'Manager update failed';
          });
          return;
        }
        setState(() {
          _mgrReconnecting = true;
          mgr.detail = 'Rebooting + reconnecting…';
        });
        await Future<void>.delayed(const Duration(seconds: 5));
        final re = await ble.connectByIdAndReady(managerId);
        setState(() => _mgrReconnecting = false);
        setState(() {
          mgr.status = re ? _FleetStatus.done : _FleetStatus.failed;
          mgr.detail = re
              ? 'Updated ${mgrRelease.tag}'
              : 'Did not reconnect — tap CONNECT';
        });
      }
    } finally {
      ota.clearOtaActive();
      if (mounted) setState(() => _fleetRunning = false);
    }
  }

  Future<void> _flashLocalBin() async {
    const typeGroup = XTypeGroup(
      label: 'firmware',
      extensions: ['bin'],
      uniformTypeIdentifiers: ['public.data'],
      mimeTypes: ['application/octet-stream'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ble = ref.read(bleManagerProvider);
    final name = file.name;
    final board = ble.board;
    final role = ble.role;
    bool mismatch = false;
    String warn = '';
    if (board.isNotEmpty && !name.toLowerCase().contains(board.toLowerCase())) {
      mismatch = true;
      warn = 'File does not include board "$board" in name. Wrong target = bricked device.';
    }
    if (role.isNotEmpty && !name.toLowerCase().contains('-$role-')) {
      mismatch = true;
      warn = warn.isEmpty
          ? 'File does not include role "$role" in name.'
          : '$warn Also role "$role" missing.';
    }
    if (mismatch) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Board mismatch'),
          content: Text('$warn\n\nProceed anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('FLASH ANYWAY', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final ota = ref.read(otaServiceProvider);
    await ota.pushLocalImage(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final busy = ref.read(otaServiceProvider).isRunning &&
        _progress != null &&
        _progress!.phase != OtaPhase.idle &&
        _progress!.phase != OtaPhase.upToDate &&
        _progress!.phase != OtaPhase.error &&
        _progress!.phase != OtaPhase.rebooting;

    final p = _progress;
    final bleActive = p != null &&
        (p.phase == OtaPhase.downloading ||
            p.phase == OtaPhase.uploading ||
            p.phase == OtaPhase.verifying ||
            p.phase == OtaPhase.rebooting ||
            p.phase == OtaPhase.error);
    OtaStepperModel? stepper;
    if (_wifiStatus != null) {
      stepper = OtaStepperModel.fromWifi(_wifiStatus!, _wifiBytesRead);
    } else if (bleActive) {
      stepper = OtaStepperModel.fromBleProgress(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigActionRow(
          icon: Icons.system_update,
          label: 'Check for Update',
          subtitle: 'Compare against latest GitHub release',
          onTap: busy ? null : _check,
        ),
        if (_checkStatus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(_checkStatus!,
                style: TextStyle(color: t.textSecondary, fontSize: 11)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Icon(Icons.wifi_tethering,
                  size: 18,
                  color: _autoWifiUpdate ? AppTheme.accent : t.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-connect WiFi for firmware update',
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(
                      _wifiConfigured
                          ? 'Manager joins saved WiFi to download the update'
                          : 'Save WiFi credentials in the WIFI NETWORK section above to use this',
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoWifiUpdate,
                onChanged: _setAutoWifi,
                activeThumbColor: AppTheme.accent,
              ),
            ],
          ),
        ),
        if (_availableRelease != null && !busy) ...[
          if (_wifiConfigured) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: ElevatedButton.icon(
                onPressed: _installWifi,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                icon: const Icon(Icons.wifi, size: 16),
                label: Text('Install via WiFi — ${_availableRelease!.tag}'),
              ),
            ),
            if (ref.read(bleManagerProvider).isManagerConnected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: ElevatedButton.icon(
                  onPressed: _fleetRunning ? null : _updateAll,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent),
                  icon: const Icon(Icons.system_update_alt, size: 16),
                  label: const Text('Update All — manager + nodes (WiFi)'),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Set WiFi credentials in the WIFI NETWORK section above to update '
                'over WiFi.',
                style: TextStyle(color: AppTheme.warning, fontSize: 12),
              ),
            ),
        ],
        ..._buildNodeUpdateSection(t, busy),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            onPressed: busy ? null : _flashLocalBin,
            icon: const Icon(Icons.upload_file, size: 16),
            label: Builder(builder: (ctx) {
              final ble = ref.read(bleManagerProvider);
              final tag = [
                if (ble.role.isNotEmpty) ble.role,
                if (ble.board.isNotEmpty) ble.board,
              ].join('-');
              return Text(tag.isEmpty
                  ? 'Flash local .bin (DFU)'
                  : 'Flash local .bin ($tag)');
            }),
          ),
        ),
        if (_fleet.isNotEmpty)
          ..._buildFleetProgress(t)
        else if (stepper != null)
          OtaProgressStepper(model: stepper),
      ],
    );
  }

  List<Widget> _buildFleetProgress(ResolvedTheme t) {
    final done = _fleet.where((f) => f.status == _FleetStatus.done).length;
    final out = <Widget>[
      const Divider(height: 20),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            Icon(Icons.dns_outlined, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
            Text('FLEET UPDATE',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$done / ${_fleet.length}',
                style: TextStyle(
                    color: _fleetRunning ? AppTheme.accent : AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ];
    for (final f in _fleet) {
      if (f.status == _FleetStatus.active) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Icon(f.isManager ? Icons.router : Icons.sensors,
                  size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(f.label,
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ));
        if (f.isManager) {
          out.add(OtaProgressStepper(
            model: OtaStepperModel.fromBleProgress(
              _progress ?? const OtaProgress(phase: OtaPhase.uploading),
              reconnecting: _mgrReconnecting,
            ),
          ));
        } else {
          out.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    backgroundColor: t.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(f.detail,
                    style: TextStyle(color: t.textSecondary, fontSize: 11)),
              ],
            ),
          ));
        }
      } else {
        final Color c;
        final IconData icon;
        switch (f.status) {
          case _FleetStatus.done:
            c = AppTheme.success;
            icon = Icons.check_circle;
            break;
          case _FleetStatus.failed:
            c = AppTheme.error;
            icon = Icons.error;
            break;
          case _FleetStatus.queued:
          case _FleetStatus.active:
            c = t.textDim;
            icon = Icons.radio_button_unchecked;
            break;
        }
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text(f.label,
                    style: TextStyle(color: t.textPrimary, fontSize: 12)),
              ),
              Text(f.detail,
                  style: TextStyle(color: c, fontSize: 10)),
            ],
          ),
        ));
      }
    }
    return out;
  }
}

class _WifiStatusPanel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_WifiStatusPanel> createState() => _WifiStatusPanelState();
}

class _WifiStatusPanelState extends ConsumerState<_WifiStatusPanel> {
  bool _hasCreds = false;
  bool _connected = false;
  bool _enabled = false;
  String _ssid = '';
  String _ip = '';
  int _rssi = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await ref.read(bleManagerProvider).readWifiConfig();
      if (!mounted) return;
      setState(() {
        _hasCreds = r.hasCreds;
        _connected = r.connected;
        _enabled = r.enabled;
        _ssid = r.ssid;
        _ip = r.ip;
        _rssi = r.rssi;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _hasCreds = false;
        _connected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final Color color;
    final IconData icon;
    final String title;
    final String? subtitle;
    bool connecting = false;
    if (_connected) {
      color = AppTheme.success;
      icon = Icons.wifi;
      title = 'Connected: $_ssid';
      subtitle = '$_ip · ${_rssi}dBm';
    } else if (_enabled && _hasCreds) {
      color = AppTheme.accent;
      icon = Icons.wifi_find;
      connecting = true;
      title = 'Connecting to $_ssid…';
      subtitle = 'Joining network — up to 20s';
    } else if (_hasCreds) {
      color = AppTheme.warning;
      icon = Icons.wifi_off;
      title = 'Saved: $_ssid (STA off)';
      subtitle = 'Enable WiFi STA below to connect';
    } else {
      color = t.textDim;
      icon = Icons.signal_wifi_off;
      title = 'No WiFi credentials saved';
      subtitle = null;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          connecting
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiEnableToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_WifiEnableToggle> createState() => _WifiEnableToggleState();
}

class _WifiEnableToggleState extends ConsumerState<_WifiEnableToggle> {
  bool _enabled = false;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await ref.read(bleManagerProvider).readWifiConfig();
      if (!mounted) return;
      setState(() => _enabled = r.enabled);
    } on Exception {
    }
  }

  Future<void> _toggle(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(bleManagerProvider).setWifiStaEnabled(v);
      if (mounted) setState(() => _enabled = v);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toggle failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.power_settings_new,
              color: _enabled ? AppTheme.success : t.textDim, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WiFi STA',
                    style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  _enabled
                      ? 'Connects automatically using saved credentials'
                      : 'Off — node will not join WiFi until you enable it',
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: _busy ? null : _toggle,
            activeThumbColor: AppTheme.success,
          ),
        ],
      ),
    );
  }
}

class _PcapInlineSection extends ConsumerStatefulWidget {
  const _PcapInlineSection({this.onExpandedChanged});
  final ValueChanged<bool>? onExpandedChanged;
  @override
  ConsumerState<_PcapInlineSection> createState() => _PcapInlineSectionState();
}

class _PcapInlineSectionState extends ConsumerState<_PcapInlineSection> {
  static const String _expandedPrefKey = 'pcaps_panel_expanded';
  late Future<List<_PcapEntry>> _entries;
  final Set<String> _deleting = {};
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _entries = _load();
    _loadExpanded();
  }

  Future<void> _loadExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_expandedPrefKey);
    if (v != null && mounted && v != _expanded) {
      setState(() => _expanded = v);
      widget.onExpandedChanged?.call(_expanded);
    }
  }

  Future<void> _toggleExpanded() async {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedPrefKey, _expanded);
  }

  Future<Directory> _pcapDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory("${base.path}/pcaps");
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<_PcapEntry>> _load() async {
    final d = await _pcapDir();
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith(".pcap"))
        .cast<File>()
        .toList();
    final out = <_PcapEntry>[];
    for (final f in files) {
      final st = await f.stat();
      out.add(_PcapEntry(file: f, size: st.size, modified: st.modified));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  void _refresh() => setState(() => _entries = _load());

  bool _isActive(File f) {
    final ble = ref.read(bleManagerProvider);
    return ble.currentPcapFile?.path == f.path;
  }

  Future<bool> _doDelete(File f) async {
    if (_isActive(f)) {
      try { await ref.read(bleManagerProvider).abortActivePcap(); } catch (_) {}
    }
    try {
      if (await f.exists()) await f.delete();
      return true;
    } catch (_) { return false; }
  }

  Future<void> _delete(File f) async {
    setState(() => _deleting.add(f.path));
    final ok = await _doDelete(f);
    if (!mounted) return;
    setState(() => _deleting.remove(f.path));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      content: Text(ok ? "Deleted" : "Delete failed"),
    ));
    _refresh();
  }

  Future<void> _deleteAll() async {
    final list = await _entries;
    if (list.isEmpty) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete all captures?"),
        content: Text("${list.length} file(s) will be deleted."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text("DELETE ALL"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting.addAll(list.map((e) => e.file.path)));
    int failed = 0;
    for (final e in list) {
      if (!await _doDelete(e.file)) failed++;
    }
    if (!mounted) return;
    setState(() => _deleting.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 1),
      content: Text(failed == 0 ? "All deleted" : "$failed failed"),
    ));
    _refresh();
  }

  Future<void> _share(File f) async {
    if (!await f.exists()) return;
    final size = await f.length();
    if (!mounted) return;
    final s = MediaQuery.of(context).size;
    final origin = Rect.fromLTWH(s.width / 2 - 1, s.height / 2 - 1, 2, 2);
    await Share.shareXFiles(
      [XFile(f.path, mimeType: "application/vnd.tcpdump.pcap")],
      subject: "OUI-SPY PCAP ($size bytes)",
      sharePositionOrigin: origin,
    );
  }

  String _humanBytes(int n) {
    if (n < 1024) return "${n}B";
    if (n < 1024 * 1024) return "${(n / 1024).toStringAsFixed(1)}KB";
    if (n < 1024 * 1024 * 1024) return "${(n / 1024 / 1024).toStringAsFixed(2)}MB";
    return "${(n / 1024 / 1024 / 1024).toStringAsFixed(2)}GB";
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggleExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: [
                Icon(_expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18, color: t.textDim),
                const SizedBox(width: 4),
                Text("SAVED PCAPS",
                    style: TextStyle(color: t.textDim, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _expanded ? _refresh : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_sweep, size: 18, color: AppTheme.error),
                  tooltip: "Delete all",
                  onPressed: _expanded ? _deleteAll : null,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (_expanded) Expanded(
          child: FutureBuilder<List<_PcapEntry>>(
            future: _entries,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data ?? const <_PcapEntry>[];
              if (list.isEmpty) {
                return Center(
                  child: Text("No captures yet",
                      style: TextStyle(color: t.textDim, fontSize: 12)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: list.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: t.surface),
                itemBuilder: (context, i) {
                  final e = list[i];
                  final name = e.file.path.split("/").last;
                  final isBle = name.contains("_ble_");
                  final active = _isActive(e.file);
                  final deleting = _deleting.contains(e.file.path);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isBle ? Icons.bluetooth : Icons.wifi,
                      color: isBle ? AppTheme.flockBle : AppTheme.accent,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: TextStyle(color: t.textPrimary, fontSize: 11, fontFamily: "monospace")),
                        ),
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text("LIVE",
                                style: TextStyle(color: AppTheme.success, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      "${_humanBytes(e.size)}  ·  ${DateFormat("MM-dd HH:mm:ss").format(e.modified)}",
                      style: TextStyle(color: t.textDim, fontSize: 10),
                    ),
                    trailing: deleting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.ios_share, size: 18, color: t.textPrimary),
                                onPressed: () => _share(e.file),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                onPressed: () => _delete(e.file),
                              ),
                            ],
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PcapEntry {
  _PcapEntry({required this.file, required this.size, required this.modified});
  final File file;
  final int size;
  final DateTime modified;
}


(String, Color) _configAuthMeta(int mode) => switch (mode) {
      0 => ('OPEN', AppTheme.error),
      1 => ('WEP', AppTheme.warning),
      2 => ('WPA', AppTheme.warning),
      3 => ('WPA2', AppTheme.success),
      4 => ('WPA/2', AppTheme.success),
      5 => ('ENT', AppTheme.accent),
      6 => ('WPA3', AppTheme.success),
      _ => ('WPA2', AppTheme.success),
    };

class _ConfigAuthPill extends StatelessWidget {
  const _ConfigAuthPill({required this.authMode});
  final int authMode;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _configAuthMeta(authMode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(authMode == 0 ? Icons.lock_open : Icons.lock, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(
            color: color, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.5,
          )),
        ],
      ),
    );
  }
}

class _MeshModeTile extends StatelessWidget {
  const _MeshModeTile({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final color = selected ? AppTheme.success : t.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.success.withValues(alpha: 0.08)
                : t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppTheme.success.withValues(alpha: 0.5)
                  : t.border,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textDim,
                        fontSize: 11,
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
}

class _NodeRenameRow extends ConsumerStatefulWidget {
  const _NodeRenameRow({
    required this.sourceId,
    required this.detectionCount,
  });
  final String sourceId;
  final int detectionCount;

  @override
  ConsumerState<_NodeRenameRow> createState() => _NodeRenameRowState();
}

class _NodeRenameRowState extends ConsumerState<_NodeRenameRow> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    _ctrl = TextEditingController(
      text: appState.labelForNode(widget.sourceId),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final appState = ref.read(appStateProvider);
    appState.setNodeLabel(widget.sourceId, _ctrl.text.trim());
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final appState = ref.watch(appStateProvider);
    final display = appState.labelForNode(widget.sourceId);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, size: 14, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.sourceId,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: const UnderlineInputBorder(),
                    ),
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        display,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        widget.sourceId == display
                            ? '${widget.detectionCount} dets'
                            : '${widget.sourceId}  ·  ${widget.detectionCount} dets',
                        style: TextStyle(
                          color: t.textDim,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
          ),
          IconButton(
            icon: Icon(
              _editing ? Icons.check : Icons.edit,
              size: 16,
              color: _editing ? AppTheme.success : t.textDim,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              if (_editing) {
                _save();
              } else {
                setState(() => _editing = true);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  static const String appVersion = '0.4.7';

  @override
  Widget build(BuildContext context) {
    return ConfigInfoRow(
      icon: Icons.info_outline,
      label: 'Version',
      value: appVersion,
    );
  }
}
