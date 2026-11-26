// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_tags.dart';
import 'package:oui_spy/core/mesh_node_info.dart';
import 'package:oui_spy/core/metrics/fleet_metrics.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/probes/probe_intel.dart';
import 'package:oui_spy/core/wardrive_report.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

enum _Mode {
  detections('Detections'),
  wardrive('Wardrive'),
  drones('Drones');

  const _Mode(this.label);
  final String label;
}

class _Loaded {
  const _Loaded({required this.mode, required this.metrics, required this.nodes, required this.drones});
  final _Mode mode;
  final FleetMetrics metrics;
  final List<String> nodes;
  final DroneMetrics? drones;
}

class FleetMetricsScreen extends ConsumerStatefulWidget {
  const FleetMetricsScreen({super.key});

  @override
  ConsumerState<FleetMetricsScreen> createState() => _FleetMetricsScreenState();
}

class _FleetMetricsScreenState extends ConsumerState<FleetMetricsScreen> {
  _Mode _mode = _Mode.detections;
  MetricsRange _range = MetricsRange.day;
  String? _node;
  late Future<_Loaded> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_Loaded> _load() async {
    final db = ref.read(databaseProvider);
    final oui = ref.read(ouiLookupProvider);
    final app = ref.read(appStateProvider);
    final mode = _mode;
    final range = _range;
    final node = _node;
    final now = DateTime.now();
    final to = now.millisecondsSinceEpoch;
    final from = to - range.span.inMilliseconds;
    final rows = await db.metricRows(from, to, node: node);
    final before = await db.metricCount(from - range.span.inMilliseconds, from, node: node);
    final nodes = await db.metricNodes();
    final fresh = mode == _Mode.drones ? const <String>{} : await db.metricNewMacs(from, to, node: node);
    final metrics = computeMetrics(
      rows,
      range: range,
      toMs: to,
      previousCount: before,
      vendorOf: (mac) => shortMaker(makerOf(mac, oui.lookup)),
      nodeLabel: app.labelForNode,
      securityOf: wifiSecurityLabel,
      newMacs: fresh,
    );
    final drones = mode == _Mode.drones
        ? computeDroneMetrics(
            await db.metricDrones(from, to, node: node),
            range: range,
            toMs: to,
            now: now,
            nodeLabel: app.labelForNode,
          )
        : null;
    return _Loaded(mode: mode, metrics: metrics, nodes: nodes, drones: drones);
  }

