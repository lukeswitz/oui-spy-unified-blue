import 'package:flutter/material.dart';
import 'package:oui_spy/core/models/session.dart';
import 'package:oui_spy/theme/app_theme.dart';

class WardriveStats extends StatelessWidget {
  const WardriveStats({super.key, required this.stats});
  final SessionStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.85),
        border:
            const Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // Primary stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(
                value: _formatDuration(stats.duration),
                label: 'TIME',
              ),
              _StatCell(
                value: stats.distanceKm.toStringAsFixed(1),
                label: 'KM',
              ),
              _StatCell(
                value: stats.speedKmh.toStringAsFixed(0),
                label: 'KM/H',
              ),
              _StatCell(
                value: '${stats.totalDetections}',
                label: 'TOTAL',
                color: AppTheme.accent,
              ),
              _StatCell(
                value: '${stats.uniqueMacs}',
                label: 'UNIQUE',
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Secondary stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(
                value: '${stats.newMacs}',
                label: 'NEW',
                color: AppTheme.success,
              ),
              _StatCell(
                value: '${stats.wifiDetections}',
                label: 'WIFI',
              ),
              _StatCell(
                value: '${stats.bleDetections}',
                label: 'BLE',
              ),
              if (stats.flockCount > 0)
                _StatCell(
                  value: '${stats.flockCount}',
                  label: 'FLOCK',
                  color: AppTheme.flockBle,
                ),
              if (stats.droneCount > 0)
                _StatCell(
                  value: '${stats.droneCount}',
                  label: 'DRONE',
                  color: AppTheme.skySpy,
                ),
              _StatCell(
                value: stats.detectionsPerKm.toStringAsFixed(0),
                label: 'DET/KM',
              ),
              _GpsCell(
                accuracy: stats.gpsAccuracy,
                satellites: stats.satelliteCount,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    this.color,
  });
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _GpsCell extends StatelessWidget {
  const _GpsCell({required this.accuracy, required this.satellites});
  final double accuracy;
  final int satellites;

  @override
  Widget build(BuildContext context) {
    final color = accuracy <= 0
        ? AppTheme.gpsNone
        : accuracy <= 10
            ? AppTheme.gpsGood
            : accuracy <= 50
                ? AppTheme.gpsFair
                : AppTheme.gpsPoor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 3),
            Text(
              accuracy > 0 ? '${accuracy.toStringAsFixed(0)}m' : '--',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        Text(
          'GPS',
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
