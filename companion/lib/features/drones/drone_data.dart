// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_tags.dart';
import 'package:oui_spy/core/export/drone_export.dart';
import 'package:oui_spy/core/services/faa_service.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final faaCachedProvider =
    FutureProvider.family<FaaRegistration?, String>((ref, id) {
  return ref.read(faaServiceProvider).cached(id);
});

final _ctaSerial = RegExp(r'^[0-9A-Z]+$');

enum FaaState { noSerial, notIndexed, ready }

/// Whether a drone's id is a serial the FAA registry can be asked about.
FaaState faaStateOf(DroneSummary d) {
  if (d.macs.contains(d.id)) return FaaState.noSerial;
  return _ctaSerial.hasMatch(d.id) ? FaaState.ready : FaaState.notIndexed;
}

String droneAgo(Duration d) {
  final s = d.inSeconds;
  if (s < 5) return 'now';
  if (s < 60) return '${s}s';
  if (s < 3600) return '${d.inMinutes}m';
  if (s < 86400) return '${d.inHours}h';
  return '${d.inDays}d';
}

String droneHeardText(Duration since) =>
    since.inSeconds < 5 ? 'Heard just now' : 'Last heard ${droneAgo(since)} ago';

String droneDuration(Duration d) {
  if (d.inSeconds < 90) return '${d.inSeconds} s';
  if (d.inMinutes < 90) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return '${d.inHours} h${m == 0 ? '' : ' $m min'}';
}

double? pilotRange(DroneReport r) {
  final d = r.dronePoint;
  final p = r.pilotPoint;
  return d == null || p == null ? null : metersBetween(p, d);
}

({String name, String source})? droneMakerOf(DroneSummary d, FaaRegistration? reg) {
  final faa = reg?.displayName ?? '';
  if (faa.isNotEmpty) return (name: faa, source: 'FAA');
  if (d.maker.isNotEmpty) return (name: d.maker, source: 'serial code');
  return null;
}

Future<void> shareDroneLog(
  BuildContext context,
  List<DroneReport> reports,
  Map<String, DroneTag> tags, {
  String title = 'OUI-SPY drones',
}) async {
  if (reports.isEmpty) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('No drone reports to export in this window')));
    return;
  }
  final format = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Export drone log')),
          ListTile(
              key: const Key('drone-export-csv'),
              title: const Text('CSV, every report'),
              onTap: () => Navigator.pop(ctx, 'csv')),
          ListTile(
              key: const Key('drone-export-kml'),
              title: const Text('KML, for Google Earth and ATAK'),
              onTap: () => Navigator.pop(ctx, 'kml')),
        ],
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  final text = format == 'csv'
      ? DroneExport.csv(reports, tags: tags)
      : DroneExport.kml(reports, tags: tags, title: title);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/oui_spy_drones.$format');
  await file.writeAsString(text);
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    subject: title,
    sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
  ));
}

class DroneTagBadge extends StatelessWidget {
  const DroneTagBadge(this.tag, {super.key});
  final DroneTag tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tag.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: tag.color),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(tag.icon, size: 12, color: tag.color),
        const SizedBox(width: 4),
        Text(tag.label,
            style: TextStyle(color: tag.color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
