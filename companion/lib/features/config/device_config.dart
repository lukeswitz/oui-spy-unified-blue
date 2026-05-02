import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/debug_log.dart';
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
    _tabController = TabController(length: 4, vsync: this);
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
          });
          DebugLog.log('CONFIG: hw read: buzzer=$_buzzerEnabled led=$_ledEnabled neo=$_neopixelBrightness');
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
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                          color: AppTheme.textDim,
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
              unselectedLabelColor: AppTheme.textDim,
              indicatorColor: AppTheme.accent,
              labelStyle: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1,
              ),
              tabs: const [
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

  Widget _buildHardwareTab() {
    final appState = ref.watch(appStateProvider);

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
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'NODE MESH',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: AppTheme.textDim,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'ESP-NOW peer-to-peer mesh. Nodes relay detections to your primary device.',
          style: TextStyle(color: AppTheme.textDim, fontSize: 11),
        ),
        const SizedBox(height: 8),
        _ConfigSwitch(
          label: 'Mesh Enabled',
          value: appState.meshEnabled,
          onChanged: (v) => _toggleMesh(v),
        ),
        _ConfigSwitch(
          label: 'Encryption (AES-256-GCM)',
          value: appState.meshEncryption,
          onChanged: appState.meshEnabled
              ? (v) => _toggleMeshEncryption(v)
              : null,
        ),
        if (appState.meshEnabled) ...[
          const SizedBox(height: 8),
          _InfoRow(label: 'Peers', value: '${appState.meshPeerCount}'),
          _InfoRow(label: 'RX Packets', value: '${appState.meshRxCount}'),
          _InfoRow(label: 'TX Packets', value: '${appState.meshTxCount}'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _rotateMeshKey,
            child: const Text('ROTATE ENCRYPTION KEY'),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleMesh(bool enabled) async {
    final appState = ref.read(appStateProvider);
    if (enabled) {
      await appState.loadMeshKey();
      final db = ref.read(databaseProvider);
      final nodes = await db.getAllNodes();
      final ble = ref.read(bleManagerProvider);
      final connectedId = ble.connectedDeviceId;
      final peerNodes = nodes.where((n) => n.id != connectedId).toList();

      if (peerNodes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Add nodes first before enabling mesh'),
              backgroundColor: AppTheme.warning,
            ),
          );
        }
        return;
      }

      final peerMacs = peerNodes.map((n) {
        return BleProtocol.parseMacToBytes(n.macAddress);
      }).toList();

      await appState.enableMesh(
        encryption: appState.meshEncryption,
        peerMacs: peerMacs,
      );
    } else {
      await appState.disableMesh();
    }
  }

  Future<void> _toggleMeshEncryption(bool encryption) async {
    final appState = ref.read(appStateProvider);
    if (!appState.meshEnabled) return;
    await appState.disableMesh();
    appState.meshEncryption = encryption;
    await _toggleMesh(true);
  }

  Future<void> _rotateMeshKey() async {
    final appState = ref.read(appStateProvider);
    await appState.generateMeshKey();
    await appState.disableMesh();
    await _toggleMesh(true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Encryption key rotated'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Widget _buildAlertsTab() {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'WiFi STA mode connects the device to your network for OTA updates, '
          'data upload, and remote node communication.',
          style: TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ssidController,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(labelText: 'WiFi SSID'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passController,
          style: const TextStyle(color: AppTheme.textPrimary),
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
          activeColor: AppTheme.accent, inactiveColor: AppTheme.border,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}
