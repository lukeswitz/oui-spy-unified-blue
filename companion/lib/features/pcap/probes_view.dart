// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/probes/probe_intel.dart';
import 'package:oui_spy/core/probes/probe_ranks.dart';
import 'package:oui_spy/core/probes/probe_store.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

enum _ProbeTab { devices, named, networks }

String probeAgo(int thenMs, int nowMs) {
  final s = ((nowMs - thenMs) / 1000).round();
  if (s < 5) return 'just now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

class ProbesView extends ConsumerStatefulWidget {
  const ProbesView({super.key});

  @override
  ConsumerState<ProbesView> createState() => _ProbesViewState();
}

class _ProbesViewState extends ConsumerState<ProbesView> {
  static const int _page = 50;
  _ProbeTab _tab = _ProbeTab.devices;
  DevSort _devSort = DevSort.recent;
  NetSort _netSort = NetSort.devices;
  bool _thisRun = false;
  int _shown = _page;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _reset(VoidCallback f) => setState(() {
        f();
        _shown = _page;
      });

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the probe database?'),
        content: const Text('Every saved probe request goes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CLEAR')),
        ],
      ),
    );
    if (ok == true) await ref.read(probeStoreProvider).clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final store = ref.watch(probeStoreProvider);
    final oui = ref.read(ouiLookupProvider);
    String maker(String mac) => makerOf(mac, oui.lookup);
    final since = _thisRun ? store.runStart : null;
    final devs = store.devices.toList();
    final twins = ProbeTwins(devs);
    final now = DateTime.now().millisecondsSinceEpoch;

    final isNet = _tab == _ProbeTab.networks;
    final devRows = isNet
        ? const <ProbeDev>[]
        : rankDevices(devs,
            sort: _devSort, maker: maker, query: _query.text, sinceMs: since, namedOnly: _tab == _ProbeTab.named);
    final netRows = isNet ? rankNetworks(devs, sort: _netSort, query: _query.text, sinceMs: since) : const <NetRank>[];
    final total = isNet ? netRows.length : devRows.length;
    final shown = _shown < total ? _shown : total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Seg(
            labels: const ['DEVICES', 'NAMED', 'NETWORKS'],
            index: _tab.index,
            onChanged: (i) => _reset(() => _tab = _ProbeTab.values[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  onChanged: (_) => _reset(() {}),
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: isNet ? 'A network name' : 'Its MAC, its maker or the names it asks for',
                    hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Chip(label: 'THIS RUN', selected: _thisRun, onTap: () => _reset(() => _thisRun = !_thisRun)),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              if (isNet)
                for (final s in NetSort.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Chip(label: s.label.toUpperCase(), selected: _netSort == s, onTap: () => _reset(() => _netSort = s)),
                  )
              else
                for (final s in DevSort.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Chip(label: s.label.toUpperCase(), selected: _devSort == s, onTap: () => _reset(() => _devSort = s)),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Text(
                '$shown OF $total ${isNet ? 'NETWORKS' : 'DEVICES'}',
                style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2, fontFamily: AppTheme.mono),
              ),
              IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: t.textSecondary),
                tooltip: 'About probe requests',
                visualDensity: VisualDensity.compact,
                onPressed: () => showInfoSheet(context, t, 'Probe requests', const [
                  'Phones and laptops asking for Wi-Fi networks they know, heard by the connected board when its detector checks probe requests or a Wi-Fi PCAP capture runs.',
                  'Makers come from each MAC, looked up on this phone.',
                  'Kept on this phone.',
                ]),
              ),
              const Spacer(),
              TextButton(
                onPressed: store.deviceCount == 0 ? null : _confirmClear,
                child: Text('CLEAR', style: TextStyle(color: AppTheme.error, fontSize: 11, letterSpacing: 2)),
              ),
            ],
          ),
        ),
        Expanded(
          child: total == 0
              ? _Empty(
                  text: store.deviceCount > 0
                      ? 'Nothing matches'
                      : isNet
                          ? 'No network asked for yet. Phones and laptops asking for networks they know by name land here.'
                          : 'No device heard asking yet. Phones and laptops asking for Wi-Fi networks land here, '
                              'with every network each one names.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: shown + (shown < total ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= shown) {
                      return TextButton(
                        onPressed: () => setState(() => _shown += _page),
                        child: Text('Show more (${total - shown} left)'),
                      );
                    }
                    if (isNet) {
                      final n = netRows[i];
                      return _NetCard(
                        key: ValueKey('net:${n.name}'),
                        rank: n,
                        askers: askersOf(n.name, devs, sinceMs: since),
                        maker: maker,
                        now: now,
                      );
                    }
                    final d = devRows[i];
                    return _DevCard(
                      key: ValueKey('dev:${d.mac}'),
                      dev: d,
                      maker: maker(d.mac),
                      twins: twins.count(d),
                      now: now,
                      onExplore: (name) => _reset(() {
                        _tab = _ProbeTab.networks;
                        _query.text = name;
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index ? AppTheme.accent.withValues(alpha: 0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == index ? AppTheme.accent : t.textPrimary,
                      fontFamily: AppTheme.mono,
                      letterSpacing: 2,
                      fontWeight: i == index ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppTheme.accent : t.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.accent : t.textSecondary,
            fontSize: 10,
            letterSpacing: 1.5,
            fontFamily: AppTheme.mono,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: t.textDim, fontSize: 12)),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}

class _DevCard extends StatelessWidget {
  const _DevCard({super.key, required this.dev, required this.maker, required this.twins, required this.now, required this.onExplore});
  final ProbeDev dev;
  final String maker;
  final int twins;
  final int now;
  final ValueChanged<String> onExplore;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final names = namesOf(dev);
    final facts = <String>[
      '${dev.count} PROBE${dev.count == 1 ? '' : 'S'}',
      if (dev.rssi != 0) '${dev.rssi} DBM',
      bandsLabel(dev.bands),
      if (dev.isRandom) 'RANDOM ADDRESS',
    ].where((s) => s.isNotEmpty).toList();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dev.isRandom ? maker : shortMaker(maker),
                  style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(probeAgo(dev.last, now).toUpperCase(),
                  style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
            ],
          ),
          const SizedBox(height: 2),
          Text(dev.mac, style: TextStyle(color: t.textSecondary, fontSize: 12, fontFamily: AppTheme.mono)),
          const SizedBox(height: 4),
          Text(facts.join('  ·  '), style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
          Text('FIRST HEARD ${probeAgo(dev.first, now).toUpperCase()}',
              style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
          if (twins > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'SAME ${dev.ssids.length} NETWORKS AS $twins OTHER MAC${twins == 1 ? '' : 'S'}',
                style: TextStyle(color: AppTheme.warning, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono),
              ),
            ),
          const SizedBox(height: 8),
          if (names.isEmpty)
            Text('Asks for any network, never one by name', style: TextStyle(color: t.textDim, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final n in names) _NameChip(name: n.$1, count: n.$2, onTap: () => onExplore(n.$1))],
            ),
        ],
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.name, required this.count, required this.onTap});
  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: t.border),
        ),
        child: Text(count > 1 ? '$name  x$count' : name, style: TextStyle(color: t.textPrimary, fontSize: 12)),
      ),
    );
  }
}

