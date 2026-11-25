// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/db/app_database.dart' show databaseProvider;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/export/device_export.dart';
import 'package:oui_spy/core/export/kmz.dart';
import 'package:oui_spy/core/mesh_node_info.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showDeviceNotesEditor(BuildContext context, WidgetRef ref, String mac) async {
  final current = ref.read(deviceNotesProvider)[DeviceNotesNotifier.keyOf(mac)] ?? const DeviceNote();
  final groups = ref.read(deviceNotesProvider.notifier).groups;
  final saved = await showDialog<DeviceNote>(
    context: context,
    builder: (_) => _DeviceNotesDialog(mac: mac, current: current, groups: groups),
  );
  if (saved != null) await ref.read(deviceNotesProvider.notifier).set(mac, saved);
}

class _DeviceNotesDialog extends StatefulWidget {
  const _DeviceNotesDialog({required this.mac, required this.current, required this.groups});
  final String mac;
  final DeviceNote current;
  final List<String> groups;

  @override
  State<_DeviceNotesDialog> createState() => _DeviceNotesDialogState();
}

class _DeviceNotesDialogState extends State<_DeviceNotesDialog> {
  late final _name = TextEditingController(text: widget.current.name);
  late final _group = TextEditingController(text: widget.current.group);
  late final _notes = TextEditingController(text: widget.current.notes);

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name & notes'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: InputDecoration(labelText: 'Your name for it', helperText: widget.mac.toUpperCase()),
            ),
            TextField(
              controller: _group,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Group'),
            ),
            if (widget.groups.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final g in widget.groups) ActionChip(label: Text(g), onPressed: () => _group.text = g),
                ],
              ),
            TextField(
              controller: _notes,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        if (!widget.current.isEmpty)
          TextButton(onPressed: () => Navigator.pop(context, const DeviceNote()), child: const Text('CLEAR')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            DeviceNote(name: _name.text.trim(), group: _group.text.trim(), notes: _notes.text.trim()),
          ),
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

String watchMacKey(String mac) {
  final hex = mac.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length != 12) return '';
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
}

bool isWatchedMac(List<WatchlistEntry> entries, String mac) {
  final key = watchMacKey(mac);
  return key.isNotEmpty && entries.any((e) => e.isFullMac && e.identifier.toUpperCase() == key);
}

/// Adds the device to the watchlist by its exact MAC; the board and its mesh nodes then report it.
Future<void> flagDeviceAsDetection(BuildContext context, WidgetRef ref, String mac, String label) async {
  final key = watchMacKey(mac);
  if (key.isEmpty) return;
  final entry = WatchlistEntry(
    identifier: key,
    matchType: WatchlistMatchType.fullMac,
    description: label.length > 31 ? label.substring(0, 31) : label,
  );
  final list = ref.read(watchlistProvider);
  final app = ref.read(appStateProvider);
  final prevSeq = app.filterPushSeq;
  final self = AppState.canonicalNodeId(app.nodeId);
  final track = app.isManagerConnected && app.liveKnownNodes.any((n) => n != self && !app.isManagerNode(n));
  await list.add(entry);
  if (!context.mounted) return;
  final random = int.parse(key.substring(0, 2), radix: 16) & 0x02 != 0;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final undo = SnackBarAction(label: 'UNDO', onPressed: () => list.remove(entry));
  messenger?.showSnackBar(SnackBar(
    content: Text(random
        ? 'Watching $key on the board and its mesh nodes. This address is random, so the device may change it'
        : 'Watching $key on the board and its mesh nodes'),
    action: undo,
  ));
  if (!track) return;
  final push = await app.waitForFilterPush(prevSeq);
  if (!context.mounted) return;
  final summary = push == null ? 'No node has confirmed the update yet' : filterPushSummary(push, app.labelForNode);
  if (summary == null) return;
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text('Watchlist update: $summary'), action: undo));
}

Future<void> showDeviceExport(BuildContext context, WidgetRef ref, String mac) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Export every sighting of this device')),
          for (final (f, label) in const [
            ('csv', 'CSV'),
            ('json', 'JSON, with your name, group and notes'),
            ('kml', 'KML, for Google Earth and ATAK'),
            ('kmz', 'KMZ, zipped KML'),
          ])
            ListTile(title: Text(label), onTap: () => Navigator.pop(ctx, f)),
        ],
      ),
    ),
  );
  if (format == null) return;
  final maps = await ref.read(databaseProvider).getDetectionMapsForMac(mac);
  final rows = maps.map(detectionFromDbRow).toList();
  if (!context.mounted) return;
  if (rows.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('No saved sightings of this device yet')),
    );
    return;
  }
  final note = ref.read(deviceNotesProvider)[DeviceNotesNotifier.keyOf(mac)] ?? const DeviceNote();
  final title = note.name.isNotEmpty ? note.name : mac.toUpperCase();
  final base = 'oui_spy_${mac.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase()}';
  final Object content = switch (format) {
    'csv' => DeviceExport.csv(rows),
    'json' => DeviceExport.json(rows, name: note.name, group: note.group, notes: note.notes),
    'kml' => DeviceExport.kml(rows, title: title),
    _ => kmzFromKml(DeviceExport.kml(rows, title: title)),
  };
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$base.$format');
  if (content is Uint8List) {
    await file.writeAsBytes(content);
  } else {
    await file.writeAsString(content as String);
  }
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    subject: 'OUI-SPY device $title',
    sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
  ));
}
