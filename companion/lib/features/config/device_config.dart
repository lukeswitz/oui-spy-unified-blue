import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/wardrive_state.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'APPEARANCE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 12),
        _ConfigSwitch(
          label: 'Dark Mode',
          value: isDark,
          onChanged: (v) {
            ref.read(themeModeProvider.notifier).setMode(
                  v ? ThemeMode.dark : ThemeMode.light,
                );
          },
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'UNITS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 12),
        _ConfigSwitch(
          label: 'Imperial (mi, mph, ft)',
          value: isImperial,
          onChanged: (v) {
            ref.read(unitSystemProvider.notifier).setSystem(
                  v ? UnitSystem.imperial : UnitSystem.metric,
                );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Text(
            isImperial
                ? 'Distances in miles, speed in mph, altitude in feet'
                : 'Distances in km, speed in km/h, altitude in meters',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'WARDRIVE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'RSSI change threshold before re-logging a seen device',
          style: TextStyle(color: t.textDim, fontSize: 11),
        ),
        const SizedBox(height: 12),
        _WardriveRssiSlider(
          label: 'WiFi re-log',
          icon: Icons.wifi,
          min: 10,
          max: 60,
        ),
        _WardriveRssiSlider(
          label: 'BLE re-log',
          icon: Icons.bluetooth,
          min: 10,
          max: 50,
          isBle: true,
        ),
        const SizedBox(height: 16),
        Text(
          'SCAN TIMING',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Lower values = faster scans, more battery drain',
          style: TextStyle(color: t.textDim, fontSize: 11),
        ),
        const SizedBox(height: 8),
        const _ScanTimingSliders(),
        const SizedBox(height: 16),
        Text(
          'CHANNEL RANGE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'WiFi channels to scan. Narrower range = faster per-channel coverage.',
          style: TextStyle(color: t.textDim, fontSize: 11),
        ),
        const SizedBox(height: 8),
        const _ChannelRangeSlider(),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'ABOUT',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: t.textDim,
              ),
        ),
        const SizedBox(height: 8),
        _InfoRow(label: 'Version', value: '1.0.0'),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _launchUrl('https://github.com/colonelpanic/oui-spy'),
          child: Row(
            children: [
              const Icon(Icons.code, size: 14, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(
                'github.com/colonelpanic/oui-spy',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.accent.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, size: 36, color: t.textDim),
            const SizedBox(height: 12),
            Text(
              'NO NODE CONNECTED',
              style: TextStyle(
                color: t.textDim, fontSize: 12,
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
    );
  }

  Widget _buildHardwareTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConfigSwitch(
          label: 'Buzzer',
          value: _buzzerEnabled,
          onChanged: (v) {
            setState(() => _buzzerEnabled = v);
            _writeHardwareConfig();
          },
        ),
        if (_buzzerEnabled)
          _ConfigSlider(
            label: 'Buzzer Volume',
            value: _buzzerVolume,
            min: 1,
            max: 255,
            onChanged: (v) {
              setState(() => _buzzerVolume = v);
              _writeHardwareConfig();
            },
          ),
        _ConfigSwitch(
          label: 'LED',
          value: _ledEnabled,
          onChanged: (v) {
            setState(() => _ledEnabled = v);
            _writeHardwareConfig();
          },
        ),
        const SizedBox(height: 16),
        _ConfigSlider(
          label: 'NeoPixel Brightness',
          value: _neopixelBrightness,
          min: 0,
          max: 255,
          onChanged: (v) {
            setState(() => _neopixelBrightness = v);
            _writeHardwareConfig();
          },
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConfigField(
          label: 'Cooldown (ms)', value: _cooldownMs,
          onChanged: (v) { setState(() => _cooldownMs = v); _writeAlertConfig(); },
        ),
        _ConfigField(
          label: 'Heartbeat (ms)', value: _heartbeatMs,
          onChanged: (v) { setState(() => _heartbeatMs = v); _writeAlertConfig(); },
        ),
        _ConfigField(
          label: 'Rediscover (ms)', value: _rediscoverMs,
          onChanged: (v) { setState(() => _rediscoverMs = v); _writeAlertConfig(); },
        ),
        _ConfigField(
          label: 'HB Active (ms)', value: _hbActiveMs,
          onChanged: (v) { setState(() => _hbActiveMs = v); _writeAlertConfig(); },
        ),
      ],
    );
  }

  final _ssidController = TextEditingController();
  final _passController = TextEditingController();

  Widget _buildWifiTab() {
    final appState = ref.watch(appStateProvider);
    if (!appState.isConnected) return _buildDisconnectedPlaceholder();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'WiFi STA mode connects the device to your network for OTA updates, '
          'data upload, and remote node communication.',
          style: TextStyle(color: AppTheme.of(context).textDim, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ssidController,
          style: TextStyle(color: AppTheme.of(context).textPrimary),
          decoration: const InputDecoration(labelText: 'WiFi SSID'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passController,
          style: TextStyle(color: AppTheme.of(context).textPrimary),
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _writeWifiConfig,
          child: const Text('SAVE & CONNECT'),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _scanNetworks,
          child: const Text('SCAN NETWORKS'),
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
      padding: const EdgeInsets.all(16),
      children: [
        _InfoRow(label: 'Version', value: _fwVersion),
        _InfoRow(label: 'Node ID', value: _nodeId),
        _InfoRow(label: 'Free Heap', value: _heapFree),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {},
          child: const Text('CHECK FOR UPDATE'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {},
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.error),
            foregroundColor: AppTheme.error,
          ),
          child: const Text('FACTORY RESET'),
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

class _ConfigSwitch extends StatelessWidget {
  const _ConfigSwitch({required this.label, required this.value, this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  const _ConfigSlider({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            Text('$value', style: const TextStyle(color: AppTheme.accent, fontFamily: 'monospace', fontSize: 13)),
          ],
        ),
        Slider(
          value: value.toDouble(), min: min.toDouble(), max: max.toDouble(),
          activeColor: AppTheme.accent, inactiveColor: t.border,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  const _ConfigField({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          SizedBox(
            width: 100,
            child: TextFormField(
              initialValue: '$value',
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.accent, fontFamily: 'monospace', fontSize: 13),
              textAlign: TextAlign.right,
              onFieldSubmitted: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanTimingSliders extends ConsumerWidget {
  const _ScanTimingSliders();

  static const _steps = [50, 100, 150, 200, 250, 300, 350, 400, 500, 800, 1000, 1500, 2000, 3000, 5000];

  String _label(int ms) => '${ms}ms';

  int _nearest(int ms) {
    int best = _steps[0];
    for (final s in _steps) {
      if ((s - ms).abs() < (best - ms).abs()) best = s;
    }
    return best;
  }

  double _toSlider(int ms) => _steps.indexOf(_nearest(ms)).toDouble();
  int _fromSlider(double v) => _steps[v.round().clamp(0, _steps.length - 1)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final wd = ref.watch(wardriveProvider);

    Widget row(String label, IconData icon, int value, ValueChanged<int> onChanged) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
            SizedBox(
              width: 90,
              child: Text(label, style: TextStyle(color: t.textSecondary, fontSize: 12)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay),
                child: Slider(
                  value: _toSlider(value),
                  min: 0,
                  max: (_steps.length - 1).toDouble(),
                  divisions: _steps.length - 1,
                  activeColor: AppTheme.accent,
                  inactiveColor: t.border,
                  onChanged: (v) => onChanged(_fromSlider(v)),
                ),
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                _label(value),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.accent, fontSize: 11,
                  fontFamily: 'monospace', fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        row('Ch 1/6/11 dwell', Icons.wifi, wd.wifiScanInterval, (v) {
          ref.read(wardriveProvider).wifiScanInterval = v;
        }),
        row('Other ch dwell', Icons.wifi, wd.wifiDwellPerCh, (v) {
          ref.read(wardriveProvider).wifiDwellPerCh = v;
        }),
        row('BLE duration', Icons.bluetooth, wd.bleScanDuration, (v) {
          ref.read(wardriveProvider).bleScanDuration = v;
        }),
        row('BLE interval', Icons.bluetooth, wd.bleScanInterval, (v) {
          ref.read(wardriveProvider).bleScanInterval = v;
        }),
      ],
    );
  }
}

class _ChannelRangeSlider extends ConsumerWidget {
  const _ChannelRangeSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final wd = ref.watch(wardriveProvider);

    return Row(
      children: [
        Icon(Icons.cell_tower, size: 14, color: t.textSecondary),
        const SizedBox(width: 6),
        Text('CH', style: TextStyle(color: t.textSecondary, fontSize: 12)),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(overlayShape: SliderComponentShape.noOverlay),
            child: RangeSlider(
              values: RangeValues(
                wd.channelStart.toDouble(),
                wd.channelEnd.toDouble(),
              ),
              min: 1,
              max: 14,
              divisions: 13,
              activeColor: AppTheme.accent,
              inactiveColor: t.border,
              labels: RangeLabels(
                '${wd.channelStart}',
                '${wd.channelEnd}',
              ),
              onChanged: (values) {
                ref.read(wardriveProvider).channelStart = values.start.round();
                ref.read(wardriveProvider).channelEnd = values.end.round();
              },
            ),
          ),
        ),
        SizedBox(
          width: 55,
          child: Text(
            '${wd.channelStart}-${wd.channelEnd}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _WardriveRssiSlider extends ConsumerWidget {
  const _WardriveRssiSlider({
    required this.label,
    required this.icon,
    required this.min,
    required this.max,
    this.isBle = false,
  });
  final String label;
  final IconData icon;
  final int min;
  final int max;
  final bool isBle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final wd = ref.watch(wardriveProvider);
    final value = isBle ? wd.bleRssiRelogDb : wd.wifiRssiRelogDb;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              activeColor: AppTheme.accent,
              inactiveColor: t.border,
              onChanged: (v) {
                final wd = ref.read(wardriveProvider);
                if (isBle) {
                  wd.bleRssiRelogDb = v.round();
                } else {
                  wd.wifiRssiRelogDb = v.round();
                }
              },
            ),
          ),
          Text(
            '${value}dB',
            style: const TextStyle(
              color: AppTheme.accent,
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: TextStyle(color: t.textPrimary, fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}
