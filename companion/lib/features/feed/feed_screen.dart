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

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final merged = _mergeFlockFromWardrive(state.recentDetections, wd);
    final filtered = _filter(merged);
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