  void _reload() => setState(() {
        _data = _load();
      });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final app = ref.watch(appStateProvider);
    final tags = ref.watch(droneTagsProvider);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('FLEET METRICS'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: FutureBuilder<_Loaded>(
        future: _data,
        builder: (context, snap) {
          final d = snap.data;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ..._meshSection(t, app),
              const SizedBox(height: 12),
              const ConfigSectionHeader(label: 'Detections'),
              _controls(t, d?.nodes ?? const [], app),
              const SizedBox(height: 8),
              if (snap.hasError)
                Text('Could not work out the metrics: ${snap.error}', style: TextStyle(color: AppTheme.error, fontSize: 13))
              else if (d == null)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (d.metrics.detections == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No metrics: nothing was logged in this span.', style: TextStyle(color: t.textDim, fontSize: 13)),
                )
              else
                ...switch (d.mode) {
                  _Mode.detections => _charts(t, d.metrics),
                  _Mode.wardrive => _wardriveCharts(t, d.metrics),
                  _Mode.drones => _droneCharts(t, d.drones!, app, tags),
                },
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _meshSection(ResolvedTheme t, AppState app) {
    final modeEnc = app.meshEnabled && app.meshEncryption;
    final others = app.liveKnownNodes.where((n) => n.isNotEmpty && n != app.nodeId).toList()..sort();
    return [
      const ConfigSectionHeader(label: 'Mesh'),
      ConfigInfoRow(
        icon: Icons.hub,
        label: 'State',
        value: !app.meshEnabled ? 'OFF' : (modeEnc ? 'ENCRYPTED' : 'BROADCAST'),
      ),
      ConfigInfoRow(icon: Icons.swap_vert, label: 'TX / RX', value: '${app.meshTxCount} / ${app.meshRxCount}'),
      if (app.meshKeyFailures case final f?) ConfigInfoRow(icon: Icons.key_off, label: 'Failed key checks', value: '$f'),
      ConfigInfoRow(icon: Icons.sensors, label: 'Nodes heard', value: '${others.length}'),
      for (final id in others) _nodeLine(t, app, id),
    ];
  }

  Widget _nodeLine(ResolvedTheme t, AppState app, String id) {
    final d = app.nodeDetail(id);
    final temp = app.nodeTempC(id);
    final ver = app.nodeFwVersion(id);
    final parts = <String>[
      if (app.nodeBoard(id) case final b? when b.isNotEmpty) b,
      ver == null ? 'build unknown' : 'v$ver',
      if (d != null) ...[filterCountText(d), 'up ${formatUptime(d.uptimeS)}', '${d.peerCount} peers'],
      if (temp != null) '$temp°C',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.labelForNode(id), style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(parts.join('  ·  '), style: TextStyle(color: t.textDim, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _controls(ResolvedTheme t, List<String> nodes, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final m in _Mode.values)
              ChoiceChip(
                label: Text(m.label, style: const TextStyle(fontSize: 11)),
                selected: _mode == m,
                onSelected: (_) {
                  _mode = m;
                  _reload();
                },
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final r in MetricsRange.values)
              ChoiceChip(
                label: Text(r.label, style: const TextStyle(fontSize: 11)),
                selected: _range == r,
                onSelected: (_) {
                  _range = r;
                  _reload();
                },
              ),
          ],
        ),
        if (nodes.isNotEmpty)
          DropdownButton<String?>(
            value: _node,
            isDense: true,
            dropdownColor: t.surface,
            style: TextStyle(color: t.textPrimary, fontSize: 12),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All nodes')),
              for (final n in nodes) DropdownMenuItem<String?>(value: n, child: Text(app.labelForNode(n))),
            ],
            onChanged: (v) {
              _node = v;
              _reload();
            },
          ),
      ],
    );
  }

  List<Widget> _charts(ResolvedTheme t, FleetMetrics m) {
    final change = m.changePercent;
    return [
      Row(
        children: [
          _Kpi(label: 'DETECTIONS', value: '${m.detections}', sub: change == null ? '' : '${change >= 0 ? '+' : ''}$change% vs before'),
          _Kpi(label: 'UNIQUE', value: '${m.unique}', sub: 'devices'),
          _Kpi(label: 'NEW', value: '${m.newDevices}', sub: 'first seen'),
          _Kpi(label: 'NODES', value: '${m.nodesActive}', sub: 'active'),
          _Kpi(label: 'PEAK', value: '${m.peak}', sub: 'per ${_bucketLabel(_range)}'),
        ],
      ),
      _radioLine(t, m),
      _Panel(title: 'OVER TIME', child: _Bars(values: m.series, color: AppTheme.accent, height: 90)),
      if (m.byNode.isNotEmpty) _Panel(title: 'BY NODE', child: _HBars(items: m.byNode)),
      if (m.byVendor.isNotEmpty) _Panel(title: 'BY VENDOR', child: _HBars(items: m.byVendor, suffix: ' dev')),
      if (m.byType.isNotEmpty) _Panel(title: 'BY TYPE', child: _HBars(items: [for (final e in m.byType) (e.$1.replaceAll('_', ' '), e.$2)])),
      _Panel(
        title: 'SIGNAL',
        child: Column(
          children: [
            _Bars(values: m.rssiHist, color: AppTheme.success, height: 70),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < rssiBins; i++)
                  Text('${rssiFloor + i * rssiBinWidth}', style: TextStyle(color: t.textDim, fontSize: 9)),
              ],
            ),
            Text('dBm', style: TextStyle(color: t.textDim, fontSize: 9)),
          ],
        ),
      ),
      _Panel(title: 'WHEN  ·  WEEKDAY × HOUR', child: _Heat(heat: m.heat)),
    ];
  }

  Widget _radioLine(ResolvedTheme t, FleetMetrics m) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('BLE / WIFI  ${m.bleDevices} / ${m.wifiDevices} unique devices',
            style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 1.5, fontFamily: AppTheme.mono)),
      );

  List<Widget> _wardriveCharts(ResolvedTheme t, FleetMetrics m) {
    final bands = <String>[
      if (m.ghz24 > 0) '2.4 GHz ${m.ghz24}',
      if (m.ghz5 > 0) '5 GHz ${m.ghz5}',
    ].join('  ·  ');
    return [
      Row(
        children: [
          _Kpi(label: 'DEVICES', value: '${m.unique}', sub: 'unique'),
          _Kpi(label: 'NEW', value: '${m.newDevices}', sub: 'first seen'),
          _Kpi(label: 'OPEN', value: '${m.openNetworks}', sub: 'networks'),
          _Kpi(label: 'PLACED', value: '${m.placed}', sub: 'with a position'),
          _Kpi(label: 'NODES', value: '${m.nodesActive}', sub: 'active'),
        ],
      ),
      _radioLine(t, m),
      _Panel(
        title: 'DISCOVERED OVER TIME  ·  NEW PER ${_bucketLabel(_range).toUpperCase()}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bars(values: m.newBle, color: AppTheme.accent, height: 90, stack: m.newWifi, stackColor: AppTheme.wardrive),
            const SizedBox(height: 6),
            Row(
              children: [
                _Key(color: AppTheme.accent, label: 'BLE'),
                const SizedBox(width: 12),
                _Key(color: AppTheme.wardrive, label: 'Wi-Fi'),
              ],
            ),
          ],
        ),
      ),
      if (m.security.isNotEmpty) _Panel(title: 'SECURITY', child: _HBars(items: m.security, suffix: ' net')),
      if (m.channels.isNotEmpty)
        _Panel(
          title: 'CHANNELS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bands.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(bands, style: TextStyle(color: t.textDim, fontSize: 10, fontFamily: AppTheme.mono)),
                ),
              _HBars(items: [for (final c in m.channels) ('Ch ${c.$1}', c.$2)], suffix: ' AP'),
            ],
          ),
        ),
      if (m.makers.isNotEmpty) _Panel(title: 'MAKERS', child: _HBars(items: m.makers, suffix: ' dev')),
      if (m.byNode.isNotEmpty) _Panel(title: 'BY NODE', child: _HBars(items: m.byNode)),
    ];
  }

  List<Widget> _droneCharts(ResolvedTheme t, DroneMetrics d, AppState app, Map<String, DroneTag> tags) {
    if (d.reports == 0) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text('No drones: no Remote ID reports were logged in this span.', style: TextStyle(color: t.textDim, fontSize: 13)),
        ),
      ];
    }
    String m(int? v) => v == null ? '-' : '$v m';
    return [
      Row(
        children: [
          _Kpi(label: 'REPORTS', value: '${d.reports}', sub: 'total'),
          _Kpi(label: 'DRONES', value: '${d.drones}', sub: 'unique'),
          _Kpi(label: 'LIVE', value: '${d.live}', sub: 'last ${droneLiveWindow.inSeconds} s'),
        ],
      ),
      Row(
        children: [
          _Kpi(label: 'MAX ALT', value: m(d.maxAlt), sub: 'AGL ${m(d.maxAgl)}'),
          _Kpi(label: 'MAX SPEED', value: d.maxSpeed == null ? '-' : '${d.maxSpeed} m/s', sub: ''),
          _Kpi(label: 'BEST RSSI', value: d.bestRssi == null ? '-' : '${d.bestRssi}', sub: 'dBm'),
        ],
      ),
      _Panel(
        title: 'OVER TIME  ·  REPORTS PER ${_bucketLabel(_range).toUpperCase()}',
        child: _Bars(values: d.series, color: AppTheme.skySpy, height: 90),
      ),
      if (d.byNode.isNotEmpty) _Panel(title: 'BY NODE', child: _HBars(items: d.byNode)),
      _Panel(
        title: 'DRONES',
        child: Column(
          children: [
            for (final s in d.summaries.take(20)) _droneLine(t, app, s, tags[s.id]),
          ],
        ),
      ),
    ];
  }

  Widget _droneLine(ResolvedTheme t, AppState app, DroneSummary s, DroneTag? tag) {
    final alt = s.reports.map((r) => r.alt).whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a);
    final spd = s.reports.map((r) => r.speed).whereType<int>().fold<int?>(null, (a, b) => a == null || b > a ? b : a);
    final node = s.last.node;
    final parts = <String>[
      '${s.reports.length} reports',
      if (alt != null) 'max $alt m',
      if (spd != null) 'max $spd m/s',
      if (node.isNotEmpty) app.labelForNode(node),
      'last ${AppTime.dateTime(s.last.ts)}',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: AppTheme.mono)),
              ),
              if (tag != null) Text(tag.label.toUpperCase(), style: TextStyle(color: tag.color, fontSize: 10, letterSpacing: 1.5)),
              if (s.live) Padding(padding: const EdgeInsets.only(left: 8), child: Text('LIVE', style: TextStyle(color: AppTheme.skySpy, fontSize: 10, letterSpacing: 1.5))),
            ],
          ),
          Text(parts.join('  ·  '), style: TextStyle(color: t.textDim, fontSize: 11)),
        ],
      ),
    );
  }

  String _bucketLabel(MetricsRange r) {
    final b = r.bucket;
    if (b.inDays >= 1) return 'day';
    if (b.inHours >= 1) return '${b.inHours} h';
    return '${b.inMinutes} min';
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.sub});
  final String label;
  final String value;
  final String sub;

  Widget _fit(Widget w) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: w);

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fit(Text(label, maxLines: 1, style: TextStyle(color: t.textDim, fontSize: 9, letterSpacing: 1.5))),
            const SizedBox(height: 2),
            _fit(Text(value, maxLines: 1, style: TextStyle(color: AppTheme.accent, fontFamily: AppTheme.mono, fontSize: 20, fontWeight: FontWeight.bold))),
            _fit(Text(sub, maxLines: 1, style: TextStyle(color: t.textDim, fontSize: 9))),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.color, required this.height, this.stack, this.stackColor});
  final List<int> values;
  final Color color;
  final double height;
  final List<int>? stack;
  final Color? stackColor;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarsPainter(values, color, stack: stack, stackColor: stackColor)));
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.chip))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: t.textDim, fontSize: 10)),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.color, {this.stack, this.stackColor});
  final List<int> values;
  final Color color;
  final List<int>? stack;
  final Color? stackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    int on(int i) => stack != null && i < stack!.length ? stack![i] : 0;
    var top = 0;
    for (var i = 0; i < values.length; i++) {
      top = math.max(top, values[i] + on(i));
    }
    if (top == 0) return;
    final w = size.width / values.length;
    final paint = Paint()..color = color;
    final above = Paint()..color = stackColor ?? color;
    for (var i = 0; i < values.length; i++) {
      final h = size.height * values[i] / top;
      final s = size.height * on(i) / top;
      if (h > 0) canvas.drawRect(Rect.fromLTWH(i * w + 0.5, size.height - h, math.max(1, w - 1), h), paint);
      if (s > 0) canvas.drawRect(Rect.fromLTWH(i * w + 0.5, size.height - h - s, math.max(1, w - 1), s), above);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.color != color || old.stack != stack || old.stackColor != stackColor;
}

