import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/wardrive_report.dart';
import 'package:oui_spy/core/wdgwars/wdgwars_provider.dart';
import 'package:oui_spy/core/wigle/wigle_provider.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_spec_row.dart';
import 'package:oui_spy/widgets/d/d_stats_strip.dart';
import 'package:oui_spy/widgets/map_tiles.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showWardriveReport(BuildContext context, Session session) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WardriveReportScreen(session: session)));

class WardriveReportScreen extends ConsumerStatefulWidget {
  const WardriveReportScreen({super.key, required this.session});
  final Session session;

  @override
  ConsumerState<WardriveReportScreen> createState() => _WardriveReportScreenState();
}

class _WardriveReportScreenState extends ConsumerState<WardriveReportScreen> {
  late final Future<WardriveReport> _report = WardriveReport.load(
    ref.read(databaseProvider),
    widget.session,
    vendorOf: ref.read(ouiLookupProvider).lookup,
    wigleUploaded: ref.read(wigleProvider).isUploaded(widget.session.id),
    wdgwarsUploaded: ref.read(wdgwarsProvider).isUploaded(widget.session.id),
  );

  Future<void> _share(BuildContext context, WardriveReport r) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : const Rect.fromLTWH(0, 0, 100, 100);
    await SharePlus.instance.share(ShareParams(
      text: r.shareText(ref.read(unitSystemProvider)),
      subject: 'OUI-APEX wardrive report',
      sharePositionOrigin: origin,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final units = ref.watch(unitSystemProvider);
    return FutureBuilder<WardriveReport>(
      future: _report,
      builder: (context, snap) {
        final r = snap.data;
        return Scaffold(
          backgroundColor: t.background,
          appBar: AppBar(
            title: const Text('Wardrive report'),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: 'Share as text',
                  onPressed: r == null ? null : () => _share(context, r),
                ),
              ),
            ],
          ),
          body: snap.hasError
              ? Center(child: Text('Could not build the report.', style: TextStyle(color: t.textDim)))
              : r == null
                  ? Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2))
                  : _Body(report: r, units: units),
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.report, required this.units});
  final WardriveReport report;
  final UnitSystem units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final r = report;
    List<Widget> rows(List<(String, String)> items) => [
          for (final (i, (label, value)) in items.indexed)
            DSpecRow(label: label, value: value, divider: i < items.length - 1),
        ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          AppTime.dateTime(DateTime.fromMillisecondsSinceEpoch(r.session.startedAt)),
          style: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${durationLabel(r.duration)} · ${UnitFormatter.distance(r.session.distanceKm, units)}',
          style: TextStyle(color: t.textSecondary, fontFamily: AppTheme.mono),
        ),
        const SizedBox(height: 12),
        DStatsStrip(items: [
          ('${r.networks}', 'Wi-Fi networks'),
          ('${r.newNetworks}', 'New'),
          ('${r.ble}', 'Bluetooth'),
        ]),
        if (r.route.length >= 2) ...[
          const SizedBox(height: 12),
          _RouteMap(route: [for (final (la, lo) in r.route) LatLng(la, lo)]),
        ],
        const DSectionHeader(label: 'Wi-Fi networks'),
        ...rows([
          ('New this session', '${r.newNetworks}'),
          ('Seen before', '${r.seenNetworks}'),
          ('Hidden', '${r.hidden}'),
          ('2.4 GHz', '${r.ghz24}'),
          ('5 GHz', '${r.ghz5}'),
        ]),
        if (r.security.isNotEmpty) ...[
          const DSectionHeader(label: 'Security'),
          ...rows([for (final e in r.security) (e.key, '${e.value}')]),
        ],
        if (r.makers.isNotEmpty) ...[
          const DSectionHeader(label: 'Top makers'),
          ...rows([for (final e in r.makers) (e.key, '${e.value}')]),
        ],
        const DSectionHeader(label: 'Detections'),
        ...rows([
          ('Flock cameras', '${r.flock}'),
          ('Drones', '${r.drones}'),
          ('Watchlist hits', '${r.watchlist}'),
        ]),
        if (r.alerts.isNotEmpty) ...[
          const DSectionHeader(label: 'Alerts during the session'),
          ...rows([for (final e in r.alerts) (e.key, '${e.value}')]),
        ],
        const DSectionHeader(label: 'Uploads'),
        ...rows([
          ('WiGLE', r.wigleUploaded ? 'Uploaded' : 'Not uploaded'),
          ('WDGWars', r.wdgwarsUploaded ? 'Uploaded' : 'Not uploaded'),
        ]),
      ],
    );
  }
}

class _RouteMap extends ConsumerWidget {
  const _RouteMap({required this.route});
  final List<LatLng> route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(mapStyleProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(route),
              padding: const EdgeInsets.all(24),
              maxZoom: 17,
            ),
            backgroundColor: style.isDark ? Colors.black : Colors.white,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            mapTileLayer(style),
            PolylineLayer(polylines: [Polyline(points: route, color: AppTheme.wardrive, strokeWidth: 3)]),
            mapAttribution(style),
          ],
        ),
      ),
    );
  }
}
