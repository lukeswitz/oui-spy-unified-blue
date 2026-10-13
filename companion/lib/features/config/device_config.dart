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
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/features/feed/detection_row.dart' show showDetectionDetails;
import 'package:oui_spy/core/models/detection.dart' show FlockExtension, FlockConfidence, FlockConfidenceX, FlockExtensionSignals;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/detector_signatures.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/core/export/detections_csv.dart' show DetectionsCsv;
import 'package:oui_spy/core/export/wigle_csv_import.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/features/config/config_menu_state.dart';
import 'package:oui_spy/features/config/widgets/config_nav.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/features/config/ota_progress_stepper.dart';
import 'package:oui_spy/features/config/alert_sounds_screen.dart';
import 'package:oui_spy/features/engines/detection_rules.dart';
import 'package:oui_spy/features/pcap/pcap_library_screen.dart';
import 'package:oui_spy/features/notifications/notification_settings_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/wigle/wigle_api.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_api.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_provider.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/map_tiles.dart';

part 'config_wardrive_settings.dart';
part 'config_wardrive_tab.dart';
part 'config_ignore_tab.dart';
part 'config_detection_settings.dart';
part 'config_detections_tab.dart';
part 'config_ota.dart';
part 'config_misc.dart';

String boardDisplayName(String? board) => switch (board) {
      'xiao_s3' => 'XIAO ESP32-S3',
      's3_devkitc' => 'ESP32-S3 DevKitC',
      'xiao_c5' => 'XIAO ESP32-C5 (2.4+5GHz)',
      'tdongle_s3' => 'LilyGO T-Dongle-S3',
      'tdongle_c5' => 'LilyGO T-Dongle-C5 (2.4+5GHz)',
      'stickc' => 'M5StickC',
      'stickc_plus' => 'M5StickC PLUS',
      'stickc_plus2' => 'M5StickC PLUS2',
      'xiao_c3' => 'XIAO ESP32-C3',
      'wroom' => 'ESP32 WROOM',
      null || '' => '—',
      final b => b,
    };

class DeviceConfigScreen extends ConsumerStatefulWidget {
  const DeviceConfigScreen({super.key});

  @override
  ConsumerState<DeviceConfigScreen> createState() => _DeviceConfigScreenState();
}

class _DeviceConfigScreenState extends ConsumerState<DeviceConfigScreen> {
  bool _flockExtendedOui = false;
  bool _flockAllowOuiOnly = false;
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
  StreamSubscription<HwGpsState>? _hwGpsSub;
  HwGpsState _hwGps = const HwGpsState(
      active: false, satellites: 0, source: GpsSource.phone, inUse: false);

  late final StateController<bool> _menuWanted;
  int? _open;
  int? _sub;

