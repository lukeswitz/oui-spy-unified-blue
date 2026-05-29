import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class UnipwnScreen extends ConsumerStatefulWidget {
  const UnipwnScreen({super.key});

  @override
  ConsumerState<UnipwnScreen> createState() => _UnipwnScreenState();
}

class _UnipwnScreenState extends ConsumerState<UnipwnScreen> {
  final Map<String, Detection> _robots = {};
  String? _selectedTarget;
  String? _selectedNode;
  final _customCmdController = TextEditingController();
  StreamSubscription<Detection>? _sub;

  @override
  void initState() {
    super.initState();
    final ble = ref.read(bleManagerProvider);
    _sub = ble.detections.listen((d) {
      if (d.engine != Engine.uniPwn || !mounted) return;
      setState(() => _robots[d.macAddress] = d);
    });
  }

  void _toggleEngine(bool enable) {
    final ble = ref.read(bleManagerProvider);
    final st = ref.read(appStateProvider);
    final node = st.isManagerConnected ? _selectedNode : null;
    if (enable) {
      if (st.isManagerConnected && node == null) return;
      ble.enableEngine(Engine.uniPwn, targetNodeId: node);
    } else {
      ble.disableEngine(Engine.uniPwn, targetNodeId: node);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _customCmdController.dispose();
    super.dispose();
  }

  void _sendCommand(int type, {String payload = ''}) {
    if (_selectedTarget == null) return;
    final ble = ref.read(bleManagerProvider);
    ble.sendUnipwnCommand(
      targetMac: _selectedTarget!,
      commandType: type,
      payload: payload,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final isActive = state.isEngineActive(Engine.uniPwn);
    final robots = _robots.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('UNIPWN'),
        actions: [
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: isActive,
              onChanged: _toggleEngine,
              activeTrackColor: AppTheme.uniPwn.withValues(alpha: 0.3),
              activeColor: AppTheme.uniPwn,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isManagerConnected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _UnipwnNodePicker(
                selected: _selectedNode,
                enabled: !isActive,
                onChanged: (v) => setState(() => _selectedNode = v),
              ),
            ),
          SizedBox(
            height: 160,
            child: robots.isEmpty
                ? Center(
                    child: Text(
                      isActive ? 'SCANNING FOR UNITREE ROBOTS...' : 'ENABLE TO START SCANNING',
                      style: TextStyle(color: t.textDim, letterSpacing: 1, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    itemCount: robots.length,
                    itemBuilder: (context, index) {
                      final r = robots[index];
                      final selected = _selectedTarget == r.macAddress;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTarget = r.macAddress),
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.uniPwn.withValues(alpha: 0.1)
                                : t.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? AppTheme.uniPwn
                                  : t.border,
                              width: selected ? 1.5 : 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.smart_toy,
                                  color: selected ? AppTheme.uniPwn : t.textDim,
                                  size: 24),
                              const Spacer(),
                              Text(
                                r.unipwn?.robotType ?? '?',
                                style: TextStyle(
                                  color: selected ? AppTheme.uniPwn : t.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                r.macAddress.substring(0, 8),
                                style: TextStyle(
                                  color: t.textDim, fontSize: 10, fontFamily: 'monospace',
                                ),
                              ),
                              Text(
                                '${r.rssi} dBm',
                                style: TextStyle(
                                  color: t.textDim, fontSize: 10, fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          // Exploit controls
          Expanded(
            child: _selectedTarget == null
                ? Center(
                    child: Text(
                      'SELECT A TARGET',
                      style: TextStyle(color: t.textDim, letterSpacing: 2, fontSize: 12),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'TARGET: ${_selectedTarget!.toUpperCase()}',
                        style: const TextStyle(
                          color: AppTheme.uniPwn,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ExploitButton(
                        label: 'ENABLE SSH',
                        icon: Icons.terminal,
                        onTap: () => _sendCommand(0),
                      ),
                      _ExploitButton(
                        label: 'CHANGE ROOT PASSWORD',
                        icon: Icons.key,
                        onTap: () => _sendCommand(1),
                      ),
                      _ExploitButton(
                        label: 'GET SERIAL NUMBER',
                        icon: Icons.numbers,
                        onTap: () => _sendCommand(2),
                      ),
                      _ExploitButton(
                        label: 'GET SYSTEM INFO',
                        icon: Icons.info_outline,
                        onTap: () => _sendCommand(4),
                      ),
                      _ExploitButton(
                        label: 'REBOOT',
                        icon: Icons.restart_alt,
                        color: AppTheme.warning,
                        onTap: () => _sendCommand(3),
                      ),
                      const SizedBox(height: 16),
                      // Custom command
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customCmdController,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Custom shell command',
                                labelText: 'CUSTOM CMD',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _sendCommand(5, payload: _customCmdController.text),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.error,
                            ),
                            child: const Text('EXEC'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _UnipwnNodePicker extends ConsumerWidget {
  const _UnipwnNodePicker({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final t = AppTheme.of(context);
    final nodes = appState.liveKnownNodes.toList()..sort();
    if (nodes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('No mesh nodes seen yet.',
            style: TextStyle(color: t.textDim, fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, color: t.textDim, size: 18),
          const SizedBox(width: 8),
          Text('EXEC NODE',
              style: TextStyle(color: t.textDim, fontSize: 11, letterSpacing: 1.5)),
          const Spacer(),
          DropdownButton<String>(
            value: nodes.contains(selected) ? selected : null,
            hint: const Text('— Pick Node —'),
            underline: const SizedBox.shrink(),
            onChanged: enabled ? onChanged : null,
            items: nodes.map((id) {
              final label = appState.labelForNode(id);
              return DropdownMenuItem(
                value: id,
                child: Text(label == id ? id : '$label ($id)'),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ExploitButton extends StatelessWidget {
  const _ExploitButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = AppTheme.uniPwn,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(letterSpacing: 1, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
