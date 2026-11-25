// Copyright (c) 2026 Luke Switzer
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble_sniff.dart';
import 'package:oui_spy/core/ble_sniff_state.dart';
import 'package:oui_spy/core/engine_control.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

class BleSniffScreen extends ConsumerStatefulWidget {
  const BleSniffScreen({super.key});

  @override
  ConsumerState<BleSniffScreen> createState() => _BleSniffScreenState();
}

class _BleSniffScreenState extends ConsumerState<BleSniffScreen> {
  String? _targetNode;
  bool _busy = false;

  String? _resolveTarget(AppState app) {
    if (!app.isManagerConnected) return null;
    if (_targetNode != null && app.liveKnownNodes.contains(_targetNode)) return _targetNode;
    final nodes = app.liveKnownNodes.where((id) => id != app.nodeId).toList();
    return nodes.isEmpty ? null : nodes.first;
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    final app = ref.read(appStateProvider);
    final target = _resolveTarget(app);
    if (app.isManagerConnected && target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No live node to sniff on')));
      return;
    }
    setState(() {
      _busy = true;
      _targetNode = target;
    });
    try {
      final sniff = ref.read(bleSniffProvider);
      if (on) {
        await sniff.pushFilter(targetNodeId: target);
        if (!mounted) return;
      }
      await setEngineEnabled(ref, Engine.bleSniff, on, targetNodeId: target);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('BLE Sniff ${on ? "start" : "stop"} failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(File f) async {
    if (!await f.exists()) return;
    final size = await f.length();
    if (!mounted) return;
    final s = MediaQuery.of(context).size;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/vnd.tcpdump.pcap')],
      subject: 'OUI-SPY BLE Sniff ($size bytes)',
      sharePositionOrigin: Rect.fromLTWH(s.width / 2 - 1, s.height / 2 - 1, 2, 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final app = ref.watch(appStateProvider);
    final sniff = ref.watch(bleSniffProvider);
    final ble = ref.watch(bleManagerProvider);
    final active = app.isEngineActive(Engine.bleSniff);
    final target = _resolveTarget(app);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('BLE SNIFF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showInfoSheet(context, t, 'BLE Sniff', const [
              'Listens passively for every Bluetooth LE advertisement and lists each one as it arrives, repeats included. It never sends a scan request.',
              'Each row shows the advert type, address kind, signal, name, services and manufacturer.',
              'Record PCAP saves what you see as a Wireshark file on the phone. Open it in Wireshark as Bluetooth LE.',
              'The filters choose which advert types and address kinds the board passes on. The signal channel is not reported by the radio, so Wireshark shows channel 37 for every frame.',
              'Stop PCAP capture first: the PCAP engine and BLE Sniff share the Bluetooth radio.',
            ]),
          ),
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: active,
              onChanged: (app.isConnected && !_busy) ? _toggle : null,
              activeTrackColor: Engine.bleSniff.color.withValues(alpha: 0.3),
              activeThumbColor: Engine.bleSniff.color,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear list',
            onPressed: sniff.clear,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (app.isManagerConnected) ...[
            _NodeCard(
              selected: target,
              enabled: !active && !_busy,
              onChanged: (id) => setState(() => _targetNode = id),
            ),
            const SizedBox(height: 12),
          ],
          StreamBuilder<PcapStats>(
            stream: ble.bleSniffStats,
            initialData: ble.latestBleSniffStats,
            builder: (context, snap) => _StatsCard(
              stats: snap.data ?? PcapStats.empty,
              active: active,
              perSecond: sniff.perSecond,
              received: sniff.received,
            ),
          ),
          const SizedBox(height: 12),
          _FilterCard(
            mask: sniff.filter,
            onChanged: (m) => sniff.setFilter(m, targetNodeId: target),
          ),
          const SizedBox(height: 12),
          _RecordCard(sniff: sniff, onShare: _share),
          const SizedBox(height: 12),
          _ListHeader(sniff: sniff, t: t),
          const SizedBox(height: 4),
          if (sniff.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  active ? 'Waiting for adverts…' : 'Turn BLE Sniff on to start listening.',
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                ),
              ),
            )
          else
            for (final a in sniff.rows.take(150)) _AdvertRow(advert: a, t: t),
        ],
      ),
    );
  }
}

BoxDecoration _box(ResolvedTheme t) => BoxDecoration(
      color: t.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: t.border),
    );

