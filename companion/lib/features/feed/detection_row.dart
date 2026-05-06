import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DetectionRow extends ConsumerWidget {
  const DetectionRow({super.key, required this.detection});
  final Detection detection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final engine = detection.engine;
    final hasGps = detection.latitude != null;
    final timeDiff = DateTime.now().difference(detection.appTimestamp);
    final timeStr = _formatTimeDiff(timeDiff);

    return GestureDetector(
      onLongPress: () => _showActions(context, ref),
      child: Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Engine color accent bar
            Container(
              width: 3,
              color: engine.color,
            ),
            // Content
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // MAC + name + method
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detection.macAddress.toUpperCase(),
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _MethodBadge(
                                method: detection.method,
                                color: engine.color,
                              ),
                              if (detection.count > 1) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: t.textDim.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '\u00d7${detection.count}',
                                    style: TextStyle(
                                      color: t.textDim,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                              if (detection.sourceNodeId.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warning.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.hub, size: 8, color: AppTheme.warning),
                                      const SizedBox(width: 2),
                                      Text(
                                        detection.sourceNodeId,
                                        style: const TextStyle(
                                          color: AppTheme.warning,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (detection.deviceName.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    detection.deviceName,
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // RSSI bar
                    _RssiIndicator(rssi: detection.rssi),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _startFoxhunt(context, ref),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.foxhunter.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.gps_fixed,
                          size: 14,
                          color: AppTheme.foxhunter,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: t.textDim,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          Icons.location_on,
                          size: 10,
                          color: hasGps ? AppTheme.gpsGood : AppTheme.gpsNone,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  void _startFoxhunt(BuildContext context, WidgetRef ref) {
    ref.read(appStateProvider).setFoxhunterTarget(
      detection.macAddress,
      channel: detection.channel,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Foxhunting ${detection.macAddress.toUpperCase().substring(0, 8)}...'),
        backgroundColor: AppTheme.foxhunter,
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
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
            Text(
              detection.macAddress.toUpperCase(),
              style: TextStyle(
                color: t.textPrimary, fontSize: 14,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
              ),
            ),
            if (detection.deviceName.isNotEmpty)
              Text(detection.deviceName,
                  style: TextStyle(color: t.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.gps_fixed, color: AppTheme.foxhunter),
              title: const Text('Foxhunt This Device',
                  style: TextStyle(color: AppTheme.foxhunter)),
              subtitle: Text('Track by RSSI proximity',
                  style: TextStyle(color: t.textDim, fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _startFoxhunt(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: t.textSecondary),
              title: Text('Copy MAC', style: TextStyle(color: t.textPrimary)),
              onTap: () {
                // ignore: unused_import
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeDiff(Duration diff) {
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method, required this.color});
  final String method;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RssiIndicator extends StatelessWidget {
  const _RssiIndicator({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    // Normalize RSSI from -100..0 to 0..1
    final normalized = ((rssi + 100) / 70).clamp(0.0, 1.0);
    final color = Color.lerp(AppTheme.error, AppTheme.success, normalized)!;

    return SizedBox(
      width: 30,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$rssi',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: normalized,
              backgroundColor: t.border,
              color: color,
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}
