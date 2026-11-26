// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/node_filters.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/info_sheet.dart';
import 'package:oui_spy/widgets/node_filters_dialog.dart';

/// The signature presets: watch one on this phone, or install it on the nodes you pick.
class PresetsPanel extends ConsumerWidget {
  const PresetsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PRESETS',
                  style: TextStyle(color: AppTheme.detector, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: t.textSecondary),
                tooltip: 'About presets',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => showInfoSheet(context, t, 'Presets', const [
                  'Signature sets for common gear.',
                  'Tap one to watch it on this phone or install it on nodes.',
                ]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in detectorPresets)
                ActionChip(
                  label: Text(p.name, style: TextStyle(color: AppTheme.detector, fontSize: 12)),
                  backgroundColor: AppTheme.detector.withValues(alpha: 0.1),
                  side: BorderSide(color: AppTheme.detector.withValues(alpha: 0.3)),
                  onPressed: () => showDialog<void>(context: context, builder: (_) => PresetDialog(preset: p)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class PresetDialog extends ConsumerWidget {
  const PresetDialog({super.key, required this.preset});
  final DetectorPreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      scrollable: true,
      title: Text(preset.name, style: TextStyle(color: t.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(preset.about, style: TextStyle(color: t.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            '${preset.rows.length} rows'
            '${preset.wifiRows > 0 ? ', ${preset.wifiRows} of them Wi-Fi. A node set to Bluetooth only skips those; a preset with nothing it can match is refused.' : '.'}',
            style: TextStyle(color: t.textDim, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'On this phone the rows join the watchlist, and a board or manager takes the whole list. '
            'On nodes the preset adds to what a node already watches for and keeps it until the phone sends a new watchlist.',
            style: TextStyle(color: t.textDim, fontSize: 12, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
        TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final nav = Navigator.of(context);
            final r = await watchPreset(ref.read(watchlistProvider), preset);
            nav.pop();
            messenger.showSnackBar(SnackBar(
              content: Text('${preset.name}: added ${r.added}, ${r.skipped} already on the watchlist'),
            ));
          },
          child: const Text('WATCH ON PHONE'),
        ),
        TextButton(
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            showDialog<void>(context: nav.context, builder: (_) => InstallOnNodesDialog(preset: preset));
          },
          child: const Text('INSTALL ON NODES'),
        ),
      ],
    );
  }
}

/// Adds the preset's rows to the watchlist, skipping rows already on it.
Future<({int added, int skipped})> watchPreset(WatchlistState wl, DetectorPreset p) async {
  final have = wl.entries.map(watchlistKey).toSet();
  var added = 0, skipped = 0;
  for (final r in p.rows) {
    final id = normalizeWatchlistId(r.identifier, r.type);
    if (id == null) continue;
    final e = WatchlistEntry(identifier: id, matchType: r.type, description: r.description);
    if (!have.add(watchlistKey(e))) {
      skipped++;
      continue;
    }
    await wl.add(e);
    added++;
  }
  return (added: added, skipped: skipped);
}

class InstallOnNodesDialog extends ConsumerStatefulWidget {
  const InstallOnNodesDialog({super.key, required this.preset});
  final DetectorPreset preset;

  @override
  ConsumerState<InstallOnNodesDialog> createState() => _InstallOnNodesDialogState();
}

class _InstallOnNodesDialogState extends ConsumerState<InstallOnNodesDialog> {
  var all = true;
  final picked = <String>{};
  var busy = false;

  List<String> nodes(AppState app) => [
        for (final id in app.liveKnownNodes)
          if (id != app.nodeId && !app.isManagerNode(id)) id,
      ]..sort();

  Future<void> install(AppState app, BleManager ble) async {
    setState(() => busy = true);
    final ops = await sendFilterEdit(
      app,
      ble.sendNodeFilterOp,
      all ? null : picked,
      BleProtocol.filterOpPreset,
      [widget.preset.id],
    );
    if (!mounted) return;
    final lines = [
      for (final op in ops) ?filterOpSummary(op, app.labelForNode),
    ];
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(ops.isEmpty
          ? 'No answer. A node on older firmware does not answer presets.'
          : '${widget.preset.name}: ${lines.join('; ')}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final app = ref.watch(appStateProvider);
    final ble = ref.read(bleManagerProvider);
    final ids = nodes(app);
    final ready = app.isManagerConnected && ids.isNotEmpty;
    return AlertDialog(
      backgroundColor: t.surface,
      scrollable: true,
      title: Text('Install ${widget.preset.name}', style: TextStyle(color: t.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!app.isManagerConnected)
            Text('Connect to a manager to install on nodes.', style: TextStyle(color: t.textDim, fontSize: 13))
          else if (ids.isEmpty)
            Text('No node is online.', style: TextStyle(color: t.textDim, fontSize: 13))
          else ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('All nodes', style: TextStyle(color: t.textPrimary, fontSize: 14)),
              value: all,
              onChanged: busy ? null : (v) => setState(() => all = v ?? true),
            ),
            if (!all)
              for (final id in ids)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(app.labelForNode(id), style: TextStyle(color: t.textPrimary, fontSize: 14)),
                  subtitle: Text(id, style: TextStyle(color: t.textDim, fontSize: 11, fontFamily: AppTheme.mono)),
                  value: picked.contains(id),
                  onChanged: busy ? null : (v) => setState(() => v == true ? picked.add(id) : picked.remove(id)),
                ),
          ],
          if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        ],
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(
          onPressed: busy || !ready || (!all && picked.isEmpty) ? null : () => install(app, ble),
          child: const Text('INSTALL'),
        ),
      ],
    );
  }
}
