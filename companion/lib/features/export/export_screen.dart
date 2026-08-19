import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart' show bleManagerProvider;
import 'package:oui_spy/core/db/app_database.dart' show AppDatabase, databaseProvider;
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final count = state.recentDetections.length;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('EXPORT')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count detections in current session',
                      style: TextStyle(color: t.textPrimary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('${state.recentDetections.where((d) => d.latitude != null).length} with GPS coordinates',
                      style: TextStyle(color: t.textDim, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _ExportButton(
              label: 'WIGLE CSV 1.6',
              description: 'Compatible with wigle.net upload',
              icon: Icons.table_chart,
              onTap: count > 0 ? () => _exportWigleCsv(context, state.recentDetections, ref.read(ignoreListProvider), ref.read(bleManagerProvider).board) : null,
            ),
            _ExportButton(
              label: 'JSON',
              description: 'Full detection data with all fields',
              icon: Icons.data_object,
              onTap: count > 0 ? () => _exportJson(context, state.recentDetections) : null,
            ),
            _ExportButton(
              label: 'KML',
              description: 'Google Earth / Maps overlay',
              icon: Icons.map,
              onTap: count > 0 ? () => _exportKml(context, state.recentDetections) : null,
            ),
            const SizedBox(height: 24),
            Text('DATABASE',
                style: TextStyle(
                    color: t.textDim,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _ExportButton(
              label: 'BACKUP DATABASE',
              description: 'Save full capture DB (.db) to Files / iCloud',
              icon: Icons.backup,
              onTap: () => _backupDatabase(context, ref),
            ),
            _ExportButton(
              label: 'RESTORE DATABASE',
              description: 'Replace ALL data from a .db backup file',
              icon: Icons.settings_backup_restore,
              trailingIcon: Icons.folder_open,
              onTap: () => _restoreDatabase(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backupDatabase(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      final file = await db.createBackup();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/x-sqlite3')],
        subject: 'OUI-SPY Database Backup',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restoreDatabase(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(
      label: 'SQLite DB',
      extensions: ['db', 'sqlite', 'sqlite3'],
    );
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || file.path.isEmpty) return;

    final valid = await AppDatabase.validateBackup(file.path);
    if (!valid) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Not a valid OUI-SPY database backup')));
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = AppTheme.of(ctx);
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Restore database?',
              style: TextStyle(color: t.textPrimary)),
          content: Text(
            'This REPLACES all current captures, sessions and settings with the backup. Current data will be lost. This cannot be undone.',
            style: TextStyle(color: t.textDim, fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('RESTORE',
                    style: TextStyle(color: AppTheme.accent))),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await ref.read(databaseProvider).restoreFromFile(file.path);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final t = AppTheme.of(ctx);
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Restore complete',
              style: TextStyle(color: t.textPrimary)),
          content: Text(
            'Fully close and reopen the app now to load the restored database.',
            style: TextStyle(color: t.textDim, fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<void> _exportWigleCsv(BuildContext context, List<Detection> detections, IgnoreListState ignoreList, String board) async {
    final csv = WigleCsv.generate(detections, ignoreList: ignoreList, board: board);
    await _shareFile(context, csv, 'oui_spy_wigle.csv');
  }

  Future<void> _exportJson(BuildContext context, List<Detection> detections) async {
    final buf = StringBuffer();
    buf.writeln('[');
    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      buf.write('  {"mac":"${d.macAddress}","engine":"${d.engine.name}","method":"${d.method}",'
          '"rssi":${d.rssi},"channel":${d.channel},'
          '"timestamp":"${d.appTimestamp.toIso8601String()}"');
      if (d.latitude != null) buf.write(',"lat":${d.latitude},"lon":${d.longitude}');
      if (d.deviceName.isNotEmpty) buf.write(',"name":"${d.deviceName}"');
      if (d.odid?.uavId != null) buf.write(',"uav_id":"${d.odid!.uavId}"');
      buf.write('}');
      if (i < detections.length - 1) buf.writeln(',');
    }
    buf.writeln('\n]');
    await _shareFile(context, buf.toString(), 'oui_spy_detections.json');
  }

  Future<void> _exportKml(BuildContext context, List<Detection> detections) async {
    final geoDetections = detections.where((d) => d.latitude != null).toList();
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buf.writeln('<Document><name>OUI-SPY Detections</name>');
    for (final d in geoDetections) {
      buf.writeln('<Placemark>');
      buf.writeln('  <name>${d.macAddress}</name>');
      buf.writeln('  <description>${d.engine.name} | ${d.method} | ${d.rssi}dBm</description>');
      buf.writeln('  <Point><coordinates>${d.longitude},${d.latitude},0</coordinates></Point>');
      buf.writeln('</Placemark>');
    }
    buf.writeln('</Document></kml>');
    await _shareFile(context, buf.toString(), 'oui_spy_detections.kml');
  }

  Future<void> _shareFile(BuildContext context, String content, String filename) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'OUI-SPY Export',
      sharePositionOrigin: origin,
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.description, required this.icon, this.onTap, this.trailingIcon = Icons.ios_share});
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? t.textPrimary : t.textDim,
          side: BorderSide(color: enabled ? t.border : t.border.withValues(alpha: 0.3)),
          padding: const EdgeInsets.all(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: enabled ? AppTheme.accent : t.textDim),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1,
                  color: enabled ? t.textPrimary : t.textDim,
                )),
                Text(description, style: TextStyle(
                  fontSize: 11, color: enabled ? t.textDim : t.textDim.withValues(alpha: 0.5),
                )),
              ],
            )),
            Icon(trailingIcon, size: 16, color: enabled ? t.textDim : t.textDim.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