class _NetCard extends ConsumerStatefulWidget {
  const _NetCard({super.key, required this.rank, required this.askers, required this.maker, required this.now});
  final NetRank rank;
  final List<ProbeDev> askers;
  final String Function(String mac) maker;
  final int now;

  @override
  ConsumerState<_NetCard> createState() => _NetCardState();
}

class _NetCardState extends ConsumerState<_NetCard> {
  bool _open = false;
  Future<({int aps, int placed, int lastMs})>? _mapped;

  void _toggle() {
    setState(() {
      _open = !_open;
      if (_open) _mapped ??= ref.read(databaseProvider).wardriveSsidSummary(widget.rank.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final r = widget.rank;
    final summary = summarizeNetwork(widget.askers, widget.maker);
    final facts = '${r.devices} DEVICE${r.devices == 1 ? '' : 'S'}  ·  ASKED ${r.asked} TIME${r.asked == 1 ? '' : 'S'}  ·  '
        'LAST ${probeAgo(r.last, widget.now).toUpperCase()}';
    return _Card(
      child: InkWell(
        onTap: _toggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.name, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600))),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: t.textDim),
              ],
            ),
            const SizedBox(height: 4),
            Text(facts, style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
            if (r.devices == 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('ONLY ONE DEVICE ASKS FOR IT',
                    style: TextStyle(color: AppTheme.warning, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
              ),
            if (_open) ...[
              const SizedBox(height: 8),
              Text('MAKERS', style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
              for (final m in summary.makers)
                Text('${m.$1}  ${m.$2}', style: TextStyle(color: t.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              Text('DEVICES', style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
              for (final d in widget.askers)
                Text(
                  '${d.mac}  ·  asked ${d.ssids[r.name]} time${d.ssids[r.name] == 1 ? '' : 's'}  ·  '
                  '${probeAgo(d.ssidLast[r.name] ?? d.last, widget.now)}',
                  style: TextStyle(color: t.textSecondary, fontSize: 11, fontFamily: AppTheme.mono),
                ),
              const SizedBox(height: 8),
              FutureBuilder<({int aps, int placed, int lastMs})>(
                future: _mapped,
                builder: (ctx, snap) {
                  final m = snap.data;
                  if (m == null || m.aps == 0) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ON YOUR WARDRIVES', style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
                      Text(
                        '${m.aps} access point${m.aps == 1 ? '' : 's'}, ${m.placed} placed on the map, last heard '
                        '${probeAgo(m.lastMs, widget.now)}',
                        style: TextStyle(color: t.textSecondary, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
