import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/db/app_database.dart' show databaseProvider;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/debug_log.dart';
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
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


enum FeedMetric {
  time('TIME'),
  rssi('RSSI'),
  count('COUNT'),
  name('NAME'),
  kind('CLASS'),
  channel('CH');

  const FeedMetric(this.label);
  final String label;
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.onShowHistory});

  final VoidCallback? onShowHistory;

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
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<Detection> _dbHits = const [];
  bool _dbSearching = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    setState(() => _searchQuery = q);
    _searchDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _dbHits = const [];
        _dbSearching = false;
      });
      return;
    }
    setState(() => _dbSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _runDbSearch(q));
  }

  Future<void> _runDbSearch(String q) async {
    final term = q.trim();
    if (term.isEmpty) return;
    try {
      final rows = await ref.read(databaseProvider).searchDetectionMaps(term);
      if (!mounted || _searchQuery != q) return;
      setState(() {
        _dbHits = rows.map(detectionFromDbRow).toList();
        _dbSearching = false;
      });
    } catch (e) {
      DebugLog.log('FEED: history search failed: $e');
      if (!mounted) return;
      setState(() => _dbSearching = false);
    }
  }

  /// Live feed rows plus stored-history hits the 500-row buffer no longer holds.
  List<Detection> _withDbHits(List<Detection> live) =>
      _mergeHistory(live, _dbHits);

  List<Detection> _mergeHistory(List<Detection> live, List<Detection> history) {
    if (history.isEmpty) return live;
    final seen = <String>{
      for (final d in live) '${d.macAddress}|${d.engine.name}',
    };
    final extra = history
        .where((d) => seen.add('${d.macAddress}|${d.engine.name}'))
        .toList();
    if (extra.isEmpty) return live;
    return [...live, ...extra];
  }

  bool get _allEnginesActive =>
      _activeFilters.length == Engine.values.length && _activeRadio == null;

  int get _activeFilterCount {
    var n = 0;
    if (!_allEnginesActive) n++;
    if (_selectedNode != null) n++;
    return n;
  }

  String _engineFilterLabel() {
    for (final p in FilterPreset.values) {
      if (p == FilterPreset.all) continue;
      if (p.matches(_activeFilters, _activeRadio)) return p.label;
    }
    if (_activeFilters.isEmpty) return 'NO ENGINES';
    return '${_activeFilters.length} ENGINES';
  }

  String _nodeLabel(String Function(String) labelForNode) {
    if (_selectedNode == null) return 'ALL';
    if (_selectedNode!.isEmpty) return 'LOCAL';
    return labelForNode(_selectedNode!);
  }

  void _toggleSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _searchQuery = '';
        _dbHits = const [];
        _dbSearching = false;
      }
    });
  }

  void _resetEngineFilters() => setState(() {
        _activeFilters = Engine.values.toSet();
        _activeRadio = null;
      });

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
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        return d.macAddress.toLowerCase().contains(q) ||
            d.deviceName.toLowerCase().contains(q) ||
            d.ssid.toLowerCase().contains(q) ||
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
      case FeedMetric.kind:
        sorted.sort((a, b) {
          final e = a.engine.label.compareTo(b.engine.label);
          return dir(e != 0 ? e : a.method.compareTo(b.method));
        });
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
    final searchScope =
        _searchQuery.trim().isEmpty ? merged : _withDbHits(merged);
    final filtered = _sorted(_filter(searchScope));
    final sourceNodes = state.isManagerConnected ? state.meshSourceNodes : const <String>{};

    final droneGroups = groupDronesByUavId(filtered);
    final droneUavIds = droneGroups.map((g) => g.uavId).toSet();
    final nonDroneRows = filtered.where((d) {
      if (d.engine != Engine.skySpy) return true;
      final id = d.odid?.uavId ?? '';
      return id.isEmpty || !droneUavIds.contains(id);
    }).toList();

    final feedItems = <Object>[...nonDroneRows, ...droneGroups];
    final rowIndex = Map<Detection, int>.identity();
    for (int i = 0; i < nonDroneRows.length; i++) {
      rowIndex[nonDroneRows[i]] = i;
    }
    feedItems.sort((a, b) {
      DateTime ts(Object o) => o is Detection
          ? o.appTimestamp
          : (o as DroneGroup).representative.appTimestamp;
      final byTime = _sortAscending
          ? ts(a).compareTo(ts(b))
          : ts(b).compareTo(ts(a));
      if (a is Detection && b is Detection) {
        return rowIndex[a]!.compareTo(rowIndex[b]!);
      }
      return byTime;
    });

    final hasQuery = _searchQuery.trim().isNotEmpty;

    return Column(
          children: [
            CommandHeader(
              title: 'FEED',
              count: _activeFilterCount > 0 || hasQuery
                  ? '${filtered.length}/${searchScope.length}'
                  : '${state.totalDetections}',
              chips: _filterChips(t, state.labelForNode),
              indicators: [
                if (state.isManagerConnected && sourceNodes.isNotEmpty)
                  Icon(Icons.hub, size: barIconSize(context) * 0.8, color: AppTheme.warning),
              ],
              actions: [
                CommandBarAction(
                  icon: Icons.filter_alt,
                  label: 'Filter',
                  active: _activeFilterCount > 0,
                  onTap: () => _openFilterSheet(sourceNodes, state.labelForNode),
                ),
                CommandBarAction(
                  icon: _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  label: 'Sort: ${_sortMetric.label}',
                  onTap: _openSortSheet,
                ),
                if (widget.onShowHistory != null)
                  CommandBarAction(
                    icon: Icons.history,
                    label: 'History',
                    onTap: widget.onShowHistory,
                  ),
                CommandBarAction(
                  icon: Icons.more_vert,
                  label: 'More',
                  onTap: () => _openActionSheet(state),
                ),
              ],
            ),
            if (_searchOpen)
              CommandSearchField(
                controller: _searchCtrl,
                hintText: 'MAC, name, SSID, method, node…',
                onChanged: _onSearchChanged,
                onClose: _toggleSearch,
              ),
            const Divider(height: 1),
            if (_showStats && filtered.length >= 2)
              FeedStatsHeader(detections: filtered),
            Expanded(
              child: feedItems.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        state.isConnected
                            ? 'No detections yet. They show up here as your board finds them.'
                            : 'Not connected. Connect your OUI-SPY board from Home to see live detections.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.of(context).textDim),
                      ),
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
    );
  }

  List<Widget> _filterChips(ResolvedTheme t, String Function(String) labelForNode) {
    return <Widget>[
      if (!_allEnginesActive)
        CommandActiveChip(
          label: _engineFilterLabel(),
          color: AppTheme.accent,
          onClear: _resetEngineFilters,
        ),
      if (_selectedNode != null)
        CommandActiveChip(
          label: _nodeLabel(labelForNode),
          color: AppTheme.warning,
          onClear: () => setState(() => _selectedNode = null),
        ),
      if (_searchQuery.trim().isNotEmpty)
        CommandActiveChip(
          label: '"${_searchQuery.trim()}"',
          color: AppTheme.accent,
          onClear: _toggleSearch,
        ),
      if (_searchQuery.trim().isNotEmpty)
        Text(
          _dbSearching ? 'HISTORY…' : 'ALL HISTORY',
          style: barLabelStyle(context, _dbSearching ? t.textDim : AppTheme.accent, bold: false),
        ),
    ];
  }

  Future<void> _openFilterSheet(
    Set<String> sourceNodes,
    String Function(String) labelForNode,
  ) {
    return showCommandSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply(VoidCallback fn) {
            fn();
            setSheet(() {});
          }

          final t = AppTheme.of(ctx);
          final gap = barGap(ctx);
          return CommandSheet(
            title: 'FILTER',
            trailing: _activeFilterCount == 0
                ? null
                : TextButton(
                    onPressed: () => apply(() {
                      _resetEngineFilters();
                      setState(() => _selectedNode = null);
                    }),
                    child: Text('RESET',
                        style: barLabelStyle(ctx, AppTheme.accent)),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommandSheetGroup(
                  label: 'PRESET',
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final preset in FilterPreset.values)
                        CommandChip(
                          label: preset.label,
                          selected:
                              preset.matches(_activeFilters, _activeRadio),
                          color: switch (preset) {
                            FilterPreset.all => kPillAll,
                            FilterPreset.ble => kPillBle,
                            FilterPreset.wifi => kPillWifi,
                            FilterPreset.flock => AppTheme.flockWifi,
                            FilterPreset.drones => AppTheme.skySpy,
                            FilterPreset.alerts => AppTheme.error,
                          },
                          onTap: () => apply(() => setState(() {
                                _activeFilters = preset.resolve();
                                _activeRadio = preset.radio;
                              })),
                        ),
                    ],
                  ),
                ),
                if (sourceNodes.isNotEmpty)
                  CommandSheetGroup(
                    label: 'SOURCE',
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final (i, (id, label)) in <(String?, String)>[
                          (null, 'ALL'),
                          ('', 'LOCAL'),
                          ...sourceNodes.map((n) => (n, labelForNode(n))),
                        ].indexed)
                          CommandChip(
                            label: label,
                            selected: _selectedNode == id,
                            color: pillColor(i),
                            onTap: () => apply(
                                () => setState(() => _selectedNode = id)),
                          ),
                      ],
                    ),
                  ),
                CommandSheetGroup(
                  label: 'ENGINES',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => apply(() => setState(() {
                                  _activeFilters = Engine.values.toSet();
                                  _activeRadio = null;
                                })),
                            child: Text('ALL',
                                style: barLabelStyle(ctx, AppTheme.accent)),
                          ),
                          TextButton(
                            onPressed: () => apply(() => setState(() {
                                  _activeFilters = <Engine>{};
                                  _activeRadio = null;
                                })),
                            child: Text('NONE',
                                style: barLabelStyle(ctx, t.textDim)),
                          ),
                        ],
                      ),
                      for (final engine in Engine.values)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: engine.color,
                          value: _activeFilters.contains(engine),
                          onChanged: (v) => apply(() => setState(() {
                                final next = Set<Engine>.from(_activeFilters);
                                if (v ?? false) {
                                  next.add(engine);
                                } else {
                                  next.remove(engine);
                                }
                                _activeFilters = next;
                                _activeRadio = null;
                              })),
                          title: Row(
                            children: [
                              Icon(engine.icon,
                                  size: barIconSize(ctx), color: engine.color),
                              SizedBox(width: gap),
                              Flexible(
                                child: Text(
                                  engine.label.toUpperCase(),
                                  style: barLabelStyle(ctx, t.textPrimary)
                                      .copyWith(letterSpacing: 1),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            engine.description,
                            style: (Theme.of(ctx).textTheme.bodySmall ??
                                    const TextStyle())
                                .copyWith(color: t.textDim),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSortSheet() => showSortSheet<FeedMetric>(
        context: context,
        options: FeedMetric.values,
        label: (m) => m.label,
        current: () => _sortMetric,
        ascending: () => _sortAscending,
        hint: () => _sortDirectionHint,
        onPick: (m) => setState(() {
          if (_sortMetric == m) {
            _sortAscending = !_sortAscending;
          } else {
            _sortMetric = m;
            _sortAscending = false;
          }
        }),
        onToggleDirection: () => setState(() => _sortAscending = !_sortAscending),
      );

  String get _sortDirectionHint => switch ((_sortMetric, _sortAscending)) {
        (FeedMetric.time, true) => 'Oldest first',
        (FeedMetric.time, false) => 'Newest first',
        (FeedMetric.rssi, true) => 'Weakest signal first',
        (FeedMetric.rssi, false) => 'Strongest signal first',
        (FeedMetric.count, true) => 'Fewest hits first',
        (FeedMetric.count, false) => 'Most hits first',
        (FeedMetric.name, true) => 'A → Z',
        (FeedMetric.name, false) => 'Z → A',
        (FeedMetric.kind, true) => 'A → Z',
        (FeedMetric.kind, false) => 'Z → A',
        (FeedMetric.channel, true) => 'Lowest channel first',
        (FeedMetric.channel, false) => 'Highest channel first',
      };

  Future<void> _openActionSheet(AppState state) {
    return showCommandSheet<void>(
      context: context,
      builder: (ctx) => CommandSheet(
        title: 'ACTIONS',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommandSheetTile(
              icon: _showStats ? Icons.analytics : Icons.analytics_outlined,
              label: _showStats ? 'HIDE STATS' : 'SHOW STATS',
              subtitle: 'Summary header above the feed',
              color: _showStats ? AppTheme.accent : null,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _showStats = !_showStats);
              },
            ),
            CommandSheetTile(
              icon: _searchOpen ? Icons.search_off : Icons.search,
              label: _searchOpen ? 'CLOSE SEARCH' : 'SEARCH',
              subtitle: 'MAC, name, method, node',
              onTap: () {
                Navigator.pop(ctx);
                _toggleSearch();
              },
            ),
            const Divider(height: 1),
            CommandSheetTile(
              icon: Icons.ios_share,
              label: 'EXPORT CSV',
              subtitle: 'Full stored history, current filters',
              onTap: () {
                Navigator.pop(ctx);
                _exportCsv(context);
              },
            ),
            CommandSheetTile(
              icon: Icons.delete_sweep,
              label: 'CLEAR FEED',
              subtitle: '${state.recentDetections.length} detections held',
              color: AppTheme.error,
              onTap: state.recentDetections.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _clearAll(context);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear feed?'),
        content: const Text('Clears all detections from the feed and resets counts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(appStateProvider).resetCounts();
  }

  Future<void> _exportCsv(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      final rows = await ref.read(databaseProvider).getAllDetectionMaps();
      final history = rows.map(detectionFromDbRow).toList();
      final live = _mergeFlockFromWardrive(
        ref.read(appStateProvider).recentDetections,
        ref.read(wardriveProvider),
      );
      final detections = _sorted(_filter(_mergeHistory(live, history)));
      if (detections.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Nothing to export')));
        return;
      }
      final csv = DetectionsCsv.generate(detections);
      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'oui_spy_feed_$ts.csv';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'OUI-SPY Feed Export (${detections.length} detections)',
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}
