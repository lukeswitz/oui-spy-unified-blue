import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/export/detections_csv.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/feed/feed_stats_header.dart';
import 'package:oui_spy/features/feed/filter_bar.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


enum FeedMetric {
  time('TIME'),
  rssi('RSSI'),
  count('COUNT'),
  name('NAME'),
  channel('CH');

  const FeedMetric(this.label);
  final String label;
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  Set<Engine> _activeFilters = Engine.values.toSet();
  RadioFilter? _activeRadio;
  String _searchQuery = '';
  String? _selectedNode;
  bool _showStats = true;
  FeedMetric _sortMetric = FeedMetric.time;
  bool _sortAscending = false; // false = descending (newest/strongest/most first)

  /// Merge flock detections from active wardrive into the feed.
  /// The feed's 500-entry ring buffer gets overwhelmed by wardrive
  /// detections, evicting flock entries. This ensures they always show.
  List<Detection> _mergeFlockFromWardrive(
    List<Detection> feedDetections,
    WardriveController wd,
  ) {
    if (!wd.isActive || !wd.includesFlock) return feedDetections;

    final flockDets = wd.flockDetections;
    if (flockDets.isEmpty) return feedDetections;

    final feedFlockMacs = <String>{};
    for (final d in feedDetections) {
      if (d.engine == Engine.flockBle || d.engine == Engine.flockWifi) {
        feedFlockMacs.add(d.macAddress);
      }
    }

    final missing = flockDets
        .where((d) => !feedFlockMacs.contains(d.macAddress))
        .toList();
    if (missing.isEmpty) return feedDetections;

    final merged = List<Detection>.from(feedDetections);
    merged.insertAll(0, missing);
    return merged;
  }

  bool _radioMatches(Detection d) {
    if (_activeRadio == null) return true;
    return _activeRadio == RadioFilter.ble ? d.isBleDetection : d.isWifiDetection;
  }

  List<Detection> _filter(List<Detection> detections) {
    return detections.where((d) {
      if (!_activeFilters.contains(d.engine)) return false;
      if (!_radioMatches(d)) return false;
      if (_selectedNode != null) {
        if (_selectedNode == '' && d.sourceNodeId.isNotEmpty) return false;
        if (_selectedNode!.isNotEmpty && d.sourceNodeId != _selectedNode) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return d.macAddress.toLowerCase().contains(q) ||
            d.deviceName.toLowerCase().contains(q) ||
            d.method.toLowerCase().contains(q) ||
            d.sourceNodeId.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  List<Detection> _sorted(List<Detection> detections) {
    final sorted = List<Detection>.from(detections);
    final asc = _sortAscending;
    int dir(int v) => asc ? v : -v;
    switch (_sortMetric) {
      case FeedMetric.time:
        sorted.sort((a, b) => dir(a.appTimestamp.compareTo(b.appTimestamp)));
      case FeedMetric.rssi:
        sorted.sort((a, b) => dir(a.rssi.compareTo(b.rssi)));
      case FeedMetric.count:
        sorted.sort((a, b) => dir(a.count.compareTo(b.count)));
      case FeedMetric.name:
        sorted.sort((a, b) => dir(a.deviceName.toLowerCase().compareTo(b.deviceName.toLowerCase())));
      case FeedMetric.channel:
        sorted.sort((a, b) => dir(a.channel.compareTo(b.channel)));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final merged = _mergeFlockFromWardrive(state.recentDetections, wd);
    final filtered = _sorted(_filter(merged));
    final sourceNodes = state.isManagerConnected ? state.meshSourceNodes : const <String>{};

    final droneGroups = groupDronesByUavId(filtered);
    final droneUavIds = droneGroups.map((g) => g.uavId).toSet();
    final nonDroneRows = filtered.where((d) {
      if (d.engine != Engine.skySpy) return true;
      final id = d.odid?.uavId ?? '';
      return id.isEmpty || !droneUavIds.contains(id);
    }).toList();

    final feedItems = <Object>[...nonDroneRows, ...droneGroups];
    feedItems.sort((a, b) {
      DateTime ts(Object o) => o is Detection
          ? o.appTimestamp
          : (o as DroneGroup).representative.appTimestamp;
      final byTime = _sortAscending
          ? ts(a).compareTo(ts(b))
          : ts(b).compareTo(ts(a));
      if (a is Detection && b is Detection) {
        final ia = nonDroneRows.indexOf(a);
        final ib = nonDroneRows.indexOf(b);
        return ia.compareTo(ib);
      }
      return byTime;
    });

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text('FEED', style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        letterSpacing: 3, color: t.textDim, fontWeight: FontWeight.w700,
                      )),
                  const Spacer(),
                  _HeaderIconButton(
                    icon: _showStats ? Icons.analytics : Icons.analytics_outlined,
                    active: _showStats,
                    enabled: true,
                    onTap: () => setState(() => _showStats = !_showStats),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: Icons.ios_share,
                    active: false,
                    enabled: filtered.isNotEmpty,
                    onTap: filtered.isEmpty ? null : () => _exportCsv(context, filtered),
                  ),
                  const SizedBox(width: 10),
                  if (state.isManagerConnected && sourceNodes.isNotEmpty) ...[
                    const Icon(Icons.hub, size: 14, color: AppTheme.warning),
                    const SizedBox(width: 4),
                  ],
                  Text('${state.totalDetections}', style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.accent, fontFamily: 'monospace', fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
            FilterBar(
              activeFilters: _activeFilters,
              activeRadio: _activeRadio,
              searchQuery: _searchQuery,
              onFiltersChanged: (f) => setState(() {
                _activeFilters = f;
                _activeRadio = null;
              }),
              onPresetApplied: (p) => setState(() {
                _activeFilters = p.resolve();
                _activeRadio = p.radio;
              }),
              onSearchChanged: (q) => setState(() => _searchQuery = q),
              sortMetric: _sortMetric,
              sortAscending: _sortAscending,
              onSortChanged: (m, asc) => setState(() {
                _sortMetric = m;
                _sortAscending = asc;
              }),
              sourceNodes: sourceNodes,
              selectedNode: _selectedNode,
              onNodeChanged: (node) => setState(() => _selectedNode = node),
              labelForNode: state.labelForNode,
            ),
            const Divider(height: 1),
            if (_showStats && filtered.length >= 2)
              FeedStatsHeader(detections: filtered),
            Expanded(
              child: feedItems.isEmpty
                  ? Center(child: Text(
                      state.isConnected ? 'NO DETECTIONS' : 'NOT CONNECTED',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 2),
                    ))
                  : ListView.builder(
                      itemCount: feedItems.length,
                      itemBuilder: (context, index) {
                        final item = feedItems[index];
                        if (item is DroneGroup) {
                          return DroneDetectionRow(group: item);
                        }
                        return DetectionRow(detection: item as Detection);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, List<Detection> detections) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = DetectionsCsv.generate(detections);
      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'oui_spy_feed_$ts.csv';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv);

      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 100, 100);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'OUI-SPY Feed Export (${detections.length} detections)',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.active,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final color = !enabled
        ? t.textDim.withValues(alpha: 0.4)
        : active
            ? AppTheme.accent
            : t.textSecondary;
    return Material(
      color: active ? AppTheme.accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
