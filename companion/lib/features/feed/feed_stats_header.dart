import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/theme/app_theme.dart';

class FeedStatsHeader extends ConsumerWidget {
  const FeedStatsHeader({super.key, required this.detections});
  final List<Detection> detections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final oui = ref.read(ouiLookupProvider);
    final topVendors = _topVendors(detections, oui, 4);
    final topFlock = _topFlock(detections, 2);

    if (topVendors.isEmpty && topFlock.isEmpty) return const SizedBox.shrink();

    final items = <Widget>[];
    if (topVendors.isNotEmpty) {
      items.add(_Section(
        label: 'VENDORS',
        icon: Icons.router,
        color: AppTheme.accent,
        entries: topVendors,
        t: t,
      ));
    }
    if (topFlock.isNotEmpty) {
      items.add(_Section(
        label: 'FLOCK',
        icon: Icons.videocam,
        color: Engine.flockWifi.color,
        entries: topFlock,
        t: t,
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SizedBox(
        height: 22,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(width: 1, color: t.border),
          ),
          itemBuilder: (_, i) => items[i],
        ),
      ),
    );
  }

  static List<_ChipEntry> _topVendors(
    List<Detection> dets,
    OuiLookupService oui,
    int n,
  ) {
    final vendorCounts = <String, int>{};
    for (final d in dets) {
      final vendor = oui.lookup(d.macAddress) ?? 'Unknown';
      final name = vendor.startsWith('Flock') ? 'Flock' : _shortenVendor(vendor);
      vendorCounts[name] = (vendorCounts[name] ?? 0) + d.count;
    }
    vendorCounts.remove('Unknown');
    final sorted = vendorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(n)
        .map((e) => _ChipEntry(label: e.key, count: e.value))
        .toList();
  }

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
      return _ChipEntry(label: '$mac$suffix', count: agg.count);
    }).toList();
  }

  static String _shortenVendor(String v) {
    var s = v
        .replaceAll(RegExp(r',?\s+(Inc|Inc\.|LLC|Ltd|Ltd\.|Corp|Corp\.|Corporation|Co\.|Co|GmbH|S\.A\.|S\.r\.l\.|AG|KG|Limited|Solutions|Networks|Communications|Technology|Technologies|Systems|International|Electronics|Industries)\.?\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*&\s*Co\.?\s*KG', caseSensitive: false), '')
        .trim();
    if (s.length > 18) s = '${s.substring(0, 17)}…';
    return s.isEmpty ? v : s;
  }

  static String _shortenMac(String mac) {
    if (mac.length < 17) return mac;
    return mac.substring(9);
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

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.icon,
    required this.color,
    required this.entries,
    required this.t,
  });
  final String label;
  final IconData icon;
  final Color color;
  final List<_ChipEntry> entries;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·',
                  style: TextStyle(
                    color: t.textDim.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          Text(
            entries[i].label,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${entries[i].count}',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}
