import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/feed/feed_stats_header.dart';
import 'package:oui_spy/features/feed/filter_bar.dart';
import 'package:oui_spy/theme/app_theme.dart';

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
    if (!wd.isActive || !wd.target.includesFlock) return feedDetections;

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

  List<Detection> _filter(List<Detection> detections) {
    return detections.where((d) {
      if (!_activeFilters.contains(d.engine)) return false;
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
    final sourceNodes = state.meshSourceNodes;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text('FEED', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 3, color: t.textDim,
                      )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showStats = !_showStats),
                    child: Icon(
                      _showStats ? Icons.analytics : Icons.analytics_outlined,
                      size: 16,
                      color: _showStats ? AppTheme.accent : t.textDim,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (sourceNodes.isNotEmpty) ...[
                    const Icon(Icons.hub, size: 10, color: AppTheme.warning),
                    const SizedBox(width: 4),
                  ],
                  Text('${filtered.length}', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.accent, fontFamily: 'monospace',
                      )),
                ],
              ),
            ),
            FilterBar(
              activeFilters: _activeFilters,
              searchQuery: _searchQuery,
              onFiltersChanged: (f) => setState(() => _activeFilters = f),
              onSearchChanged: (q) => setState(() => _searchQuery = q),
              sourceNodes: sourceNodes,
              selectedNode: _selectedNode,
              onNodeChanged: (node) => setState(() => _selectedNode = node),
            ),
            SizedBox(
              height: 28,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: FeedMetric.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final metric = FeedMetric.values[index];
                  final active = _sortMetric == metric;
                  final arrow = active ? (_sortAscending ? ' ↑' : ' ↓') : '';
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (active) {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortMetric = metric;
                        _sortAscending = false;
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: active
                            ? AppTheme.accent.withValues(alpha: 0.2)
                            : t.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: active
                              ? AppTheme.accent.withValues(alpha: 0.6)
                              : t.border,
                          width: active ? 1.0 : 0.5,
                        ),
                      ),
                      child: Text(
                        '${metric.label}$arrow',
                        style: TextStyle(
                          color: active ? AppTheme.accent : t.textDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            const Divider(),
            if (_showStats && filtered.length >= 2)
              FeedStatsHeader(detections: filtered),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(
                      state.isConnected ? 'NO DETECTIONS' : 'NOT CONNECTED',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 2),
                    ))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => DetectionRow(detection: filtered[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