class _NodeCard extends ConsumerWidget {
  const _NodeCard({required this.selected, required this.enabled, required this.onChanged});
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final t = AppTheme.of(context);
    final nodes = app.liveKnownNodes.where((id) => id != app.nodeId).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lan, color: AppTheme.accent, size: 18),
            const SizedBox(width: 10),
            Text('SNIFF NODE',
                style: TextStyle(
                    color: AppTheme.accent, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          if (nodes.isEmpty)
            Text('No live nodes yet — wait for nodes to report in.',
                style: TextStyle(color: t.textSecondary, fontSize: 11))
          else
            DropdownButton<String>(
              value: nodes.contains(selected) ? selected : null,
              hint: Text('Select a node', style: TextStyle(color: t.textDim, fontSize: 13)),
              isExpanded: true,
              dropdownColor: t.surface,
              underline: const SizedBox.shrink(),
              items: [
                for (final id in nodes)
                  DropdownMenuItem(
                    value: id,
                    child: Text('${app.labelForNode(id)}  ·  $id', style: TextStyle(color: t.textPrimary)),
                  ),
              ],
              onChanged: enabled ? onChanged : null,
            ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.active, required this.perSecond, required this.received});
  final PcapStats stats;
  final bool active;
  final int perSecond;
  final int received;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final total = stats.bleAdvCount + stats.bleScanCount;
    final up = stats.uptimeMs ~/ 1000;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: _box(t),
      child: Row(
        children: [
          _Stat(label: 'ADVERTS', value: active && total > 0 ? total : received, color: Engine.bleSniff.color),
          _Stat(label: 'PER SECOND', value: perSecond, color: t.textPrimary),
          _Stat(label: 'DROPPED', value: stats.droppedFrames, color: stats.droppedFrames > 0 ? AppTheme.warning : t.textPrimary),
          _Stat(label: 'UPTIME S', value: active ? up : 0, color: t.textPrimary),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  static String _fmt(int v) {
    if (v < 1000) return '$v';
    if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '${(v / 1000000).toStringAsFixed(2)}M';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: t.textDim, fontSize: 9, letterSpacing: 1.5)),
            const SizedBox(height: 2),
            Text(_fmt(value),
                style: TextStyle(color: color, fontFamily: AppTheme.mono, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.mask, required this.onChanged});
  final int mask;
  final ValueChanged<int> onChanged;

  static const _bits = <(int, String)>[
    (sniffFtAdvInd, 'Connectable'),
    (sniffFtAdvDirect, 'Directed'),
    (sniffFtAdvNonconn, 'Non-connectable'),
    (sniffFtAdvScanInd, 'Scannable'),
    (sniffFtScanRsp, 'Scan response'),
    (sniffFtAddrPublic, 'Public address'),
    (sniffFtAddrRandom, 'Random address'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PASS THESE ADVERTS',
              style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (bit, label) in _bits)
                FilterChip(
                  label: Text(label),
                  selected: mask & bit != 0,
                  onSelected: (on) => onChanged(on ? mask | bit : mask & ~bit),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.sniff, required this.onShare});
  final BleSniffState sniff;
  final Future<void> Function(File) onShare;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final rec = sniff.recording;
    final last = sniff.lastSaved;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => rec ? sniff.stopRecording() : sniff.startRecording(),
            icon: Icon(rec ? Icons.stop : Icons.fiber_manual_record),
            label: Text(rec ? 'STOP AND SAVE PCAP' : 'RECORD PCAP'),
            style: OutlinedButton.styleFrom(
              foregroundColor: rec ? AppTheme.error : AppTheme.success,
              side: BorderSide(color: rec ? AppTheme.error : AppTheme.success),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (rec) ...[
            const SizedBox(height: 8),
            Text('${sniff.recordedFrames} frames · ${_humanBytes(sniff.recordedBytes)}',
                style: TextStyle(color: t.textSecondary, fontSize: 12, fontFamily: AppTheme.mono)),
          ],
          if (!rec && last != null) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => onShare(last),
              icon: const Icon(Icons.ios_share),
              label: const Text('SHARE LAST PCAP'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ],
      ),
    );
  }
}

String _humanBytes(int n) {
  if (n < 1024) return '${n}B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
  return '${(n / 1024 / 1024).toStringAsFixed(2)}MB';
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.sniff, required this.t});
  final BleSniffState sniff;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('LIVE ADVERTS',
              style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
        ),
        TextButton.icon(
          onPressed: sniff.togglePause,
          icon: Icon(sniff.paused ? Icons.play_arrow : Icons.pause, size: 18),
          label: Text(sniff.paused ? 'RESUME LIST' : 'PAUSE LIST'),
        ),
      ],
    );
  }
}

class _AdvertRow extends StatelessWidget {
  const _AdvertRow({required this.advert, required this.t});
  final SniffAdvert advert;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final a = advert;
    final detail = [
      if (a.servicesLabel.isNotEmpty) 'services ${a.servicesLabel}',
      if (a.mfrLabel.isNotEmpty) 'maker ${a.mfrLabel}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _box(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.macStr,
                    style: TextStyle(color: t.textPrimary, fontFamily: AppTheme.mono, fontSize: 13)),
              ),
              Text('${a.rssi} dBm',
                  style: TextStyle(color: Engine.bleSniff.color, fontFamily: AppTheme.mono, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${a.llName} · ${a.addrClass == 'pub' ? 'public address' : 'random address (${a.addrClass})'}'
            '${a.name.isEmpty ? '' : ' · "${a.name}"'}',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
          if (detail.isNotEmpty)
            Text(detail, style: TextStyle(color: t.textDim, fontSize: 11)),
        ],
      ),
    );
  }
}
