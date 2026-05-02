import 'package:flutter/material.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Compact flock count badge. Tap to expand detail list.
/// Receives pre-deduped flock detections (unique per MAC).
class FlockPanel extends StatefulWidget {
  const FlockPanel({super.key, required this.detections});
  final List<Detection> detections;

  @override
  State<FlockPanel> createState() => _FlockPanelState();
}

class _FlockPanelState extends State<FlockPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.detections.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: count > 0 ? () => setState(() => _expanded = !_expanded) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: count > 0
                  ? AppTheme.flockBle.withValues(alpha: 0.2)
                  : AppTheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: count > 0
                    ? AppTheme.flockBle.withValues(alpha: 0.5)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam, size: 11,
                    color: count > 0 ? AppTheme.flockBle : AppTheme.textDim),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    color: count > 0 ? AppTheme.flockBle : AppTheme.textDim,
                    fontSize: 11, fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 11, color: AppTheme.flockBle,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded && widget.detections.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 140, maxWidth: 240),
            decoration: BoxDecoration(
              color: AppTheme.background.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.flockBle.withValues(alpha: 0.3)),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 2),
              shrinkWrap: true,
              itemCount: widget.detections.length,
              itemBuilder: (_, i) => _Row(d: widget.detections[i]),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.d});
  final Detection d;

  @override
  Widget build(BuildContext context) {
    final isBle = d.engine == Engine.flockBle;
    final color = isBle ? AppTheme.flockBle : AppTheme.flockWifi;
    final isRaven = d.flock?.isRaven ?? false;
    final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
    final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          Container(
            width: 2, height: 16,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Row(children: [
              Text(
                d.macAddress.toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 9,
                  fontFamily: 'monospace', fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  isBle ? 'B' : 'W',
                  style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w700),
                ),
              ),
              if (isRaven) ...[
                const SizedBox(width: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text('R',
                    style: TextStyle(color: AppTheme.warning, fontSize: 7, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
          Text('${d.rssi}', style: TextStyle(
            color: rssiColor, fontSize: 9,
            fontFamily: 'monospace', fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}
