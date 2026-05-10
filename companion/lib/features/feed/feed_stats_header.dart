import 'package:flutter/material.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Top stats bar showing most-seen OUI prefixes and most-seen Flock devices.
class FeedStatsHeader extends StatelessWidget {
  const FeedStatsHeader({super.key, required this.detections});
  final List<Detection> detections;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final topOuis = _topOuis(detections, 3);
    final topFlocks = _topFlocks(detections, 3);

    if (topOuis.isEmpty && topFlocks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topOuis.isNotEmpty)
            Expanded(child: _StatsCard(
              icon: Icons.router,
              iconColor: AppTheme.accent,
              title: 'TOP OUI',
              entries: topOuis,
              badgeColor: AppTheme.accent,
              t: t,
            )),
          if (topOuis.isNotEmpty && topFlocks.isNotEmpty)
            const SizedBox(width: 8),
          if (topFlocks.isNotEmpty)
            Expanded(child: _StatsCard(
              icon: Icons.videocam,
              iconColor: Engine.flockWifi.color,
              title: 'TOP FLOCK',
              entries: topFlocks,
              badgeColor: Engine.flockWifi.color,
              t: t,
            )),
        ],
      ),
    );
  }

  /// Extract top N OUI prefixes by detection count across all engines.
  static List<_StatEntry> _topOuis(List<Detection> dets, int n) {
    final ouiCounts = <String, int>{};
    for (final d in dets) {
      final mac = d.macAddress.toUpperCase();
      if (mac.length < 8) continue;
      final oui = mac.substring(0, 8); // "AA:BB:CC"
      ouiCounts[oui] = (ouiCounts[oui] ?? 0) + d.count;
    }
    final sorted = ouiCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) {
      final vendor = _ouiVendorHint(e.key);
      return _StatEntry(
        label: e.key,
        subtitle: vendor,
        count: e.value,
      );
    }).toList();
  }

  /// Extract top N Flock devices by detection count.
  static List<_StatEntry> _topFlocks(List<Detection> dets, int n) {
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
      final suffix = agg.isRaven ? ' RAVEN' : '';
      return _StatEntry(
        label: _shortenMac(e.key),
        subtitle: '${agg.method}$suffix',
        count: agg.count,
      );
    }).toList();
  }

  static String _shortenMac(String mac) {
    if (mac.length < 17) return mac;
    return '${mac.substring(0, 8)}..${mac.substring(15)}';
  }

  /// Best-effort vendor hint from OUI prefix.
  static String _ouiVendorHint(String oui) {
    final lookup = oui.replaceAll(':', '').toUpperCase();
    return _knownOuis[lookup] ?? '';
  }

  static const _knownOuis = <String, String>{
    // Flock Safety
    '588E81': 'Flock', 'EC1BBD': 'Flock', '9035EA': 'Flock',
    '040D84': 'Flock', 'F082C0': 'Flock', '1C34F1': 'Flock',
    '385B44': 'Flock', '943469': 'Flock', 'B4E3F9': 'Flock',
    '70C94E': 'Flock', '3C9180': 'Flock', 'D8F3BC': 'Flock',
    '803049': 'Flock', '145AFC': 'Flock', '744CA1': 'Flock',
    '083A88': 'Flock', '9C2F9D': 'Flock', '940853': 'Flock',
    'E4AAEA': 'Flock', 'CCCCCC': 'Flock',
    // Common vendors
    'DCCFEE': 'Motorola', '002272': 'Cisco', 'F4F5D8': 'Google',
    'DC56E7': 'Apple', '3C22FB': 'Apple', 'A4C3F0': 'Apple',
    'ACDE48': 'Apple', 'F0D4F6': 'Apple', '94E979': 'Apple',
    '8C8590': 'Apple', 'BC3400': 'Apple', 'CC2DB7': 'Apple',
    '28FF3E': 'Samsung', 'E440E2': 'Samsung', 'B0C420': 'Samsung',
    'AC5F3E': 'Samsung', '889B39': 'Samsung',
    '606D3C': 'Intel', 'A44CC8': 'Intel', '489EBD': 'Intel',
    'B8E856': 'Intel', '7CC2C6': 'Intel',
    '3CFB5C': 'Qualcomm', '70660B': 'Qualcomm',
    '8C1F64': 'Espressif', '30AEA4': 'Espressif',
    '807D3A': 'Espressif', '243DB2': 'Espressif',
    'B8D61A': 'TP-Link', '60A4B7': 'TP-Link',
    '14CC20': 'TP-Link', '50C7BF': 'TP-Link',
    'AAAA03': 'Virtual', 'FEFEFE': 'RFC7042',
  };
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

class _StatEntry {
  const _StatEntry({
    required this.label,
    required this.count,
    this.subtitle = '',
  });
  final String label;
  final String subtitle;
  final int count;
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.entries,
    required this.badgeColor,
    required this.t,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<_StatEntry> entries;
  final Color badgeColor;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.label,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (e.subtitle.isNotEmpty)
                        Text(
                          e.subtitle,
                          style: TextStyle(
                            color: t.textDim,
                            fontSize: 8,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${e.count}',
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
