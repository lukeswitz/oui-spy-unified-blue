import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class FoxhunterScreen extends ConsumerStatefulWidget {
  const FoxhunterScreen({super.key});

  @override
  ConsumerState<FoxhunterScreen> createState() => _FoxhunterScreenState();
}

class _FoxhunterScreenState extends ConsumerState<FoxhunterScreen> {
  final _macController = TextEditingController();
  String? _activeTarget;

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  void _setTarget() {
    final mac = _macController.text.trim();
    if (mac.length != 17) return;
    final ble = ref.read(bleManagerProvider);
    ble.enableEngine(Engine.foxhunter);
    ble.setFoxhunterTarget(mac);
    setState(() => _activeTarget = mac);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final rssi = state.foxhunterRssi;
    final intervalMs = state.foxhunterIntervalMs;
    final normalized = ((rssi + 100) / 70).clamp(0.0, 1.0);
    final color = Color.lerp(AppTheme.error, AppTheme.success, normalized)!;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('FOXHUNTER')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _macController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 14),
                    decoration: const InputDecoration(hintText: 'AA:BB:CC:DD:EE:FF', labelText: 'Target MAC'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: _setTarget, child: const Text('HUNT')),
              ],
            ),
            if (_activeTarget != null) ...[
              const SizedBox(height: 8),
              Text('Tracking: $_activeTarget',
                  style: const TextStyle(color: AppTheme.foxhunter, fontSize: 11, fontFamily: 'monospace')),
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
                      Text('dBm', style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Beep interval: ${intervalMs}ms',
                style: const TextStyle(color: AppTheme.textDim, fontSize: 11, fontFamily: 'monospace')),
            const Spacer(),
          ],
        ),
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
