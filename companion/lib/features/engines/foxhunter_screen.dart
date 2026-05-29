import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class FoxhunterScreen extends ConsumerStatefulWidget {
  const FoxhunterScreen({super.key});

  @override
  ConsumerState<FoxhunterScreen> createState() => _FoxhunterScreenState();
}

class _FoxhunterScreenState extends ConsumerState<FoxhunterScreen> {
  final _macController = TextEditingController();

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  int _channelForMac(String mac) {
    final state = ref.read(appStateProvider);
    final macLower = mac.toLowerCase();
    for (final d in state.recentDetections) {
      if (d.macAddress.toLowerCase() == macLower && d.channel > 0) {
        return d.channel;
      }
    }
    return 0;
  }

  void _setTarget() {
    final mac = _macController.text.trim();
    if (mac.length != 17) return;
    final channel = _channelForMac(mac);
    final st = ref.read(appStateProvider);
    final node = st.isManagerConnected ? st.foxhunterTargetNodeId : null;
    st.setFoxhunterTarget(mac, channel: channel, nodeId: node);
  }

  void _clearTarget() {
    ref.read(appStateProvider).clearFoxhunterTarget();
    _macController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final isActive = state.isEngineActive(Engine.foxhunter);
    final target = state.foxhunterTarget;
    final rssi = state.foxhunterRssi;
    final intervalMs = state.foxhunterIntervalMs;
    final channel = state.foxhunterChannel;
    final targetLost = isActive && intervalMs == 0;
    final normalized = ((rssi + 100) / 70).clamp(0.0, 1.0);
    final color = targetLost
        ? t.textDim
        : Color.lerp(AppTheme.error, AppTheme.success, normalized)!;

    if (target != null && _macController.text.isEmpty) {
      _macController.text = target;
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('FOXHUNTER'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isActive ? AppTheme.foxhunter : t.textDim).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (isActive ? AppTheme.foxhunter : t.textDim).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              isActive
                  ? (channel > 0 ? 'CH $channel' : 'SCANNING')
                  : 'OFF',
              style: TextStyle(
                color: isActive ? AppTheme.foxhunter : t.textDim,
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
              ),
            ),
          ),
          if (target != null)
            IconButton(
              icon: const Icon(Icons.clear, color: AppTheme.error),
              onPressed: _clearTarget,
              tooltip: 'Clear target',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (state.isManagerConnected) ...[
              _NodeTargetPicker(
                selected: state.foxhunterTargetNodeId,
                enabled: !isActive,
                onChanged: (v) =>
                    ref.read(appStateProvider).setFoxhunterTargetNode(v),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _macController,
                    style: TextStyle(color: t.textPrimary, fontFamily: 'monospace', fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'AA:BB:CC:DD:EE:FF',
                      labelText: 'Target MAC',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: (state.isManagerConnected &&
                          state.foxhunterTargetNodeId == null)
                      ? null
                      : _setTarget,
                  child: const Text('HUNT'),
                ),
              ],
            ),
            if (target != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.foxhunter : t.textDim,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Tracking: ${target.toUpperCase()}',
                    style: TextStyle(
                      color: isActive ? AppTheme.foxhunter : t.textDim,
                      fontSize: 11, fontFamily: 'monospace',
                    ),
                  ),
                  if (channel > 0) ...[
                    const SizedBox(width: 8),
                    Text('ch$channel',
                      style: TextStyle(
                        color: AppTheme.foxhunter.withValues(alpha: 0.6),
                        fontSize: 10, fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const Spacer(),
            SizedBox(
              width: 200, height: 200,
              child: CustomPaint(
                painter: _RssiGaugePainter(rssi: rssi, normalized: normalized, color: color),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$rssi', style: TextStyle(
                        color: color, fontSize: 48, fontWeight: FontWeight.w300, fontFamily: 'monospace',
                      )),
                      Text(targetLost ? 'LOST' : 'dBm', style: TextStyle(
                        color: color.withValues(alpha: 0.6), fontSize: 14,
                      )),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(targetLost ? 'TARGET LOST — scanning...' : 'Beep interval: ${intervalMs}ms',
                style: TextStyle(
                  color: targetLost ? AppTheme.error.withValues(alpha: 0.7) : t.textDim,
                  fontSize: 11, fontFamily: 'monospace',
                )),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _NodeTargetPicker extends ConsumerWidget {
  const _NodeTargetPicker({
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
          Text('HUNT FROM',
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

class _RssiGaugePainter extends CustomPainter {
  _RssiGaugePainter({required this.rssi, required this.normalized, required this.color});
  final int rssi;
  final double normalized;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final bgPaint = Paint()
      ..color = AppTheme.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        math.pi * 0.75, math.pi * 1.5, false, bgPaint);

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        math.pi * 0.75, math.pi * 1.5 * normalized, false, valuePaint);
  }

  @override
  bool shouldRepaint(covariant _RssiGaugePainter old) =>
      old.rssi != rssi || old.normalized != normalized;
}
