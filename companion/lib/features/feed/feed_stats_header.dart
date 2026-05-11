import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Compact stats rows: top vendors (line 1), top flock devices (line 2).
class FeedStatsHeader extends ConsumerWidget {
  const FeedStatsHeader({super.key, required this.detections});
  final List<Detection> detections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final oui = ref.read(ouiLookupProvider);
    final topVendors = _topVendors(detections, oui, 4);
    final topFlock = _topFlock(detections, 1);

    if (topVendors.isEmpty && topFlock.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topVendors.isNotEmpty)
            _ChipRow(
              icon: Icons.router,
              iconColor: AppTheme.accent,
              label: 'VENDORS',
              entries: topVendors,
              chipColor: AppTheme.accent,
              t: t,
            ),
          if (topVendors.isNotEmpty && topFlock.isNotEmpty)
            const SizedBox(height: 3),
          if (topFlock.isNotEmpty)
            _ChipRow(
              icon: Icons.videocam,
              iconColor: Engine.flockWifi.color,
              label: 'FLOCK',
              entries: topFlock,
              chipColor: Engine.flockWifi.color,
              t: t,
            ),
        ],
      ),
    );
  }

  /// Group detections by resolved vendor name, return top N.
  static List<_ChipEntry> _topVendors(
    List<Detection> dets,
    OuiLookupService oui,
    int n,
  ) {
    final vendorCounts = <String, int>{};
    for (final d in dets) {
      final vendor = oui.lookup(d.macAddress) ?? 'Unknown';
      // Normalize Flock sub-types to single entry
      final name = vendor.startsWith('Flock') ? 'Flock' : vendor;
      vendorCounts[name] = (vendorCounts[name] ?? 0) + d.count;
    }
    // Drop "Unknown" from display — not useful
    vendorCounts.remove('Unknown');
    final sorted = vendorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(n)
        .map((e) => _ChipEntry(label: e.key, count: e.value))
        .toList();
  }

  /// Top flock device by detection count — single entry for one-line display.
  static List<_ChipEntry> _topFlock(List<Detection> dets, int n) {
    final flockDets = dets.where((d) =>
        d.engine == Engine.flockBle ||
        d.engine == Engine.flockWifi ||
        (d.engine == Engine.wardrive && d.method == 'flock_oui'));
    final macCounts = <String, _FlockAgg>{};
    for (final d in flockDets) {
      final mac = d.macAddress.toUpperCase();
      final existing = macCounts[mac];
      if (existing != null) {
        macCounts[mac] = _FlockAgg(
          count: existing.count + d.count,
          method: d.method,
          isRaven: existing.isRaven || (d.flock?.isRaven ?? false),
          bestRssi: d.rssi > existing.bestRssi ? d.rssi : existing.bestRssi,
        );
      } else {
        macCounts[mac] = _FlockAgg(
          count: d.count,
          method: d.method,
          isRaven: d.flock?.isRaven ?? false,
          bestRssi: d.rssi,
        );
      }
    }
    final sorted = macCounts.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));
    return sorted.take(n).map((e) {
      final agg = e.value;
      final suffix = agg.isRaven ? ' RVN' : '';
      final mac = _shortenMac(e.key);
      return _ChipEntry(
        label: '$mac ${agg.method}$suffix',
        count: agg.count,
      );
    }).toList();
  }

  static String _shortenMac(String mac) {
    if (mac.length < 17) return mac;
    return '${mac.substring(0, 8)}..${mac.substring(15)}';
  }
}

class _FlockAgg {
  const _FlockAgg({
    required this.count,
    required this.method,
    required this.isRaven,
    required this.bestRssi,
  });
  final int count;
  final String method;
  final bool isRaven;
  final int bestRssi;
}

class _ChipEntry {
  const _ChipEntry({required this.label, required this.count});
  final String label;
  final int count;
}

/// Single-line row: icon + label + scrollable chip list.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.entries,
    required this.chipColor,
    required this.t,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final List<_ChipEntry> entries;
  final Color chipColor;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Icon(icon, size: 10, color: iconColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: iconColor,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) => _buildChip(entries[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(_ChipEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: chipColor.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.label,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${entry.count}',
            style: TextStyle(
              color: chipColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
