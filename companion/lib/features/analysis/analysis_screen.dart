import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/db/app_database.dart' show ArchiveHit, ArchiveOverview, databaseProvider;
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  late final Future<ArchiveOverview> _overview = ref.read(databaseProvider).archiveOverview();
  final _query = TextEditingController();
  Timer? _debounce;
  List<ArchiveHit> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      final hits = await ref.read(databaseProvider).searchArchive(q);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    });
  }

  static String _engineLabel(String name) =>
      Engine.values.where((e) => e.name == name).firstOrNull?.label ?? name;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final priv = ref.watch(privacyScreenProvider);
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final num = NumberFormat.decimalPattern();
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('ARCHIVE')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          FutureBuilder<ArchiveOverview>(
            future: _overview,
            builder: (context, snap) {
              final o = snap.data;
              if (o == null) return const LinearProgressIndicator();
              final gpsPct = o.detections == 0 ? 0 : (o.withGps * 100 / o.detections).round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConfigSectionHeader(label: 'Local archive'),
                  ConfigInfoRow(icon: Icons.storage, label: 'Detections', value: num.format(o.detections)),
                  ConfigInfoRow(icon: Icons.devices_other, label: 'Devices', value: num.format(o.devices)),
                  ConfigInfoRow(icon: Icons.folder, label: 'Sessions', value: num.format(o.sessions)),
                  ConfigInfoRow(icon: Icons.gps_fixed, label: 'With GPS fix', value: '${num.format(o.withGps)} ($gpsPct%)'),
                  if (o.firstMs != null && o.lastMs != null)
                    ConfigInfoRow(
                      icon: Icons.date_range,
                      label: 'Span',
                      value: '${fmt.format(DateTime.fromMillisecondsSinceEpoch(o.firstMs!))} to '
                          '${fmt.format(DateTime.fromMillisecondsSinceEpoch(o.lastMs!))}',
                    ),
                  const SizedBox(height: 12),
                  const ConfigSectionHeader(label: 'By engine'),
                  for (final e in o.byEngine)
                    ConfigInfoRow(
                      icon: Icons.radar,
                      label: _engineLabel(e.engine),
                      value: '${num.format(e.devices)} devices · ${num.format(e.detections)} rows',
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const ConfigSectionHeader(label: 'Search'),
          TextField(
            controller: _query,
            onChanged: _onQuery,
            decoration: const InputDecoration(
              hintText: 'MAC (any separator), SSID, name or match description',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (_query.text.trim().isNotEmpty && !_searching)
            Text('${_hits.length} device${_hits.length == 1 ? '' : 's'}${_hits.length >= 200 ? ' (first 200)' : ''}',
                style: TextStyle(color: t.textDim, fontSize: 12)),
          for (final h in _hits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (h.ssid.isNotEmpty) maskName(h.ssid, priv),
                      if (h.name.isNotEmpty && h.name != h.ssid) maskName(h.name, priv),
                      if (h.ssid.isEmpty && h.name.isEmpty) maskMac(h.mac.toUpperCase(), priv),
                    ].join(' · '),
                    style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${maskMac(h.mac.toUpperCase(), priv)} · ${_engineLabel(h.engine)}'
                    '${h.description.isNotEmpty ? ' · ${h.description}' : ''}',
                    style: TextStyle(color: t.textDim, fontSize: 12, fontFamily: AppTheme.mono),
                  ),
                  Text(
                    '${h.sightings}× · best ${h.bestRssi} dBm · '
                    '${fmt.format(DateTime.fromMillisecondsSinceEpoch(h.firstMs))} to '
                    '${fmt.format(DateTime.fromMillisecondsSinceEpoch(h.lastMs))}',
                    style: TextStyle(color: t.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
