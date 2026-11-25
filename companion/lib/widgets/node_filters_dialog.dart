// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/node_filters.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/features/engines/rule_picker.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Sends a filter edit to the connected manager; false when no board is connected.
typedef NodeFilterSender = Future<bool> Function(Uint8List op);

/// Sends [op] with [data] to every node in [ids], or to every node when [ids] is null, and waits for the answers.
/// Null when no board is connected or nothing answered. Nodes are asked one at a time so each answer is told apart.
Future<List<MeshFilterOp>> sendFilterEdit(
  AppState app,
  NodeFilterSender send,
  Iterable<String>? ids,
  int op, [
  List<int> data = const [],
]) async {
  final out = <MeshFilterOp>[];
  final targets = <String?>[...?ids];
  if (ids == null) targets.add(null);
  for (final id in targets) {
    final prev = app.filterOpSeq;
    if (!await send(BleProtocol.encodeNodeFilterOp(id, op, data))) return out;
    final res = await app.waitForFilterOp(prev);
    if (res != null) out.add(res);
  }
  return out;
}

/// The dialog behind a node's FILTERS button: read what it watches for, add or remove a rule, install a
/// preset, replace its list with this phone's watchlist, or clear it.
Future<void> showNodeFiltersDialog(
  BuildContext context,
  AppState app,
  String nodeId, {
  required NodeFilterSender send,
  required List<WatchlistEntry> Function() phoneList,
}) {
  final id = AppState.canonicalNodeId(nodeId);
  return showDialog<void>(
    context: context,
    builder: (_) => _NodeFilters(app: app, id: id, send: send, phoneList: phoneList),
  );
}

class _NodeFilters extends StatefulWidget {
  const _NodeFilters({required this.app, required this.id, required this.send, required this.phoneList});
  final AppState app;
  final String id;
  final NodeFilterSender send;
  final List<WatchlistEntry> Function() phoneList;

  @override
  State<_NodeFilters> createState() => _NodeFiltersState();
}

class _NodeFiltersState extends State<_NodeFilters> {
  var busy = false;
  String status = 'Read the node to see what it watches for.';
  List<NodeFilterRow>? rows;

  AppState get app => widget.app;

  void say(String s) {
    if (mounted) setState(() => status = s);
  }

  Future<MeshFilterOp?> edit(int op, [List<int> data = const []]) async {
    final prev = app.filterOpSeq;
    if (!await widget.send(BleProtocol.encodeNodeFilterOp(widget.id, op, data))) {
      say('Not connected to a board');
      return null;
    }
    final res = await app.waitForFilterOp(prev);
    if (res == null) say('No answer. A node on older firmware does not answer filter edits.');
    return res;
  }

  NodeFilterResult? mine(MeshFilterOp op) {
    for (final r in op.results) {
      if (AppState.canonicalNodeId(r.id) == widget.id) return r;
    }
    return null;
  }

  Future<void> guarded(Future<void> Function() body) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> read({String? prefix}) async {
    final res = await edit(BleProtocol.filterOpGet);
    if (res == null) return;
    final r = mine(res);
    if (r == null) return say('No answer from ${app.labelForNode(widget.id)}.');
    if (r.status != 0) return say('${prefix ?? ''}Refused: ${filterOpRefusalText(r.status)}');
    final report = await app.waitForNodeFilterReport(widget.id, res.seq);
    if (!mounted) return;
    setState(() {
      rows = report?.rows;
      final part = report != null && !report.complete ? ' Some pages did not arrive; read again.' : '';
      status = '${prefix ?? ''}${nodeFilterOpText(r, BleProtocol.filterOpGet)}.$part';
    });
  }

  Future<void> add() async {
    final e = await showRulePicker(context);
    if (e == null) return;
    final rec = filterRecordOf(e);
    if (rec == null) return say('That rule cannot go on a node.');
    await guarded(() async {
      final res = await edit(BleProtocol.filterOpAdd, rec);
      final r = res == null ? null : mine(res);
      if (r != null) await read(prefix: 'Add: ${nodeFilterOpText(r, BleProtocol.filterOpAdd)}. ');
    });
  }

