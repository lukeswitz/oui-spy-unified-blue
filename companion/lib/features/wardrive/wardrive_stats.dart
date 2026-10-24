import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/models/session.dart';
import 'package:oui_spy/theme/app_theme.dart';

class WardriveStats extends ConsumerWidget {
  const WardriveStats({super.key, required this.stats});
  final SessionStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final gpsColor = stats.gpsAccuracy <= 0
        ? AppTheme.gpsNone
        : stats.gpsAccuracy <= 10
            ? AppTheme.gpsGood
            : stats.gpsAccuracy <= 50
                ? AppTheme.gpsFair
                : AppTheme.gpsPoor;

    final label = Theme.of(context).textTheme.labelSmall;
    final hasWifi = stats.wifiDetections > 0 || stats.wifiTotal > 0;
    final hasBle = stats.bleDetections > 0 || stats.bleTotal > 0;
    final counts = <({String key, String label, int unique, int? total})>[
      if (hasWifi)
        (key: 'wifi', label: 'WIFI', unique: stats.wifiDetections, total: stats.wifiTotal),
      if (stats.flockCount > 0)
        (key: 'flock', label: 'FLOCK', unique: stats.flockCount, total: null),
      if (stats.droneCount > 0)
        (key: 'drone', label: 'DRONE', unique: stats.droneCount, total: null),
      if (stats.detectorCount > 0)
        (key: 'detect', label: 'DETECT', unique: stats.detectorCount, total: null),
      if (hasBle)
        (key: 'ble', label: 'BLE', unique: stats.bleDetections, total: stats.bleTotal),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Container(
        key: const Key('wardrive-stats-card'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: t.fill,
          border: Border.all(color: t.fillBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: t.mark,
                  child: Text('REC', style: label?.copyWith(color: t.fill)),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(stats.duration),
                  style: TextStyle(
                    color: t.onFill,
                    fontSize: 13,
                    fontFamily: AppTheme.mono,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: gpsColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  stats.gpsAccuracy > 0 ? '${stats.gpsAccuracy.toStringAsFixed(0)}m' : '--',
                  style: TextStyle(
                    color: gpsColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppTheme.mono,
                  ),
                ),
              ],
            ),
            if (counts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, thickness: 1, color: t.onFillDim.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
              _Spread(
                children: [
                  for (final c in counts)
                    _Stat(
                      key: Key('count-${c.key}'),
                      value: '${c.unique}',
                      label: c.label,
                      sub: c.total != null ? '${c.total} total' : null,
                      valueColor: t.onFill,
                      labelColor: t.onFillDim,
                    ),
                ],
              ),
            ],
          ],
        ),
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

class WardriveRunCard extends ConsumerWidget {
  const WardriveRunCard({
    super.key,
    required this.stats,
    required this.targets,
    required this.paused,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.showButtons = true,
  });
  final SessionStats stats;
  final String targets;
  final bool paused;
  final bool showButtons;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    final label = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        key: const Key('wardrive-run-card'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('WARDRIVE', style: label?.copyWith(color: t.textSecondary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    targets,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12,
                      fontFamily: AppTheme.mono,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Spread(
              children: [
                _Stat(
                  value: UnitFormatter.distance(stats.distanceKm, units),
                  label: 'DISTANCE',
                  valueColor: t.textPrimary,
                  labelColor: t.textSecondary,
                ),
                _Stat(
                  value: UnitFormatter.speed(stats.speedKmh, units),
                  label: 'SPEED',
                  valueColor: t.textPrimary,
                  labelColor: t.textSecondary,
                ),
                _Stat(
                  value: UnitFormatter.detPerDist(stats.detectionsPerKm, units),
                  label: UnitFormatter.detPerDistLabel(units),
                  valueColor: t.textPrimary,
                  labelColor: t.textSecondary,
                ),
              ],
            ),
            if (showButtons) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                    onPressed: onStop,
                    child: const Text('Stop'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: paused
                      ? ElevatedButton(onPressed: onResume, child: const Text('Resume'))
                      : OutlinedButton(onPressed: onPause, child: const Text('Pause')),
                ),
              ],
            ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Spread extends StatelessWidget {
  const _Spread({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.value,
    required this.label,
    required this.valueColor,
    required this.labelColor,
    this.sub,
  });
  final String value;
  final String label;
  final String? sub;
  final Color valueColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall?.copyWith(color: labelColor);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: valueColor,
            fontSize: 22,
            fontWeight: FontWeight.w500,
            fontFamily: AppTheme.mono,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, maxLines: 1, style: small),
        if (sub != null) Text(sub!, maxLines: 1, style: small),
      ],
    );
  }
}
