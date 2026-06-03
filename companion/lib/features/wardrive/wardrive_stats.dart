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
    final units = ref.watch(unitSystemProvider);

    final gpsColor = stats.gpsAccuracy <= 0
        ? AppTheme.gpsNone
        : stats.gpsAccuracy <= 10
            ? AppTheme.gpsGood
            : stats.gpsAccuracy <= 50
                ? AppTheme.gpsFair
                : AppTheme.gpsPoor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.88),
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: _heroRow(t),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _InfoChip(Icons.timer_outlined, _formatDuration(stats.duration), t.textSecondary, t),
                const SizedBox(width: 6),
                _InfoChip(Icons.straighten, UnitFormatter.distance(stats.distanceKm, units), t.textSecondary, t),
                const SizedBox(width: 6),
                _InfoChip(Icons.speed, UnitFormatter.speed(stats.speedKmh, units), t.textSecondary, t),
                const SizedBox(width: 6),
                _InfoChip(null, '${UnitFormatter.detPerDist(stats.detectionsPerKm, units)} ${UnitFormatter.detPerDistLabel(units).toLowerCase()}', t.textSecondary, t),
                const SizedBox(width: 6),
                _GpsChip(accuracy: stats.gpsAccuracy, color: gpsColor, t: t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _heroRow(ResolvedTheme t) {
    final hasWifi = stats.wifiDetections > 0 || stats.wifiTotal > 0;
    final hasBle = stats.bleDetections > 0 || stats.bleTotal > 0;
    final flockSolo = stats.wifiDetections == 0 && stats.bleDetections == 0;
    final counts = <Widget>[
      if (hasWifi)
        Expanded(
          flex: 3,
          child: _HeroCount(
            icon: Icons.wifi,
            unique: stats.wifiDetections,
            total: stats.wifiTotal,
            color: AppTheme.accent,
            fontSize: 44,
          ),
        ),
      if (stats.flockCount > 0)
        Expanded(
          flex: flockSolo ? 3 : 2,
          child: _HeroCount(
            icon: Icons.videocam,
            unique: stats.flockCount,
            total: null,
            color: AppTheme.flockBle,
            fontSize: flockSolo ? 44 : 30,
          ),
        ),
      if (hasBle)
        Expanded(
          flex: 2,
          child: _HeroCount(
            icon: Icons.bluetooth,
            unique: stats.bleDetections,
            total: stats.bleTotal,
            color: t.textSecondary,
            fontSize: 30,
          ),
        ),
    ];
    final out = <Widget>[];
    for (var i = 0; i < counts.length; i++) {
      if (i > 0) {
        out.add(Container(
          width: 0.5,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: t.border,
        ));
      }
      out.add(counts[i]);
    }
    return out;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _HeroCount extends StatelessWidget {
  const _HeroCount({
    required this.icon,
    required this.unique,
    required this.total,
    required this.color,
    required this.fontSize,
  });
  final IconData icon;
  final int unique;
  final int? total;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: fontSize * 0.4, color: color.withValues(alpha: 0.85)),
        const SizedBox(height: 2),
        Text(
          '$unique',
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          total != null ? '$total total' : 'unique',
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.value, this.color, this.t);
  final IconData? icon;
  final String value;
  final Color color;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.accuracy, required this.color, required this.t});
  final double accuracy;
  final Color color;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            accuracy > 0 ? '${accuracy.toStringAsFixed(0)}m' : '--',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