  Future<void> remove(NodeFilterRow row) => guarded(() async {
        final res = await edit(BleProtocol.filterOpDel, row.record);
        final r = res == null ? null : mine(res);
        if (r != null) await read(prefix: 'Remove: ${nodeFilterOpText(r, BleProtocol.filterOpDel)}. ');
      });

  Future<void> install(DetectorPreset p) => guarded(() async {
        final res = await edit(BleProtocol.filterOpPreset, [p.id]);
        final r = res == null ? null : mine(res);
        if (r != null) await read(prefix: '${p.name}: ${nodeFilterOpText(r, BleProtocol.filterOpPreset)}. ');
      });

  Future<bool> confirm(String title, String body, String action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> clear() async {
    final label = app.labelForNode(widget.id);
    if (!await confirm('Clear $label?', 'It stops watching for everything until you add rules or a preset.', 'CLEAR')) return;
    await guarded(() async {
      final res = await edit(BleProtocol.filterOpClear);
      final r = res == null ? null : mine(res);
      if (r != null) await read(prefix: 'Clear: ${nodeFilterOpText(r, BleProtocol.filterOpClear)}. ');
    });
  }

  Future<void> replace() async {
    final records = [
      for (final e in widget.phoneList())
        if (e.enabled) ?filterRecordOf(e),
    ];
    final label = app.labelForNode(widget.id);
    if (!await confirm('Replace $label\'s filters?',
        'Its list becomes the ${records.length} rules on this phone\'s watchlist that a node can match.', 'REPLACE')) {
      return;
    }
    await guarded(() async {
      final cleared = await edit(BleProtocol.filterOpClear);
      if (cleared == null) return;
      MeshFilterOp? last;
      for (final pack in packFilterRecords(records)) {
        last = await edit(BleProtocol.filterOpAdd, pack);
        if (last == null) return;
      }
      final r = last == null ? mine(cleared) : mine(last);
      final skipped = r?.skipped ?? 0;
      await read(
          prefix: 'Replaced with ${records.length} rules${skipped > 0 ? ', $skipped skipped' : ''}. ');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final label = app.labelForNode(widget.id);
    return AlertDialog(
      scrollable: true,
      title: Text('Filters on $label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.4)),
          if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ConfigCompactButton(
                    icon: Icons.fact_check_outlined, label: 'Read', onTap: busy ? null : () => guarded(read)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ConfigCompactButton(icon: Icons.add, label: 'Add a rule', onTap: busy ? null : add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ConfigCompactButton(
                    icon: Icons.sync_alt, label: 'Replace', onTap: busy ? null : replace),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ConfigCompactButton(
                    icon: Icons.delete_sweep_outlined, label: 'Clear', destructive: true, onTap: busy ? null : clear),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const ConfigSectionHeader(label: 'Presets'),
          for (final p in detectorPresets)
            ConfigActionRow(
              icon: Icons.playlist_add,
              label: p.name,
              subtitle: '${p.rows.length} rows${p.wifiRows > 0 ? ' · ${p.wifiRows} need Wi-Fi' : ''}',
              onTap: busy ? null : () => install(p),
            ),
          if (rows != null) ...[
            const SizedBox(height: 8),
            ConfigSectionHeader(label: 'On the node (${rows!.length})'),
            if (rows!.isEmpty) Text('Nothing.', style: TextStyle(color: t.textDim, fontSize: 13)),
            for (final r in rows!) _RowTile(row: r, onRemove: busy ? null : () => remove(r)),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE'))],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.onRemove});
  final NodeFilterRow row;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final e = row.entry!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.identifier, style: TextStyle(color: t.textPrimary, fontSize: 13, fontFamily: AppTheme.mono)),
              Text(e.matchType.title, style: TextStyle(color: t.textDim, fontSize: 11)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Remove from the node',
          onPressed: onRemove,
        ),
      ],
    );
  }
}
