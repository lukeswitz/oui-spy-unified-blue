import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/ignore_list_state.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/stops_report.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

List<StopsHit> _build((List<TrackPoint>, List<CellSighting>) input) => StopsReport.build(input.$1, input.$2);

String _ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class StopsScreen extends ConsumerStatefulWidget {
  const StopsScreen({super.key});

  @override
  ConsumerState<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends ConsumerState<StopsScreen> {
  late Future<List<StopsHit>> _hits = _load();

  Future<List<StopsHit>> _load() async {
    final since = DateTime.now().millisecondsSinceEpoch - StopsReport.windowMs;
    final (track, rows) = await ref.read(databaseProvider).stopsReportInput(since);
    final ignore = ref.read(ignoreListProvider);
    final engines = Engine.values.asNameMap();
    final cells = <CellSighting>[];
    for (final r in rows) {
      final ble = isBleDetectionRaw(method: r.method, engine: engines[r.engine] ?? Engine.wardrive, channel: r.channel);
      if (ignore.shouldSuppress(mac: r.mac, ssid: r.ssid, isBle: ble)) continue;
      cells.add(CellSighting(r.mac, r.name.isNotEmpty ? r.name : r.ssid, ble, r.lat, r.lon, r.lastMs));
    }
    return compute(_build, ([for (final p in track) TrackPoint(p.$1, p.$2, p.$3)], cells));
  }

  Future<void> _ignore(StopsHit h) async {
    await ref.read(ignoreListProvider).add(IgnoreEntry(
          type: IgnoreType.mac,
          value: IgnoreEntry.normalize(IgnoreType.mac, h.mac),
          scope: h.ble ? IgnoreScope.ble : IgnoreScope.wifi,
          label: h.name,
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to the ignore list')));
    setState(() => _hits = _load());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final masked = ref.watch(privacyScreenProvider);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Seen at Your Stops'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About this report',
            onPressed: () => showInfoSheet(context, t, 'Seen at your stops', const [
              'A stop is a place where you stayed 5 minutes or more. Stops closer than 500 m count as one.',
              'This lists radios heard at 2 or more of your stops in the last 7 days.',
              'Your own phone, watch, earbuds and car show here too. Tap the eye to ignore one.',
              'Uses detections that have a GPS position.',
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<StopsHit>>(
          future: _hits,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final hits = snap.data ?? const <StopsHit>[];
            if (snap.hasError || hits.isEmpty) {
              return CommandEmptyState(
                icon: Icons.place_outlined,
                title: snap.hasError ? 'Could not build the report' : 'Nothing seen at two stops',
                message: snap.hasError
                    ? '${snap.error}'
                    : 'Radios heard at 2 or more of your stops in the last 7 days show here.',
              );
            }
            return ListView.separated(
              itemCount: hits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final h = hits[i];
                final mac = maskMac(h.mac, masked);
                return ListTile(
                  leading: Icon(h.ble ? Icons.bluetooth : Icons.wifi, color: t.textSecondary),
                  title: Text(h.name.isEmpty ? mac : maskName(h.name, masked)),
                  subtitle: Text('${h.stops} stops · last heard ${_ago(h.lastMs)}${h.name.isEmpty ? '' : ' · $mac'}',
                      style: TextStyle(color: t.textDim, fontSize: 12)),
                  trailing: IconButton(
                    icon: Icon(Icons.visibility_off_outlined, color: t.textSecondary),
                    tooltip: 'Ignore this device',
                    onPressed: () => _ignore(h),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
