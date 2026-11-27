// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/db/app_database.dart' show databaseProvider;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/export/detections_csv.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/features/feed/feed_counts_strip.dart';
import 'package:oui_spy/features/feed/feed_stats_header.dart';
import 'package:oui_spy/features/feed/search_sheet.dart';
import 'package:oui_spy/core/global_search.dart';
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
  channel('CH'),
  vendor('VENDOR');

  const FeedMetric(this.label);
  final String label;
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.count,
    required this.chips,
    required this.showHub,
    required this.actions,
  });
  final String count;
  final List<Widget> chips;
  final bool showHub;
  final List<CommandBarAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Text(
            count,
            style: TextStyle(fontFamily: AppTheme.mono, fontSize: 12, color: t.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(spacing: 8, children: chips),
            ),
          ),
          if (showHub)
            Tooltip(
              message: 'Mesh nodes',
              child: Icon(Icons.hub_outlined, size: 18, color: AppTheme.accent),
            ),
          for (final a in actions)
            IconButton(
              tooltip: a.label,
              onPressed: a.onTap,
              visualDensity: VisualDensity.compact,
              icon: Icon(a.icon, size: 20),
              color: a.active ? AppTheme.accent : t.textSecondary,
            ),
        ],
      ),
    );
  }
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.onShowHistory});

  final VoidCallback? onShowHistory;

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  Set<Engine> _activeFilters = Engine.values.toSet();
  SignatureClass? _activeClass;
  RadioFilter? _activeRadio;
  String _searchQuery = '';
  String? _selectedNode;
  bool _showStats = true;
  FeedMetric _sortMetric = FeedMetric.time;
  bool _sortAscending = false; // false = descending (newest/strongest/most first)
  String? _vendorFirst;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<Detection> _dbHits = const [];
  bool _dbSearching = false;
  SearchResults _results = SearchResults.empty;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  SearchResults _searchAll() {
    final q = _searchQuery.trim();
    return q.isEmpty ? SearchResults.empty : searchEntries(q, buildSearchEntries(ref, history: _dbHits));
  }

  Future<void> _openResults(SearchArea? area) {
    final fresh = _searchAll();
    setState(() => _results = fresh);
    return showSearchResults(context, ref, fresh, area: area);
  }

  void _onSearchChanged(String q) {
    setState(() => _searchQuery = q);
    _searchDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _dbHits = const [];
        _dbSearching = false;
        _results = SearchResults.empty;
      });
      return;
    }
    setState(() {
      _dbSearching = true;
      _results = _searchAll();
    });
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
        _results = _searchAll();
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
    final app = ref.read(appStateProvider);
    final seen = <String>{
      for (final d in live) app.dedupeKey(d),
    };
    final extra = history
        .where((d) => seen.add(app.dedupeKey(d)))
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
    if (_activeClass != null) n++;
    return n;
  }

  Map<String, SignatureClass> _classByMac() {
    final reg = ref.read(deviceRegistryProvider);
    return {
      for (final dev in reg.devices)
        if (dev.primaryClass != null && dev.obs.mac.isNotEmpty)
          dev.obs.mac.toLowerCase(): dev.primaryClass!,
    };
  }

  List<SignatureClass> _classesPresent() {
    final s = <SignatureClass>{
      for (final dev in ref.read(deviceRegistryProvider).devices)
        if (dev.primaryClass != null) dev.primaryClass!,
    };
    return s.toList()..sort((a, b) => a.label.compareTo(b.label));
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
        _results = SearchResults.empty;
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
    final classByMac = _activeClass == null ? null : _classByMac();
    return detections.where((d) {
      if (!_activeFilters.contains(d.engine)) return false;
      if (!_radioMatches(d)) return false;
      if (classByMac != null &&
          classByMac[d.macAddress.toLowerCase()] != _activeClass) {
        return false;
      }
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
        int radio(Detection d) => d.isWifiDetection ? 0 : d.isBleDetection ? 1 : 2;
        sorted.sort((a, b) {
          final r = radio(a).compareTo(radio(b));
          return r != 0 ? r : dir(a.appTimestamp.compareTo(b.appTimestamp));
        });
      case FeedMetric.rssi:
        sorted.sort((a, b) => dir(a.rssi.compareTo(b.rssi)));
      case FeedMetric.count:
        sorted.sort((a, b) => dir(a.count.compareTo(b.count)));
      case FeedMetric.name:
        sorted.sort((a, b) {
          final na = detectionHasName(a), nb = detectionHasName(b);
          if (na != nb) return na ? -1 : 1;
          return dir(detectionHeadline(a).toLowerCase().compareTo(detectionHeadline(b).toLowerCase()));
        });
      case FeedMetric.kind:
        sorted.sort((a, b) {
          final e = a.engine.label.compareTo(b.engine.label);
          return dir(e != 0 ? e : a.method.compareTo(b.method));
        });
      case FeedMetric.channel:
        sorted.sort((a, b) => dir(a.channel.compareTo(b.channel)));
      case FeedMetric.vendor:
        final oui = ref.read(ouiLookupProvider);
        sortByVendor(sorted, (d) => FeedStatsHeader.vendorKey(oui, d.macAddress),
            first: _vendorFirst, ascending: asc);
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
    final grouped = groupBySsid(nonDroneRows, state.dedupeKey);
    String rowKey(Detection d) => grouped.keyOf[d] ?? state.dedupeKey(d);
    final nested = !ref.watch(groupClientsProvider)
        ? (rows: grouped.rows, parentOf: Map<Detection, Detection>.identity())
        : nestUnderParents(grouped.rows, rowKey, (d) {
            final ap = state.apKeyFor(d);
            return ap == null ? null : grouped.groupOf[ap] ?? ap;
          });
    nonDroneRows
      ..clear()
      ..addAll(nested.rows);

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
            const FeedCountsStrip(),
            _FeedHeader(
              count: _activeFilterCount > 0 || hasQuery
                  ? '${filtered.length}/${searchScope.length}'
                  : '${state.totalDetections}',
              chips: _filterChips(t, state.labelForNode),
              showHub: state.isManagerConnected && sourceNodes.isNotEmpty,
              actions: [
                CommandBarAction(
                  icon: Icons.filter_alt_outlined,
                  label: 'Filter',
                  active: _activeFilterCount > 0,
                  onTap: () => _openFilterSheet(sourceNodes, state.labelForNode),
                ),
                CommandBarAction(
                  icon: _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  label: 'Sort: ${_sortMetric.label}',
                  onTap: _openSortSheet,
                ),
                groupClientsAction(ref),
                if (widget.onShowHistory != null)
                  CommandBarAction(
                    icon: Icons.history,
                    label: 'Alerts',
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
                hintText: 'Search everything: MAC, name, SSID, maker, node…',
                onChanged: _onSearchChanged,
                onClose: _toggleSearch,
              ),
            if (_searchOpen && hasQuery)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    key: const Key('search-area-chips'),
                    spacing: 8,
                    children: [
                      CommandChip(
                        label: 'EVERYTHING',
                        count: _results.total,
                        selected: false,
                        color: AppTheme.accent,
                        onTap: () => _openResults(null),
                      ),
                      for (final a in _results.areas)
                        CommandChip(
                          label: a.label.toUpperCase(),
                          count: _results.totals[a],
                          selected: false,
                          color: AppTheme.accent,
                          onTap: () => _openResults(a),
                        ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            if (_showStats && filtered.length >= 2)
              FeedStatsHeader(
                detections: filtered,
                selectedVendor: _sortMetric == FeedMetric.vendor ? _vendorFirst : null,
                onVendorTap: (v) => setState(() {
                  _sortMetric = FeedMetric.vendor;
                  _sortAscending = true;
                  _vendorFirst = v;
                }),
              ),
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
                          return DroneDetectionRow(
                            key: ValueKey('drone:${item.uavId}'),
                            group: item,
                          );
                        }
                        final d = item as Detection;
                        final row = DetectionRow(
                          key: ValueKey(rowKey(d)),
                          detection: d,
                          macs: grouped.macs[d] ?? const [],
                        );
                        return nested.parentOf.containsKey(d)
                            ? Padding(padding: const EdgeInsets.only(left: 28), child: row)
                            : row;
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
          color: AppTheme.accent,
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
                      setState(() {
                        _selectedNode = null;
                        _activeClass = null;
                      });
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
                if (_classesPresent().isNotEmpty)
                  CommandSheetGroup(
                    label: 'CLASS',
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        CommandChip(
                          label: 'ALL',
                          selected: _activeClass == null,
                          color: AppTheme.accent,
                          onTap: () =>
                              apply(() => setState(() => _activeClass = null)),
                        ),
                        for (final c in _classesPresent())
                          CommandChip(
                            label: c.label.toUpperCase(),
                            color: classColor(c),
                            selected: _activeClass == c,
                            onTap: () => apply(() => setState(() =>
                                _activeClass = _activeClass == c ? null : c)),
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
          _vendorFirst = null;
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
        (FeedMetric.time, true) => 'WiFi, then BLE · oldest first',
        (FeedMetric.time, false) => 'WiFi, then BLE · newest first',
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
        (FeedMetric.vendor, true) => 'A → Z',
        (FeedMetric.vendor, false) => 'Z → A',
      };

  Future<void> _openActionSheet(AppState state) {
    final groupOn = ref.read(groupClientsProvider);
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
              icon: groupOn ? Icons.layers : Icons.layers_outlined,
              label: groupOn ? 'UNGROUP CLIENTS' : 'GROUP CLIENTS',
              subtitle: 'Clients indented under the network they use',
              color: groupOn ? AppTheme.accent : null,
              onTap: () {
                Navigator.pop(ctx);
                toggleGroupClients(ref);
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

({List<T> rows, Map<T, T> parentOf}) nestUnderParents<T extends Object>(List<T> rows,
    String Function(T) keyOf, String? Function(T) parentKeyOf) {
  final byKey = {for (final d in rows) keyOf(d): d};
  final byParent = <String, List<T>>{};
  final parentOf = Map<T, T>.identity();
  for (final d in rows) {
    final p = parentKeyOf(d);
    final parent = p == null || p == keyOf(d) ? null : byKey[p];
    if (parent == null || parentKeyOf(parent) != null) continue;
    (byParent[p!] ??= []).add(d);
    parentOf[d] = parent;
  }
  final out = <T>[];
  for (final d in rows) {
    if (parentOf.containsKey(d)) continue;
    out.add(d);
    out.addAll(byParent[keyOf(d)] ?? const []);
  }
  return (rows: out, parentOf: parentOf);
}

const _kGroupSsid = 'feedGroupBySsid';

final groupClientsProvider =
    StateProvider<bool>((ref) => ref.read(sharedPreferencesProvider).getBool(_kGroupSsid) ?? false);

void toggleGroupClients(WidgetRef ref) {
  final v = !ref.read(groupClientsProvider);
  ref.read(groupClientsProvider.notifier).state = v;
  ref.read(sharedPreferencesProvider).setBool(_kGroupSsid, v);
}

CommandBarAction groupClientsAction(WidgetRef ref) {
  final on = ref.watch(groupClientsProvider);
  return CommandBarAction(
    icon: on ? Icons.layers : Icons.layers_outlined,
    label: on ? 'Ungroup clients' : 'Group clients',
    active: on,
    onTap: () => toggleGroupClients(ref),
  );
}

({List<Detection> rows, Map<Detection, String> keyOf, Map<Detection, List<String>> macs, Map<String, String> groupOf})
    groupBySsid(List<Detection> rows, String Function(Detection) keyOf) {
  final out = <Detection>[];
  final slot = <String, int>{};
  final members = <int, List<Detection>>{};
  final groupOf = <String, String>{};
  for (final d in rows) {
    final shown = d.wardrive?.ssid.trim() ?? '';
    final ssid = d.method != 'wifi_ap' ? '' : shown.isNotEmpty ? shown : d.ssid.trim();
    if (ssid.isEmpty) {
      out.add(d);
      continue;
    }
    final g = 'ssid:$ssid|${d.engine.name}';
    groupOf[keyOf(d)] = g;
    final i = slot[g];
    if (i != null) {
      members[i]!.add(d);
      continue;
    }
    slot[g] = out.length;
    members[out.length] = [d];
    out.add(d);
  }
  final keys = Map<Detection, String>.identity();
  final macs = Map<Detection, List<String>>.identity();
  for (final MapEntry(key: i, value: list) in members.entries) {
    var rep = list.first;
    if (list.length > 1) {
      var rssi = rep.rssi, count = 0, at = rep.appTimestamp;
      for (final m in list) {
        if (m.rssi > rssi) rssi = m.rssi;
        if (m.appTimestamp.isAfter(at)) at = m.appTimestamp;
        count += m.count;
      }
      rep = rep.copyWith(rssi: rssi, count: count, appTimestamp: at);
      out[i] = rep;
      macs[rep] = [for (final m in list) m.macAddress];
    }
    keys[rep] = groupOf[keyOf(list.first)]!;
  }
  return (rows: out, keyOf: keys, macs: macs, groupOf: groupOf);
}
