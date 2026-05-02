import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/export/wigle_csv.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final count = state.recentDetections.length;

    return Scaffold(
      backgroundColor: AppTheme.background,
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
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count detections in current session',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('${state.recentDetections.where((d) => d.latitude != null).length} with GPS coordinates',
                      style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _ExportButton(
              label: 'WIGLE CSV 1.6',
              description: 'Compatible with wigle.net upload',
              icon: Icons.table_chart,
              onTap: count > 0 ? () => _exportWigleCsv(context, state.recentDetections) : null,
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
          ],
        ),
      ),
    );
  }

  Future<void> _exportWigleCsv(BuildContext context, List<Detection> detections) async {
    final csv = WigleCsv.generate(detections);
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
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: 'OUI-SPY Export');
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.description, required this.icon, this.onTap});
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? AppTheme.textPrimary : AppTheme.textDim,
          side: BorderSide(color: enabled ? AppTheme.border : AppTheme.border.withValues(alpha: 0.3)),
          padding: const EdgeInsets.all(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: enabled ? AppTheme.accent : AppTheme.textDim),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1,
                  color: enabled ? AppTheme.textPrimary : AppTheme.textDim,
                )),
                Text(description, style: TextStyle(
                  fontSize: 11, color: enabled ? AppTheme.textDim : AppTheme.textDim.withValues(alpha: 0.5),
                )),
              ],
            )),
            Icon(Icons.ios_share, size: 16, color: enabled ? AppTheme.textDim : AppTheme.textDim.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