class _HBars extends StatelessWidget {
  const _HBars({required this.items, this.suffix = ''});
  final List<(String, int)> items;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final top = items.map((e) => e.$2).reduce(math.max);
    return Column(
      children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(e.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textPrimary, fontSize: 12)),
                ),
                Expanded(
                  flex: 5,
                  child: LayoutBuilder(
                    builder: (ctx, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 8,
                        width: top == 0 ? 0 : c.maxWidth * e.$2 / top,
                        decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(AppRadius.chip)),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text('${e.$2}$suffix', textAlign: TextAlign.right, style: TextStyle(color: t.textSecondary, fontSize: 11, fontFamily: AppTheme.mono)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Heat extends StatelessWidget {
  const _Heat({required this.heat});
  final List<List<int>> heat;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final days = DateFormat.E();
    final top = heat.expand((r) => r).fold<int>(0, math.max);
    return Column(
      children: [
        for (var d = 0; d < 7; d++)
          Row(
            children: [
              SizedBox(width: 32, child: Text(days.format(DateTime(2024, 1, 1 + d)), style: TextStyle(color: t.textDim, fontSize: 9))),
              for (var h = 0; h < 24; h++)
                Expanded(
                  child: Container(
                    height: 14,
                    margin: const EdgeInsets.all(0.5),
                    color: top == 0 || heat[d][h] == 0
                        ? t.border.withValues(alpha: 0.4)
                        : AppTheme.accent.withValues(alpha: 0.2 + 0.8 * heat[d][h] / top),
                  ),
                ),
            ],
          ),
        Row(
          children: [
            const SizedBox(width: 32),
            for (var h = 0; h < 24; h++)
              Expanded(child: Text(h % 6 == 0 ? '$h' : '', style: TextStyle(color: t.textDim, fontSize: 9))),
          ],
        ),
      ],
    );
  }
}
