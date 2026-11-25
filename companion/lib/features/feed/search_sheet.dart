// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/global_search.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/features/alerts/alerts_view.dart' show showAlertSheet;
import 'package:oui_spy/features/devices/devices_screen.dart' show DeviceDetailSheet;
import 'package:oui_spy/features/feed/detection_row.dart'
    show detectionHeadline, methodLabel, showDetectionDetails;
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';

String _ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

List<SearchEntry> buildSearchEntries(WidgetRef ref, {List<Detection> history = const []}) {
  final app = ref.read(appStateProvider);
  final oui = ref.read(ouiLookupProvider);
  final notes = ref.read(deviceNotesProvider);
  final out = <SearchEntry>[];
  final seen = <String>{};
  final macs = <String>{};
  for (final d in [...app.recentDetections, ...history]) {
    if (!seen.add(app.dedupeKey(d))) continue;
    final key = MacUtil.normalize(d.macAddress);
    macs.add(key);
    final note = notes[DeviceNotesNotifier.keyOf(d.macAddress)];
    final vendor = oui.lookup(d.macAddress);
    final node = d.sourceNodeId.isEmpty ? '' : app.labelForNode(d.sourceNodeId);
    final area = switch (d.engine) {
      Engine.skySpy => SearchArea.drones,
      Engine.wardrive => SearchArea.wardrive,
      _ => SearchArea.devices,
    };
    out.add(SearchEntry(
      area: area,
      title: detectionHeadline(d),
      subtitle: [
        if (d.engine == Engine.detector || d.engine == Engine.wardrive) methodLabel(d.method) else d.engine.label,
        d.macAddress.toUpperCase(),
        if (node.isNotEmpty) node,
      ].join(' · '),
      haystack: [
        d.macAddress,
        d.deviceName,
        d.ssid,
        d.method,
        methodLabel(d.method),
        d.sourceNodeId,
        node,
        vendor,
        d.engine.label,
        d.odid?.uavId,
        d.odid?.operatorId,
        d.detector?.filterDescription,
        note?.name,
        note?.group,
        note?.notes,
      ],
      payload: d,
      atMs: d.appTimestamp.millisecondsSinceEpoch,
    ));
  }
  if (ref.exists(deviceRegistryProvider)) {
    for (final dev in ref.read(deviceRegistryProvider).devices) {
      final o = dev.obs;
      if (o.mac.isNotEmpty && macs.contains(MacUtil.normalize(o.mac))) continue;
      final title = DeviceExplain.title(dev.guess);
      out.add(SearchEntry(
        area: SearchArea.devices,
        title: title,
        subtitle: [if (o.mac.isNotEmpty) o.mac.toUpperCase(), if (dev.vendor != null) dev.vendor!].join(' · '),
        haystack: [o.mac, o.name, dev.vendor, title, ...dev.signatureNames, dev.guess.headline],
        payload: dev,
        atMs: o.lastSeenMs,
      ));
    }
  }
  for (final r in ref.read(alertsFeedProvider).rows) {
    final kind = r['alertClass'] as String?;
    out.add(SearchEntry(
      area: SearchArea.alerts,
      title: r['deviceName'] as String? ?? '',
      subtitle: [alertKindLabel(kind), r['detectionMethod'] as String? ?? ''].where((s) => s.isNotEmpty).join(' · '),
      haystack: [r['deviceName'], r['macAddress'], r['detectionMethod'], r['ssid'], alertKindLabel(kind)],
      payload: r,
      atMs: r['appTimestamp'] as int? ?? 0,
    ));
  }
  final live = app.liveKnownNodes;
  for (final id in app.knownNodes) {
    final label = app.labelForNode(id);
    final board = app.nodeBoard(id) ?? '';
    final fw = app.nodeFwVersion(id) ?? '';
    out.add(SearchEntry(
      area: SearchArea.nodes,
      title: label,
      subtitle: [live.contains(id) ? 'online' : 'offline', id, if (board.isNotEmpty) board, if (fw.isNotEmpty) 'v$fw']
          .join(' · '),
      haystack: [label, id, board, fw, live.contains(id) ? 'online' : 'offline'],
      payload: id,
      atMs: live.contains(id) ? DateTime.now().millisecondsSinceEpoch : 0,
    ));
  }
  return out;
}

