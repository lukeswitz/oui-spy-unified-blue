// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:oui_spy/core/offline/offline_maps.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

class SavedMapAreasSection extends StatefulWidget {
  const SavedMapAreasSection({super.key, this.storeOpener = openOfflineStore});

  final Future<OfflineStore> Function() storeOpener;

  @override
  State<SavedMapAreasSection> createState() => _SavedMapAreasSectionState();
}

class _SavedMapAreasSectionState extends State<SavedMapAreasSection> {
  List<OfflineArea>? _areas;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final areas = await (await widget.storeOpener()).areas();
      if (mounted) setState(() => _areas = areas);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _delete(OfflineArea a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved map area'),
        content: Text('Removes ${a.styleLabel}, zoom ${a.minZoom} to ${a.maxZoom} (${offlineSizeLabel(a.bytes)}) from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (await widget.storeOpener()).delete(a);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final areas = _areas;
    if (_error != null) {
      return ConfigInfoRow(icon: Icons.map_outlined, label: 'Saved map areas', value: _error!, monospace: false);
    }
    if (areas == null) {
      return const ConfigInfoRow(icon: Icons.map_outlined, label: 'Saved map areas', value: '...', monospace: false);
    }
    if (areas.isEmpty) {
      return const ConfigInfoRow(icon: Icons.map_outlined, label: 'Saved map areas', value: 'None', monospace: false);
    }
    final total = areas.fold<int>(0, (n, a) => n + a.bytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigInfoRow(
          icon: Icons.map_outlined,
          label: 'Saved map areas',
          value: '${areas.length} using ${offlineSizeLabel(total)}',
          monospace: false,
        ),
        for (final a in areas)
          ConfigActionRow(
            icon: Icons.download_done,
            label: '${a.styleLabel}, zoom ${a.minZoom} to ${a.maxZoom}',
            subtitle:
                '${offlineSizeLabel(a.bytes)}, ${a.tiles} tiles, ${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(a.createdMs))}',
            onTap: null,
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: t.textDim),
              tooltip: 'Delete this saved area',
              onPressed: () => _delete(a),
            ),
          ),
      ],
    );
  }
}
