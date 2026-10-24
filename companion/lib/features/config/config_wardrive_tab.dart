part of 'device_config.dart';

class _WardriveConfigTab extends ConsumerStatefulWidget {
  const _WardriveConfigTab({required this.showAccounts});
  final bool showAccounts;

  @override
  ConsumerState<_WardriveConfigTab> createState() => _WardriveConfigTabState();
}

class _WardriveConfigTabState extends ConsumerState<_WardriveConfigTab> {
  late Future<CollectionStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = ref.read(databaseProvider).wardriveCollectionStats();
  }

  void _reload() {
    setState(() {
      _statsFuture = ref.read(databaseProvider).wardriveCollectionStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    if (widget.showAccounts) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: const [
          ConfigSectionHeader(label: 'Wardrive accounts'),
          SizedBox(height: 10),
          _WigleSection(),
          SizedBox(height: 18),
          _WdgwarsSection(),
          SizedBox(height: 20),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Row(
          children: [
            const Expanded(child: ConfigSectionHeader(label: 'Your capture database')),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _reload,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.refresh, size: 16, color: t.textDim),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Text(
            'Counts below are from this app\'s own wardrive sessions only.',
            style: TextStyle(color: t.textDim, fontSize: 11),
          ),
        ),
        FutureBuilder<CollectionStats>(
          future: _statsFuture,
          builder: (context, snap) {
            if (!snap.hasData) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent),
                  ),
                ),
              );
            }
            final s = snap.data!;
            if (s.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.travel_explore, size: 18, color: t.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No data yet — run a wardrive session to build stats.',
                        style: TextStyle(color: t.textDim, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }
            return _CollectionStatsView(stats: s);
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _CollectionStatsView extends ConsumerWidget {
  const _CollectionStatsView({required this.stats});
  final CollectionStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oui = ref.watch(ouiLookupProvider);

    final vendorCounts = <String, int>{};
    for (final e in stats.ouiCounts) {
      final name = oui.lookup('${e.key}:00:00:00') ?? 'Unknown';
      vendorCounts[name] = (vendorCounts[name] ?? 0) + e.value;
    }
    final topVendors = vendorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final vendors = topVendors.take(12).toList();

    final flockVendorCounts = <String, int>{};
    for (final e in stats.flockOuiCounts) {
      final name = oui.lookup('${e.key}:00:00:00') ?? 'Unknown';
      flockVendorCounts[name] = (flockVendorCounts[name] ?? 0) + e.value;
    }
    final flockVendors = (flockVendorCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(8)
        .toList();

    final reg = ref.watch(deviceRegistryProvider);
    final byClass = <String, int>{};
    final bySig = <String, int>{};
    var classified = 0;
    for (final d in reg.devices) {
      final c = d.primaryClass;
      if (c == null) continue;
      classified++;
      byClass[c.label] = (byClass[c.label] ?? 0) + 1;
      for (final n in d.signatureNames.toSet()) {
        bySig[n] = (bySig[n] ?? 0) + 1;
      }
    }
    final classCounts = (byClass.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
    final sigCounts = (bySig.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MiniStatTile(icon: Icons.fingerprint, label: 'UNIQUE',
                value: _fmt(stats.totalUnique), color: AppTheme.accent),
            _MiniStatTile(icon: Icons.wifi, label: 'WIFI',
                value: _fmt(stats.wifiUnique), color: AppTheme.wardrive),
            _MiniStatTile(icon: Icons.bluetooth, label: 'BLE',
                value: _fmt(stats.bleUnique), color: AppTheme.detector),
            _MiniStatTile(icon: Icons.router, label: 'SSIDS',
                value: _fmt(stats.ssidCount), color: AppTheme.skySpy),
            _MiniStatTile(icon: Icons.route, label: 'SESSIONS',
                value: '${stats.sessionCount}', color: AppTheme.success),
            _MiniStatTile(icon: Icons.sensors, label: 'HITS',
                value: _fmt(stats.totalDetections), color: AppTheme.warning),
          ],
        ),
        const SizedBox(height: 18),

        if (stats.channelCounts.isNotEmpty) ...[
          _StatBlockLabel('CHANNEL DISTRIBUTION', Icons.equalizer),
          const SizedBox(height: 8),
          _ChannelChart(
            counts: {
              for (final e in stats.channelCounts.entries)
                if (e.key <= 14) e.key: e.value,
            },
            band: '2.4 GHz',
            color: AppTheme.accent,
          ),
          if (stats.channelCounts.keys.any((c) => c >= 36)) ...[
            const SizedBox(height: 10),
            _ChannelChart(
              counts: {
                for (final e in stats.channelCounts.entries)
                  if (e.key >= 36) e.key: e.value,
              },
              band: '5 GHz',
              color: AppTheme.skySpy,
              angled: true,
            ),
          ],
          const SizedBox(height: 18),
        ],

        if (vendors.isNotEmpty) ...[
          _StatBlockLabel('TOP VENDORS', Icons.factory),
          const SizedBox(height: 8),
          ...() {
            final maxV = vendors.first.value;
            return vendors.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _BarRow(
                    label: e.key,
                    value: e.value,
                    max: maxV,
                    color: _heat(e.value, maxV),
                    labelAbove: true,
                  ),
                ));
          }(),
          const SizedBox(height: 18),
        ],

        if (flockVendors.isNotEmpty) ...[
          _StatBlockLabel('TOP FLOCK VENDORS', Icons.videocam),
          const SizedBox(height: 8),
          ...() {
            final maxV = flockVendors.first.value;
            return flockVendors.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _BarRow(
                    label: e.key,
                    value: e.value,
                    max: maxV,
                    color: AppTheme.flockBle,
                    labelAbove: true,
                  ),
                ));
          }(),
          const SizedBox(height: 18),
        ],

        if (classCounts.isNotEmpty) ...[
          _StatBlockLabel('CLASSIFIED DEVICES · ${_fmt(classified)} of ${_fmt(reg.count)} seen', Icons.category),
          const SizedBox(height: 8),
          ...() {
            final maxV = classCounts.first.value;
            return classCounts.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _BarRow(
                    label: e.key,
                    value: e.value,
                    max: maxV,
                    color: _heat(e.value, maxV),
                    labelAbove: true,
                  ),
                ));
          }(),
          const SizedBox(height: 10),
          _StatBlockLabel('TOP SIGNATURES', Icons.fingerprint),
          const SizedBox(height: 8),
          ...() {
            final maxV = sigCounts.first.value;
            return sigCounts.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _BarRow(
                    label: e.key,
                    value: e.value,
                    max: maxV,
                    color: AppTheme.detector,
                    labelAbove: true,
                  ),
                ));
          }(),
          const SizedBox(height: 18),
        ],

        if (stats.authCounts.isNotEmpty) ...[
          _StatBlockLabel('ENCRYPTION', Icons.lock_outline),
          const SizedBox(height: 8),
          ...() {
            final entries = stats.authCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final maxV = entries.first.value;
            return entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _BarRow(
                    label: _authLabel(e.key),
                    value: e.value,
                    max: maxV,
                    color: _authColor(e.key),
                  ),
                ));
          }(),
        ],

      ],
    );
  }

  static String _fmt(int c) {
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(1)}M';
    if (c >= 1000) return '${(c / 1000).toStringAsFixed(1)}K';
    return '$c';
  }

  static Color _heat(int value, int max) {
    final f = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Color.lerp(AppTheme.wdgwars, AppTheme.wardrive, 1 - f)!;
  }

  static String _authLabel(int a) => switch (a) {
        0 => 'Open',
        1 => 'WEP',
        2 => 'WPA',
        3 => 'WPA2',
        4 => 'WPA/WPA2',
        5 => 'WPA2-EAP',
        6 => 'WPA3',
        _ => 'Other',
      };

  static Color _authColor(int a) => switch (a) {
        0 => AppTheme.error,
        1 => AppTheme.error,
        2 => AppTheme.warning,
        6 => AppTheme.success,
        _ => AppTheme.accent,
      };
}