  @override
  void initState() {
    super.initState();
    _menuWanted = ref.read(configMenuWantedProvider.notifier);
    final prefs = ref.read(sharedPreferencesProvider);
    final requested = kConfigSections.indexWhere((s) => s.label == ref.read(configSectionRequestProvider));
    if (requested >= 0) {
      _open = requested;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(configSectionRequestProvider.notifier).state = null);
    }
    _offlineGpsTag = prefs.getBool('offlineGpsTagEnabled') ?? false;
    _neopixelBrightness = prefs.getInt('neopixelBrightness') ?? _neopixelBrightness;
    _readDeviceConfig();
    final ble = ref.read(bleManagerProvider);
    _connStateSub = ble.connectionState.listen((s) {
      if (s == NodeConnectionState.ready) {
        DebugLog.log('CONFIG: reconnect detected, re-reading device info');
        _readDeviceConfig();
      }
    });
    final gps = ref.read(gpsProvider);
    _hwGps = gps.hwGps;
    _hwGpsSub = gps.hwGpsStream.listen((s) {
      if (mounted) setState(() => _hwGps = s);
    });
    gps.refreshHwGps();
  }

  @override
  void dispose() {
    final menuWanted = _menuWanted;
    Future.microtask(() => menuWanted.state = false);
    _connStateSub?.cancel();
    _hwGpsSub?.cancel();
    _ssidController.dispose();
    _passController.dispose();
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
        if (!mounted) return;
        if (hw.length >= 3) {
          setState(() {
            _buzzerEnabled = hw[0] != 0;
            _ledEnabled = hw[1] != 0;
            _neopixelBrightness = hw[2];
            ref.read(sharedPreferencesProvider)
                .setInt('neopixelBrightness', hw[2]);
            _buzzerVolume = hw.length >= 4 ? hw[3] : 100;
            _flockExtendedOui = hw.length >= 5 && hw[4] != 0;
            _flockAllowOuiOnly = hw.length >= 7 && hw[6] != 0;
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
        if (!mounted) return;
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
        if (!mounted) return;
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

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    ref.listen<bool>(configMenuWantedProvider, (_, wanted) {
      if (!wanted) return;
      _menuWanted.state = false;
      if (_open != null) setState(() => _open = _sub = null);
    });
    final open = _open;
    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _open != null) _back();
      },
      child: Scaffold(
        backgroundColor: t.background,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            bottom: false,
            child: open == null ? _overview(t) : _sectionPage(t, open),
          ),
        ),
      ),
    );
  }

  static const _sectionTitles = ['App', 'Scanning', 'Detection', 'Alerts', 'Node', 'Data', 'About'];
  static const _aboutIndex = 6;

  String _sectionSummary(int i) {
    final ble = ref.read(bleManagerProvider);
    return switch (i) {
      0 => 'Appearance, units, auto-connect',
      1 => 'Re-log thresholds, scan timing, channels',
      2 => 'What to watch for, watchlist, ignore list',
      3 => 'Foxhunt, milestones, limits, sound',
      4 => ble.isConnected ? '$_nodeId · fw $_fwVersion' : 'Not connected',
      _ => 'Accounts, captures, export',
    };
  }

  Widget _overview(ResolvedTheme t) => LayoutBuilder(builder: (context, box) {
        const rows = 7;
        const chrome = 8 + 8 + 34 + 16 + 24 + 16;
        final rowH = ((box.maxHeight - chrome) / rows).clamp(64.0, 120.0);
        Widget sized(Widget row) => ConstrainedBox(
              constraints: BoxConstraints(minHeight: rowH),
              child: row,
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
              child: Text('Settings',
                  style: TextStyle(color: t.textPrimary, fontSize: 28, fontWeight: FontWeight.w700)),
            ),
            for (var i = 0; i < kConfigSections.length; i++)
              sized(ConfigActionRow(
                icon: kConfigSections[i].icon,
                label: _sectionTitles[i],
                subtitle: _sectionSummary(i),
                color: AppTheme.accent,
                prominent: true,
                onTap: () => setState(() {
                  _open = i;
                  _sub = null;
                }),
              )),
            const SizedBox(height: 16),
            sized(ConfigActionRow(
              icon: Icons.info_outline,
              label: 'About',
              subtitle: 'Version, source code',
              color: t.textDim,
              prominent: true,
              onTap: () => setState(() {
                _open = _aboutIndex;
                _sub = null;
              }),
            )),
          ],
        );
      });

  List<(String, String, IconData, Widget Function())>? _subPages(int i) => switch (i) {
        4 => [
            ('Hardware', 'Sound, lights, GPS source, Flock detection, offline scan', Icons.memory, _buildHardwareTab),
            ('Mesh', 'Mode, status, key, nodes', Icons.hub, _buildMeshTab),
            ('Firmware', 'Device info, Wi-Fi network, updates', Icons.system_update, _buildFirmwareTab),
          ],
        5 => [
            ('Accounts', 'WiGLE and WDGWars, your capture database', Icons.cloud_upload, () => const _WardriveConfigTab()),
            ('Captures', 'Saved PCAP files', Icons.folder_open, () => const PcapLibraryScreen(embedded: true)),
            ('Export', 'Data and backup, OUI database', Icons.ios_share, _buildExportTab),
          ],
        _ => null,
      };

  void _back() => setState(() => _sub != null ? _sub = null : _open = null);

  Widget _sectionPage(ResolvedTheme t, int i) {
    final subs = _subPages(i);
    final sub = _sub;
    final title = subs != null && sub != null ? subs[sub].$1 : _sectionTitles[i];
    final Widget body = switch (i) {
      0 => _buildAppTab(),
      1 => _buildScanTab(),
      2 => const _DetectionSettingsTab(),
      3 => _buildAlertsTab(),
      _aboutIndex => _buildAboutTab(),
      _ when sub != null => subs![sub].$4(),
      _ => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (i == 4 && !ref.read(bleManagerProvider).isConnected)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('Connect an OUI-SPY board to change its settings.',
                    style: TextStyle(color: t.textDim, fontSize: 12)),
              ),
            for (var s = 0; s < subs!.length; s++)
              ConfigActionRow(
                icon: subs[s].$3,
                label: subs[s].$1,
                subtitle: subs[s].$2,
                color: AppTheme.accent,
                onTap: () => setState(() => _sub = s),
              ),
          ],
        ),
    };
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: t.textPrimary),
                tooltip: sub != null ? _sectionTitles[i] : 'Settings',
                onPressed: _back,
              ),
              Expanded(
                child: Text(title,
                    style: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              if (_loading && i == 4)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildAppTab() {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final unitSystem = ref.watch(unitSystemProvider);
    final isImperial = unitSystem == UnitSystem.imperial;
    final use24Hour = ref.watch(use24HourTimeProvider);

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
        ConfigToggleRow(
          icon: Icons.schedule,
          label: '24-Hour Time',
          subtitle: use24Hour ? 'Times shown as 20:13' : 'Times shown as 8:13 PM',
          color: AppTheme.accent,
          value: use24Hour,
          onChanged: (v) => ref.read(use24HourTimeProvider.notifier).set(v),
        ),

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'CONNECTION'),
        const _AutoConnectToggle(),
      ],
    );
  }

  Widget _buildAboutTab() {
    final t = AppTheme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
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

  Widget _buildScanTab() {
    final t = AppTheme.of(context);
    final isC5 = ref.watch(bleManagerProvider).isC5;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
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

        if (isC5) ...[
          const SizedBox(height: 16),
          const ConfigSectionHeader(label: 'WIFI BAND'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              '5GHz sweeps UNII-1 + UNII-3; applies to all WiFi engines.',
              style: TextStyle(color: t.textDim, fontSize: 11),
            ),
          ),
          const _WifiBandSelector(),
        ],

        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'CHANNEL RANGE'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            '2.4GHz channels to scan. Narrower range = faster per-channel coverage.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const _ChannelRangeSlider(),
      ],
    );
  }

  Widget _buildExportTab() {
    final t = AppTheme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ConfigSectionHeader(label: 'DATA & BACKUP'),
        ConfigActionRow(
          icon: Icons.import_export,
          label: 'Export & Database Backup',
          subtitle: 'WiGLE/JSON/KML export, full DB backup & restore',
          onTap: () => context.push('/export'),
          trailing: Icon(Icons.chevron_right, size: 18, color: t.textDim),
        ),
        const SizedBox(height: 16),
        const ConfigSectionHeader(label: 'OUI DATABASE'),
        const _OuiDatabaseSection(),
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

  Widget _gpsSourceRow(
      GpsSource source, IconData icon, String label, String subtitle) {
    final selected = _hwGps.source == source;
    return ConfigActionRow(
      icon: icon,
      label: label,
      subtitle: subtitle,
      color: selected ? const Color(0xFF4AB8FF) : null,
      onTap: () => ref.read(gpsProvider).setSource(source),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        size: 18,
        color: selected ? const Color(0xFF4AB8FF) : AppTheme.textDim,
      ),
    );
  }

  Widget _buildHardwareTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    final hasBuzzer = !const {'tdongle_s3', 'tdongle_c5', 'stickc'}
        .contains(ref.read(bleManagerProvider).board);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (hasBuzzer) const ConfigSectionHeader(label: 'AUDIO'),
        if (hasBuzzer) ConfigToggleRow(
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
        if (hasBuzzer && _buzzerEnabled)
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
        if (hasBuzzer && _buzzerEnabled)
          ConfigActionRow(
            icon: Icons.music_note,
            label: 'Alert sounds',
            subtitle: 'Compose melodies and assign them to detections',
            color: const Color(0xFFFFB84A),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AlertSoundsScreen(),
            )),
          ),

        if (hasBuzzer) const SizedBox(height: 16),
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
        const ConfigSectionHeader(label: 'GPS SOURCE'),
        ConfigInfoRow(
          icon: _hwGps.active ? Icons.satellite_alt : Icons.satellite_alt_outlined,
          label: 'On-board GPS module',
          value: _hwGps.active ? 'FIX · ${_hwGps.satellites} sats' : 'NO FIX',
          color: _hwGps.active ? const Color(0xFF4AFF8A) : const Color(0xFFFF6B6B),
        ),
        ConfigInfoRow(
          icon: Icons.edit_location_alt,
          label: 'Recording positions from',
          value: _hwGps.inUse
              ? 'HARDWARE'
              : (_hwGps.fallback ? 'PHONE (FALLBACK)' : 'PHONE'),
          color: _hwGps.fallback
              ? const Color(0xFFFFB84A)
              : const Color(0xFF4AB8FF),
        ),
        _gpsSourceRow(
          GpsSource.phone,
          Icons.smartphone,
          'Phone (default)',
          'Record the phone location. The device is never polled for GPS.',
        ),
        _gpsSourceRow(
          GpsSource.hardware,
          Icons.memory,
          'On-board GPS module',
          'Record from the module, falling back to the phone whenever it has no fix.',
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
        ConfigToggleRow(
          icon: Icons.fingerprint,
          label: 'Report OUI-only WiFi hits',
          subtitle: 'Report a WiFi device on a Flock OUI match alone, without a probe or other corroborating signal. More hits, more false positives.',
          color: const Color(0xFFFF6B6B),
          value: _flockAllowOuiOnly,
          onChanged: (v) {
            setState(() => _flockAllowOuiOnly = v);
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
        if (appState.nodeBoard(id) != null) boardDisplayName(appState.nodeBoard(id)),
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
    for (final id in liveIds) {
      widgets.add(row(id, online: true));
    }
    if (offlineIds.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(const ConfigSectionHeader(label: 'OFFLINE'));
      for (final id in offlineIds) {
        widgets.add(row(id, online: false));
      }
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
          icon: Icons.developer_board,
          label: 'Board',
          value: boardDisplayName(ref.read(bleManagerProvider).board),
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

  Future<void> _writeHardwareConfig() async {
    try {
      await ref.read(bleManagerProvider).writeHardwareConfig(
            buzzer: _buzzerEnabled,
            led: _ledEnabled,
            neopixelBrightness: _neopixelBrightness,
            buzzerVolume: _buzzerVolume,
            extendedOui: _flockExtendedOui,
            allowOuiOnly: _flockAllowOuiOnly,
            offlineScan: _offlineScanEnabled,
          );
      ref.read(sharedPreferencesProvider)
          .setBool('offlineScanEnabled', _offlineScanEnabled);
      ref.read(sharedPreferencesProvider)
          .setInt('neopixelBrightness', _neopixelBrightness);
    } catch (e) {
      DebugLog.log('CONFIG: writeHardwareConfig failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Hardware config write failed — resyncing: $e')),
      );
      _readDeviceConfig();
    }
  }

  Future<void> _writeAlertConfig() async {
    try {
      await ref.read(bleManagerProvider).writeAlertConfig(
            cooldownMs: _cooldownMs,
            heartbeatMs: _heartbeatMs,
            rediscoverMs: _rediscoverMs,
            hbActiveMs: _hbActiveMs,
          );
    } catch (e) {
      DebugLog.log('CONFIG: writeAlertConfig failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Alert config write failed — resyncing: $e')),
      );
      _readDeviceConfig();
    }
  }
}