Future<void> showSearchResults(
  BuildContext context,
  WidgetRef ref,
  SearchResults results, {
  SearchArea? area,
}) {
  return showCommandSheet<void>(
    context: context,
    builder: (ctx) => _SearchResultsSheet(host: context, ref: ref, results: results, initial: area),
  );
}

class _SearchResultsSheet extends StatefulWidget {
  const _SearchResultsSheet({required this.host, required this.ref, required this.results, this.initial});

  final BuildContext host;
  final WidgetRef ref;
  final SearchResults results;
  final SearchArea? initial;

  @override
  State<_SearchResultsSheet> createState() => _SearchResultsSheetState();
}

class _SearchResultsSheetState extends State<_SearchResultsSheet> {
  late SearchArea? _area = widget.initial;

  void _open(SearchEntry e) {
    final host = widget.host;
    final ref = widget.ref;
    Navigator.of(context).pop();
    final p = e.payload;
    if (p is Detection) {
      showDetectionDetails(host, ref, p);
    } else if (p is ClassifiedDevice) {
      showCommandSheet<void>(context: host, builder: (_) => DeviceDetailSheet(device: p, vendor: p.vendor));
    } else if (p is Map<String, dynamic>) {
      showAlertSheet(host, ref, p, ref.read(privacyScreenProvider));
    } else if (p is String) {
      _showNode(host, ref, p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final r = widget.results;
    final shown = [for (final a in r.areas) if (_area == null || _area == a) a];
    return CommandSheet(
      title: 'SEARCH · "${r.query}"',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CommandChip(
                key: const Key('search-chip-all'),
                label: 'EVERYTHING',
                count: r.total,
                selected: _area == null,
                color: AppTheme.accent,
                onTap: () => setState(() => _area = null),
              ),
              for (final a in r.areas)
                CommandChip(
                  key: Key('search-chip-${a.name}'),
                  label: a.label.toUpperCase(),
                  count: r.totals[a],
                  selected: _area == a,
                  color: AppTheme.accent,
                  onTap: () => setState(() => _area = _area == a ? null : a),
                ),
            ],
          ),
          if (r.total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Nothing matches "${r.query}"',
                  textAlign: TextAlign.center, style: TextStyle(color: t.textDim)),
            ),
          for (final a in shown) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                '${a.label.toUpperCase()} · ${r.totals[a]}${r.totals[a]! > (r.byArea[a]?.length ?? 0) ? ' (showing ${r.byArea[a]!.length})' : ''}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.textSecondary),
              ),
            ),
            for (final e in r.byArea[a]!)
              ListTile(
                key: ValueKey('search-hit-${e.area.name}-${e.title}-${e.subtitle}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  e.atMs > 0 && a != SearchArea.nodes ? '${e.subtitle} · ${_ago(e.atMs)}' : e.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textDim, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right, color: t.textDim),
                onTap: () => _open(e),
              ),
          ],
        ],
      ),
    );
  }
}

void _showNode(BuildContext context, WidgetRef ref, String id) {
  final app = ref.read(appStateProvider);
  final t = AppTheme.of(context);
  final online = app.liveKnownNodes.contains(id);
  final board = app.nodeBoard(id);
  final fw = app.nodeFwVersion(id);
  final temp = app.nodeTempC(id);
  Widget line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 84, child: Text(label, style: TextStyle(color: t.textDim, fontSize: 12))),
            Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
  showCommandSheet<void>(
    context: context,
    builder: (ctx) => CommandSheet(
      title: 'NODE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(app.labelForNode(id), style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          line('Status', online ? 'Online' : 'Offline'),
          line('ID', id),
          if (board != null && board.isNotEmpty) line('Board', board),
          if (fw != null) line('Firmware', fw),
          if (temp != null) line('Temperature', '$temp °C'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Open fleet settings'),
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/config');
            },
          ),
        ],
      ),
    ),
  );
}