class _StatBlockLabel extends StatelessWidget {
  const _StatBlockLabel(this.label, this.icon);
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: t.textDim),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          color: t.textSecondary, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.5,
        )),
      ],
    );
  }
}

class _MiniStatTile extends StatelessWidget {
  const _MiniStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final w = (MediaQuery.of(context).size.width - 32 - 16) / 3;
    return Container(
      width: w.clamp(90.0, 140.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                color: t.textDim, fontSize: 8,
                fontWeight: FontWeight.w700, letterSpacing: 1,
              )),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(
            color: t.textPrimary, fontSize: 18,
            fontWeight: FontWeight.w700, fontFamily: AppTheme.mono, height: 1,
          )),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.labelAbove = false,
  });
  final String label;
  final int value;
  final int max;
  final Color color;
  final bool labelAbove;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final f = max == 0 ? 0.0 : (value / max).clamp(0.02, 1.0);
    final bar = Stack(
      children: [
        Container(height: 14, color: t.surface),
        FractionallySizedBox(
          widthFactor: f,
          child: Container(height: 14, color: color.withValues(alpha: 0.85)),
        ),
      ],
    );
    final valueText = Text(
      _CollectionStatsView._fmt(value),
      textAlign: TextAlign.right,
      style: TextStyle(
        color: t.textPrimary, fontSize: 11,
        fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
      ),
    );

    if (labelAbove) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              valueText,
            ],
          ),
          const SizedBox(height: 3),
          bar,
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(color: t.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: bar),
        const SizedBox(width: 8),
        SizedBox(width: 44, child: valueText),
      ],
    );
  }
}

class _ChannelChart extends StatelessWidget {
  const _ChannelChart({
    required this.counts,
    required this.band,
    required this.color,
    this.angled = false,
  });
  final Map<int, int> counts;
  final String band;
  final Color color;
  final bool angled;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    if (counts.isEmpty) return const SizedBox.shrink();
    final entries = counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxV = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final countStyle = TextStyle(
      color: t.textDim, fontSize: 8, fontFamily: AppTheme.mono,
    );
    final chStyle = TextStyle(
      color: t.textSecondary, fontSize: 8, fontFamily: AppTheme.mono,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(band, style: TextStyle(
          color: t.textDim, fontSize: 9,
          fontWeight: FontWeight.w600, letterSpacing: 1,
        )),
        const SizedBox(height: 4),
        SizedBox(
          height: angled ? 92 : 64,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: entries.map((e) {
              final f = maxV == 0 ? 0.0 : (e.value / maxV).clamp(0.06, 1.0);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: angled ? 1.0 : 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (angled)
                        _diag(_CollectionStatsView._fmt(e.value), countStyle)
                      else
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                              _CollectionStatsView._fmt(e.value), style: countStyle),
                        ),
                      const SizedBox(height: 2),
                      Container(
                        height: 40 * f,
                        color: color.withValues(alpha: 0.85),
                      ),
                      const SizedBox(height: 3),
                      if (angled)
                        _diag('${e.key}', chStyle)
                      else
                        Text('${e.key}', style: chStyle),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  static Widget _diag(String s, TextStyle style) => SizedBox(
        height: 20,
        child: OverflowBox(
          minWidth: 0,
          maxWidth: 70,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: -0.7,
            child: Text(s, maxLines: 1, softWrap: false, style: style),
          ),
        ),
      );
}

