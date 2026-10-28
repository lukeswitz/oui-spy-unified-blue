import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/theme/app_theme.dart';

void sortByVendor(List<Detection> dets, String? Function(Detection) keyOf,
    {String? first, bool ascending = true}) {
  final keys = Map<Detection, String?>.identity();
  for (final d in dets) {
    keys[d] = keyOf(d);
  }
  int rank(String? k) => k == null ? 2 : (k == first ? 0 : 1);
  dets.sort((a, b) {
    final ka = keys[a], kb = keys[b];
    final r = rank(ka).compareTo(rank(kb));
    if (r != 0) return r;
    if (ka != null && kb != null) {
      final v = ka.toLowerCase().compareTo(kb.toLowerCase());
      if (v != 0) return ascending ? v : -v;
    }
    return b.appTimestamp.compareTo(a.appTimestamp);
  });
}

class FeedStatsHeader extends ConsumerWidget {
  const FeedStatsHeader({super.key, required this.detections, this.selectedVendor, this.onVendorTap});
  final List<Detection> detections;
  final String? selectedVendor;
  final ValueChanged<String>? onVendorTap;

  static String? vendorKey(OuiLookupService oui, String mac) {
    final vendor = oui.lookup(mac);
    if (vendor == null) return null;
    return vendor.startsWith('Flock') ? 'Flock' : _shortenVendor(vendor);
  }

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
        selected: selectedVendor,
        onTap: onVendorTap,
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.rule),
          bottom: BorderSide(color: t.border),
        ),
      ),
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(22),
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
      final name = vendorKey(oui, d.macAddress) ?? 'Unknown';
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
    this.selected,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final List<_ChipEntry> entries;
  final ResolvedTheme t;
  final String? selected;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.textSecondary),
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null ? null : () => onTap!(entries[i].label),
            child: Row(
              children: [
                Text(
                  entries[i].label,
                  style: TextStyle(
                    color: entries[i].label == selected ? color : t.textPrimary,
                    fontSize: 10,
                    fontWeight: entries[i].label == selected ? FontWeight.w700 : FontWeight.w500,
                    fontFamily: AppTheme.mono,
                    decoration: entries[i].label == selected ? TextDecoration.underline : null,
                    decorationColor: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${entries[i].count}',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppTheme.mono,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
