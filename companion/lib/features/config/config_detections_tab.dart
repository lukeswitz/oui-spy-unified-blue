part of 'device_config.dart';

enum _DetSort {
  time('TIME'),
  rssi('RSSI'),
  mac('MAC');

  const _DetSort(this.label);
  final String label;
}

enum _RadioSel { all, ble, wifi }

/// 0 = BLE, 1 = WiFi, 2 = unknown — for a raw DB detection row.
int _detRadioRank(Map<String, dynamic> d) {
  final isBle = d['isBle'];
  if (isBle is bool) return isBle ? 0 : 1;
  final method = (d['detectionMethod'] as String?) ?? '';
  if (isBleMethod(method)) return 0;
  if (isWifiMethod(method)) return 1;
  final engine = (d['engine'] as String?) ?? '';
  if (engine == 'flockBle') return 0;
  if (engine == 'flockWifi') return 1;
  final ch = (d['channel'] as int?) ?? 0;
  return (ch >= 1 && ch <= 14) || ch >= 30 ? 1 : 0;
}

/// Detection-method label — the exact text shown on each detections-tab row.
String _detMethodLabel(String method) => switch (method) {
  'oui_addr1' => 'ADDR1 (DST)',
  'oui_addr2' => 'ADDR2 (SRC)',
  'oui_addr3' => 'ADDR3 (BSSID)',
  'ssid' => 'SSID',
  'wildcard_probe' => 'PROBE REQ',
  'oui_match' => 'BLE OUI',
  'name_match' => 'BLE NAME',
  'mfg_id' => 'MFG DATA',
  'raven_uuid' => 'RAVEN UUID',
  'gatt_uuid' => 'FLOCK GATT',
  'nordic_dfu' => 'NORDIC DFU',
  'watchlist' => 'WATCHLIST',
  'ble_watchlist' => 'BLE WATCHLIST',
  'wifi_watchlist' => 'WIFI WATCHLIST',
  'ble_proximity' => 'BLE PROXIMITY',
  'wifi_proximity' => 'WIFI PROXIMITY',
  _ => method.toUpperCase(),
};

FlockConfidence? _detFlockConfidence(Map<String, dynamic> d) {
  final e = d['engine'] as String?;
  if (e != 'flockBle' && e != 'flockWifi') return null;
  return FlockExtension(signals: d['flockSignals'] as int? ?? 0)
      .confidence(d['detectionMethod'] as String? ?? '');
}

String _confShort(FlockConfidence c) => switch (c) {
  FlockConfidence.verified => 'VERIFIED',
  FlockConfidence.high => 'HIGH',
  FlockConfidence.suspected => 'SUSPECTED',
};

Color _confColor(FlockConfidence c) =>
    c == FlockConfidence.suspected ? AppTheme.warning : AppTheme.success;

class DetectionHistoryView extends StatelessWidget {
  const DetectionHistoryView({super.key, this.onShowLive});

  final VoidCallback? onShowLive;

  @override
  Widget build(BuildContext context) => _DetectionsTab(onShowLive: onShowLive);
}

class _DetectionsTab extends ConsumerStatefulWidget {
  const _DetectionsTab({this.onShowLive});

  final VoidCallback? onShowLive;

  @override
  ConsumerState<_DetectionsTab> createState() => _DetectionsTabState();
}

class _DetectionsTabState extends ConsumerState<_DetectionsTab> {
  List<Map<String, dynamic>> _detections = [];
  bool _loading = true;
  bool _rescanning = false;
  _DetSort _sort = _DetSort.time;
  bool _ascending = false;
  String? _engineFilter; // null = all, 'flock', 'detector'
  bool _noGpsOnly = false;
  _RadioSel _radioFilter = _RadioSel.all;
  String? _methodFilter; // null = all, else a raw detectionMethod string
  FlockConfidence? _confFilter; // null = all, else flock rows at that level
  String? _classFilter; // null = all, else an alert class
  bool _showMap = false;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  String _search = '';
  final _mapController = MapController();

  Future<void> _rescan() async {
    final db = ref.read(databaseProvider);
    final watchlist =
        List<WatchlistEntry>.from(ref.read(watchlistProvider).entries);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _rescanning = true);
    try {
      final res = await WigleCsvRescan.rescanAll(db, watchlist: watchlist);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.success,
        content: Text(
          'Rescanned ${res.sessionsScanned} sessions, '
          '${res.rowsScanned} rows, ${res.rowsUpdated} reclassified '
          '(${res.newDetectorMacs} detector, ${res.newFlockMacs} flock)',
        ),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppTheme.error,
        content: Text('Rescan failed: $e'),
      ));
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  Future<void> _clearAll() async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all detections?'),
        content: Text('Permanently deletes ${_detections.length} detection(s) from the database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await db.clearFlockDetectorDetections() + await db.clearClassAlerts();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      backgroundColor: AppTheme.success,
      content: Text('Cleared $n detection(s)'),
    ));
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _engineFilter = ref.read(historyFilterRequestProvider) ?? _engineFilter;
    if (ref.read(historyFilterRequestProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(historyFilterRequestProvider.notifier).state = null);
    }
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getAlertHistoryMaps();
    if (mounted) setState(() { _detections = rows; _loading = false; });
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _detections;
    if (_engineFilter == 'flock') {
      list = list.where((d) {
        final e = d['engine'] as String;
        return e == 'flockBle' || e == 'flockWifi';
      }).toList();
    } else if (_engineFilter == 'detector') {
      list = list.where((d) => d['engine'] == 'detector').toList();
    } else if (_engineFilter == 'drone') {
      list = list.where((d) => d['engine'] == 'skySpy').toList();
    } else if (_engineFilter == 'signature') {
      list = list.where((d) => d['engine'] == 'signature' || d['mergedClasses'] != null).toList();
    }

    if (_noGpsOnly) {
      list = list
          .where((d) => d['latitude'] == null || d['longitude'] == null)
          .toList();
    }

    if (_radioFilter != _RadioSel.all) {
      final wantRank = _radioFilter == _RadioSel.ble ? 0 : 1;
      list = list.where((d) => _detRadioRank(d) == wantRank).toList();
    }

    if (_methodFilter != null) {
      list = list
          .where((d) => (d['detectionMethod'] as String?) == _methodFilter)
          .toList();
    }

    if (_confFilter != null) {
      list =
          list.where((d) => _detFlockConfidence(d) == _confFilter).toList();
    }

    if (_classFilter != null) {
      list = list.where((d) => _detClasses(d).contains(_classFilter)).toList();
    }

    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final mac = (d['macAddress'] as String?)?.toLowerCase() ?? '';
        final name = (d['deviceName'] as String?)?.toLowerCase() ?? '';
        final ssid = (d['ssid'] as String?)?.toLowerCase() ?? '';
        final method = (d['detectionMethod'] as String?)?.toLowerCase() ?? '';
        final engine = (d['engine'] as String?)?.toLowerCase() ?? '';
        return mac.contains(q) || name.contains(q) || ssid.contains(q) ||
            method.contains(q) || engine.contains(q);
      }).toList();
    }

    final cmp = switch (_sort) {
      _DetSort.time => (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['appTimestamp'] as int).compareTo(b['appTimestamp'] as int),
      _DetSort.rssi => (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['rssi'] as int).compareTo(b['rssi'] as int),
      _DetSort.mac => (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['macAddress'] as String).compareTo(b['macAddress'] as String),
    };

    list.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));
    return list;
  }

  Color _engineColor(String engine) => switch (engine) {
    'flockBle' => AppTheme.flockBle,
    'flockWifi' => AppTheme.flockWifi,
    'detector' => AppTheme.detector,
    'skySpy' => AppTheme.skySpy,
    'signature' => AppTheme.warning,
    _ => AppTheme.accent,
  };

  Color _colorOf(Map<String, dynamic> d) => d['engine'] == 'signature'
      ? alertKindColor(d['alertClass'] as String?)
      : _engineColor(d['engine'] as String);

  String _labelOf(Map<String, dynamic> d) => d['engine'] == 'signature'
      ? alertKindLabel(d['alertClass'] as String?)
      : _engineLabel(d['engine'] as String);

  String _engineLabel(String engine) => switch (engine) {
    'flockBle' => 'FLOCK BLE',
    'flockWifi' => 'FLOCK WiFi',
    'detector' => 'DETECTOR',
    'skySpy' => 'DRONE',
    'signature' => 'SIGNATURE',
    _ => engine,
  };

  void _toggleSort(_DetSort s) {
    setState(() {
      if (_sort == s) {
        _ascending = !_ascending;
      } else {
        _sort = s;
        _ascending = false;
      }
    });
  }

  Future<void> _showPicker<T>({
    required String title,
    required List<(T, String)> options,
    required T current,
    required ValueChanged<T> onSelected,
  }) {
    final t = AppTheme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: t.textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (val, lbl) in options)
                      ListTile(
                        title: Text(lbl,
                            style: TextStyle(
                                color: val == current
                                    ? AppTheme.accent
                                    : t.textPrimary,
                                fontSize: 14,
                                fontWeight: val == current
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        trailing: val == current
                            ? Icon(Icons.check,
                                size: 18, color: AppTheme.accent)
                            : null,
                        onTap: () {
                          onSelected(val);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMethod() {
    final methods = _detections
        .map((d) => (d['detectionMethod'] as String?) ?? '')
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => _detMethodLabel(a).compareTo(_detMethodLabel(b)));
    return _showPicker<String?>(
      title: 'METHOD',
      current: _methodFilter,
      options: [
        (null, 'ALL'),
        for (final m in methods) (m, _detMethodLabel(m)),
      ],
      onSelected: (v) => setState(() => _methodFilter = v),
    );
  }


  Future<void> _exportCsv(
      BuildContext context, List<Map<String, dynamic>> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      final csv = DetectionsCsv.generate(items.map(detectionFromDbRow));
      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/oui_spy_detections_$ts.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'OUI-SPY Detections Export (${items.length} detections)',
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  int get _activeFilterCount {
    var n = 0;
    if (_engineFilter != null) n++;
    if (_noGpsOnly) n++;
    if (_radioFilter != _RadioSel.all) n++;
    if (_methodFilter != null) n++;
    if (_confFilter != null) n++;
    if (_classFilter != null) n++;
    return n;
  }

  Set<String> _detClasses(Map<String, dynamic> d) {
    final out = <String>{};
    if (d['alertClass'] case final String c when c.isNotEmpty) out.add(c);
    for (final (_, cls)
        in (d['mergedClasses'] as List<(String, String)>?) ?? const <(String, String)>[]) {
      out.add(cls);
    }
    return out;
  }

  int _classCount(String c) =>
      _detections.where((d) => _detClasses(d).contains(c)).length;

  List<String> _classesPresent() {
    final s = <String>{for (final d in _detections) ..._detClasses(d)};
    return s.toList()
      ..sort((a, b) => alertKindLabel(a).compareTo(alertKindLabel(b)));
  }

  int _confCount(FlockConfidence c) =>
      _detections.where((d) => _detFlockConfidence(d) == c).length;

  int _engineCount(String key) => switch (key) {
        'flock' => _detections.where((d) {
            final e = d['engine'] as String;
            return e == 'flockBle' || e == 'flockWifi';
          }).length,
        'detector' => _detections.where((d) => d['engine'] == 'detector').length,
        'drone' => _detections.where((d) => d['engine'] == 'skySpy').length,
        'signature' => _detections.where((d) => d['engine'] == 'signature' || d['mergedClasses'] != null).length,
        _ => _detections.length,
      };

  void _clearFilters() => setState(() {
        _engineFilter = null;
        _noGpsOnly = false;
        _radioFilter = _RadioSel.all;
        _methodFilter = null;
        _confFilter = null;
        _classFilter = null;
      });

  void _toggleSearch() => setState(() {
        _searchOpen = !_searchOpen;
        if (!_searchOpen) {
          _searchCtrl.clear();
          _search = '';
        }
      });

  Future<void> _openFilterSheet() {
    return showCommandSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply(VoidCallback fn) {
            fn();
            setSheet(() {});
          }

          final noGpsCount = _detections
              .where((d) => d['latitude'] == null || d['longitude'] == null)
              .length;

          return CommandSheet(
            title: 'FILTER',
            trailing: _activeFilterCount == 0
                ? null
                : TextButton(
                    onPressed: () => apply(_clearFilters),
                    child: Text(
                      'RESET',
                      style: barLabelStyle(ctx, AppTheme.accent),
                    ),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommandSheetGroup(
                  label: 'SOURCE',
                  child: Wrap(
                    spacing: barGap(ctx),
                    runSpacing: barGap(ctx),
                    children: [
                      CommandChip(
                        label: 'ALL',
                        count: _detections.length,
                        selected: _engineFilter == null,
                        color: AppTheme.accent,
                        onTap: () =>
                            apply(() => setState(() => _engineFilter = null)),
                      ),
                      CommandChip(
                        label: 'FLOCK',
                        count: _engineCount('flock'),
                        selected: _engineFilter == 'flock',
                        color: AppTheme.flockBle,
                        onTap: () => apply(() => setState(() => _engineFilter =
                            _engineFilter == 'flock' ? null : 'flock')),
                      ),
                      CommandChip(
                        label: 'DETECT',
                        count: _engineCount('detector'),
                        selected: _engineFilter == 'detector',
                        color: AppTheme.detector,
                        onTap: () => apply(() => setState(() => _engineFilter =
                            _engineFilter == 'detector' ? null : 'detector')),
                      ),
                      CommandChip(
                        label: 'DRONES',
                        count: _engineCount('drone'),
                        selected: _engineFilter == 'drone',
                        color: AppTheme.skySpy,
                        onTap: () => apply(() => setState(() => _engineFilter =
                            _engineFilter == 'drone' ? null : 'drone')),
                      ),
                      CommandChip(
                        label: 'SIGNATURES',
                        count: _engineCount('signature'),
                        selected: _engineFilter == 'signature',
                        color: AppTheme.warning,
                        onTap: () => apply(() => setState(() => _engineFilter =
                            _engineFilter == 'signature' ? null : 'signature')),
                      ),
                    ],
                  ),
                ),
                CommandSheetGroup(
                  label: 'FLOCK CONFIDENCE',
                  child: Wrap(
                    spacing: barGap(ctx),
                    runSpacing: barGap(ctx),
                    children: [
                      CommandChip(
                        label: 'ALL',
                        selected: _confFilter == null,
                        color: AppTheme.accent,
                        onTap: () =>
                            apply(() => setState(() => _confFilter = null)),
                      ),
                      for (final c in FlockConfidence.values)
                        CommandChip(
                          label: _confShort(c),
                          count: _confCount(c),
                          selected: _confFilter == c,
                          color: _confColor(c),
                          onTap: () => apply(() => setState(
                              () => _confFilter = _confFilter == c ? null : c)),
                        ),
                    ],
                  ),
                ),
                if (_classesPresent().isNotEmpty)
                  CommandSheetGroup(
                    label: 'CLASS',
                    child: Wrap(
                      spacing: barGap(ctx),
                      runSpacing: barGap(ctx),
                      children: [
                        CommandChip(
                          label: 'ALL',
                          selected: _classFilter == null,
                          color: AppTheme.accent,
                          onTap: () =>
                              apply(() => setState(() => _classFilter = null)),
                        ),
                        for (final c in _classesPresent())
                          CommandChip(
                            label: alertKindLabel(c).toUpperCase(),
                            count: _classCount(c),
                            selected: _classFilter == c,
                            color: alertKindColor(c),
                            onTap: () => apply(() => setState(() =>
                                _classFilter = _classFilter == c ? null : c)),
                          ),
                      ],
                    ),
                  ),
                CommandSheetGroup(
                  label: 'RADIO',
                  child: Wrap(
                    spacing: barGap(ctx),
                    runSpacing: barGap(ctx),
                    children: [
                      for (final (sel, label) in const [
                        (_RadioSel.all, 'ALL'),
                        (_RadioSel.ble, 'BLE'),
                        (_RadioSel.wifi, 'WIFI'),
                      ])
                        CommandChip(
                          label: label,
                          selected: _radioFilter == sel,
                          color: switch (sel) {
                            _RadioSel.all => kPillAll,
                            _RadioSel.ble => kPillBle,
                            _RadioSel.wifi => kPillWifi,
                          },
                          onTap: () => apply(
                              () => setState(() => _radioFilter = sel)),
                        ),
                    ],
                  ),
                ),
                CommandSheetGroup(
                  label: 'LOCATION',
                  child: Wrap(
                    spacing: barGap(ctx),
                    runSpacing: barGap(ctx),
                    children: [
                      CommandChip(
                        label: 'ANY',
                        selected: !_noGpsOnly,
                        color: AppTheme.accent,
                        onTap: () =>
                            apply(() => setState(() => _noGpsOnly = false)),
                      ),
                      CommandChip(
                        label: 'NO GPS ONLY',
                        count: noGpsCount,
                        selected: _noGpsOnly,
                        color: AppTheme.gpsNone,
                        onTap: () =>
                            apply(() => setState(() => _noGpsOnly = true)),
                      ),
                    ],
                  ),
                ),
                CommandSheetGroup(
                  label: 'METHOD',
                  child: _DetDropdown(
                    icon: Icons.tune,
                    label: 'METHOD',
                    value: _methodFilter == null
                        ? 'ALL'
                        : _detMethodLabel(_methodFilter!),
                    active: _methodFilter != null,
                    onTap: () async {
                      await _pickMethod();
                      setSheet(() {});
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSortSheet() => showSortSheet<_DetSort>(
        context: context,
        options: _DetSort.values,
        label: (s) => s.label,
        current: () => _sort,
        ascending: () => _ascending,
        hint: () => _sortDirectionHint,
        onPick: _toggleSort,
        onToggleDirection: () => setState(() => _ascending = !_ascending),
      );

  String get _sortDirectionHint => switch ((_sort, _ascending)) {
        (_DetSort.time, true) => 'Oldest first',
        (_DetSort.time, false) => 'Newest first',
        (_DetSort.rssi, true) => 'Weakest signal first',
        (_DetSort.rssi, false) => 'Strongest signal first',
        (_DetSort.mac, true) => 'A → Z',
        (_DetSort.mac, false) => 'Z → A',
      };

  Future<void> _openActionSheet() {
    final items = _filtered;
    return showCommandSheet<void>(
      context: context,
      builder: (ctx) => CommandSheet(
        title: 'ACTIONS',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommandSheetTile(
              icon: _showMap ? Icons.view_list : Icons.map,
              label: _showMap ? 'LIST VIEW' : 'MAP VIEW',
              subtitle: _showMap
                  ? 'Back to the detection list'
                  : 'Plot detections with GPS',
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _showMap = !_showMap);
              },
            ),
            CommandSheetTile(
              icon: _searchOpen ? Icons.search_off : Icons.search,
              label: _searchOpen ? 'CLOSE SEARCH' : 'SEARCH',
              subtitle: 'MAC, name, SSID, method',
              onTap: () {
                Navigator.pop(ctx);
                _toggleSearch();
              },
            ),
            const Divider(height: 1),
            CommandSheetTile(
              icon: Icons.ios_share,
              label: 'EXPORT CSV',
              subtitle: '${items.length} shown',
              onTap: items.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _exportCsv(context, items);
                    },
            ),
            CommandSheetTile(
              icon: Icons.refresh,
              label: 'RESCAN & RECLASSIFY',
              subtitle: 'Re-run OUI matching over stored sessions',
              color: AppTheme.detector,
              onTap: _rescanning
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _rescan();
                    },
            ),
            CommandSheetTile(
              icon: Icons.delete_sweep,
              label: 'CLEAR ALL',
              subtitle: '${_detections.length} detections in database',
              color: AppTheme.error,
              onTap: _detections.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _clearAll();
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(historyFilterRequestProvider, (_, req) {
      if (req == null) return;
      setState(() => _engineFilter = req);
      ref.read(historyFilterRequestProvider.notifier).state = null;
      _load();
    });
    final t = AppTheme.of(context);
    final items = _loading ? const <Map<String, dynamic>>[] : _filtered;
    final hasQuery = _search.trim().isNotEmpty;

    return Column(
      children: [
        CommandHeader(
          title: 'HISTORY',
          count: _activeFilterCount > 0 || hasQuery ? '${items.length}/${_detections.length}' : '${_detections.length}',
          chips: _filterChips(),
          actions: [
            CommandBarAction(
              icon: Icons.filter_alt,
              label: 'Filter',
              active: _activeFilterCount > 0,
              onTap: _detections.isEmpty ? null : _openFilterSheet,
            ),
            CommandBarAction(
              icon: _ascending ? Icons.arrow_upward : Icons.arrow_downward,
              label: 'Sort: ${_sort.label}',
              onTap: _detections.isEmpty ? null : _openSortSheet,
            ),
            if (widget.onShowLive != null)
              CommandBarAction(
                icon: Icons.sensors,
                label: 'Live',
                onTap: widget.onShowLive,
              ),
            CommandBarAction(
              icon: _rescanning ? Icons.hourglass_top : Icons.more_vert,
              label: 'More',
              onTap: _openActionSheet,
            ),
          ],
        ),
        if (_searchOpen) _buildSearchField(t),
        const Divider(height: 1),
        Expanded(child: _buildBody(t, items)),
      ],
    );
  }

  Widget _buildSearchField(ResolvedTheme t) {
    final gap = barGap(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gap * 1.5, gap, gap * 1.5, gap),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _search = v),
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: t.textPrimary),
        decoration: InputDecoration(
          hintText: 'MAC, name, SSID, method…',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: gap * 1.5,
            vertical: gap * 1.5,
          ),
          prefixIcon: Icon(Icons.search, size: barIconSize(context)),
          suffixIcon: IconButton(
            icon: Icon(Icons.close, size: barIconSize(context)),
            onPressed: _toggleSearch,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: t.border),
          ),
        ),
      ),
    );
  }

  List<Widget> _filterChips() {
    return <Widget>[
      if (_engineFilter != null)
        CommandActiveChip(
          label: switch (_engineFilter!) {
            'flock' => 'FLOCK',
            'detector' => 'DETECT',
            'drone' => 'DRONES',
            'signature' => 'SIGNATURES',
            _ => _engineFilter!.toUpperCase(),
          },
          color: switch (_engineFilter!) {
            'flock' => AppTheme.flockBle,
            'detector' => AppTheme.detector,
            'drone' => AppTheme.skySpy,
            'signature' => AppTheme.warning,
            _ => AppTheme.accent,
          },
          onClear: () => setState(() => _engineFilter = null),
        ),
      if (_radioFilter != _RadioSel.all)
        CommandActiveChip(
          label: _radioFilter == _RadioSel.ble ? 'BLE' : 'WIFI',
          color: AppTheme.accent,
          onClear: () => setState(() => _radioFilter = _RadioSel.all),
        ),
      if (_methodFilter != null)
        CommandActiveChip(
          label: _detMethodLabel(_methodFilter!),
          color: AppTheme.accent,
          onClear: () => setState(() => _methodFilter = null),
        ),
      if (_confFilter != null)
        CommandActiveChip(
          label: _confShort(_confFilter!),
          color: _confColor(_confFilter!),
          onClear: () => setState(() => _confFilter = null),
        ),
      if (_noGpsOnly)
        CommandActiveChip(
          label: 'NO GPS',
          color: AppTheme.gpsNone,
          onClear: () => setState(() => _noGpsOnly = false),
        ),
      if (_search.trim().isNotEmpty)
        CommandActiveChip(
          label: '"${_search.trim()}"',
          color: AppTheme.accent,
          onClear: _toggleSearch,
        ),
    ];
  }

  Widget _buildBody(ResolvedTheme t, List<Map<String, dynamic>> items) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.accent, strokeWidth: 2),
      );
    }

    if (_detections.isEmpty) {
      return CommandEmptyState(
        icon: Icons.videocam_off,
        title: 'NO DETECTIONS',
        message:
            'Flock, Detector and Sky Spy hits, and every signature alert you are notified about, are listed here.',
      );
    }

    if (items.isEmpty) {
      return CommandEmptyState(
        icon: Icons.filter_alt_off,
        title: 'NO MATCHES',
        message:
            '${_detections.length} detections stored, none match the current filters.',
        action: TextButton(
          onPressed: () {
            _clearFilters();
            if (_search.trim().isNotEmpty) _toggleSearch();
          },
          child: Text(
            'CLEAR FILTERS',
            style: barLabelStyle(context, AppTheme.accent),
          ),
        ),
      );
    }

    if (_showMap) return _buildMapView(items, t);

    final gap = barGap(context);
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: gap * 1.5, vertical: gap * 0.5),
      itemCount: items.length,
      itemBuilder: (_, i) => _DetectionRow(
        data: items[i],
        onShowMap: () => _showOnMap(items[i]),
        onDelete: _load,
      ),
    );
  }

  Widget _buildMapView(List<Map<String, dynamic>> items, ResolvedTheme t) {
    final geoItems = items
        .where((d) => d['latitude'] != null && d['longitude'] != null)
        .toList();

    if (geoItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 36, color: t.textDim),
            const SizedBox(height: 12),
            Text('NO GPS DATA', style: TextStyle(
              color: t.textDim, fontSize: 12,
              fontWeight: FontWeight.w700, letterSpacing: 2,
            )),
            const SizedBox(height: 6),
            Text(
              'None of the current detections have location data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textDim, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final mapStyle = ref.watch(mapStyleProvider);

    // Compute bounds to fit all markers
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final d in geoItems) {
      final lat = d['latitude'] as double;
      final lon = d['longitude'] as double;
      minLat = min(minLat, lat);
      maxLat = max(maxLat, lat);
      minLon = min(minLon, lon);
      maxLon = max(maxLon, lon);
    }
    final center = LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    final bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));

    final markers = geoItems.map((d) {
      final lat = d['latitude'] as double;
      final lon = d['longitude'] as double;
      final color = _colorOf(d);

      return Marker(
        point: LatLng(lat, lon),
        width: 28,
        height: 28,
        child: GestureDetector(
          onTap: () => _showMarkerSheet(d),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.25),
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.8),
                  border: Border.all(color: color, width: 1.5),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    // Fit bounds after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && geoItems.length > 1) {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40),
        ));
      }
    });

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: geoItems.length == 1 ? 16 : 13,
        backgroundColor: mapStyle.isDark ? Colors.black : Colors.white,
      ),
      children: [
        mapTileLayer(mapStyle),
        MarkerLayer(markers: markers),
        mapAttribution(mapStyle),
      ],
    );
  }

  void _showMarkerSheet(Map<String, dynamic> det) {
    final t = AppTheme.of(context);
    final mac = (det['macAddress'] as String).toUpperCase();
    final deviceName = det['deviceName'] as String? ?? '';
    final ssid = det['ssid'] as String? ?? '';
    final rssi = det['rssi'] as int;
    final channel = det['channel'] as int? ?? 0;
    final method = det['detectionMethod'] as String? ?? '';
    final ts = DateTime.fromMillisecondsSinceEpoch(det['appTimestamp'] as int);
    final timeStr = AppTime.dateTime(ts);
    final vendor = ref.read(ouiLookupProvider).lookup(mac);
    final lat = det['latitude'] as double?;
    final lon = det['longitude'] as double?;

    showModalBottomSheet(
      context: context,
      backgroundColor: t.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: _colorOf(det),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(mac, style: TextStyle(
                    color: t.textPrimary, fontSize: 14,
                    fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
                  )),
                ),
              ],
            ),
            if (vendor != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 18),
                child: Text(vendor, style: TextStyle(
                  color: _colorOf(det).withValues(alpha: 0.8),
                  fontSize: 12,
                )),
              ),
            if (deviceName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 18),
                child: Text(deviceName, style: TextStyle(
                  color: t.textSecondary, fontSize: 11,
                )),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.surfaceLight,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                children: [
                  _markerDetailRow('Engine', _labelOf(det), t),
                  if (method.isNotEmpty) _markerDetailRow('Method', method, t),
                  _markerDetailRow('RSSI', '$rssi dBm', t),
                  if (channel > 0) _markerDetailRow('Channel', '$channel', t),
                  if (ssid.isNotEmpty) _markerDetailRow('SSID', ssid, t),
                  _markerDetailRow('Time', timeStr, t),
                  if (lat != null && lon != null)
                    _markerDetailRow('Location',
                        '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}', t),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: mac));
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('MAC copied'),
                          backgroundColor: t.surface,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(Icons.copy, size: 14, color: t.textDim),
                    label: Text('Copy MAC', style: TextStyle(
                      color: t.textSecondary, fontSize: 11,
                    )),
                  ),
                ),
                Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startFoxhunt(det);
                      },
                      icon: Icon(Icons.gps_fixed, size: 14,
                          color: AppTheme.foxhunter),
                      label: Text('Foxhunt', style: TextStyle(
                        color: AppTheme.foxhunter, fontSize: 11,
                      )),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _markerDetailRow(String label, String value, ResolvedTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(
              color: t.textDim, fontSize: 10, fontWeight: FontWeight.w500,
            )),
          ),
          Expanded(
            child: Text(value, style: TextStyle(
              color: t.textPrimary, fontSize: 10, fontFamily: AppTheme.mono,
            )),
          ),
        ],
      ),
    );
  }

  void _showOnMap(Map<String, dynamic> det) {
    final lat = det['latitude'] as double?;
    final lon = det['longitude'] as double?;
    final sid = det['sessionId'] as String;

    final wd = ref.read(wardriveProvider);
    if (wd.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop active wardrive first')),
      );
      return;
    }

    wd.loadSession(sid).then((_) {
      if (lat != null && lon != null) {
        wd.requestZoom(lat, lon, detection: detectionFromDbRow(det));
      }
      if (mounted) context.go('/wardrive');
    });
  }

  void _startFoxhunt(Map<String, dynamic> det) {
    final mac = det['macAddress'] as String;
    final channel = det['channel'] as int? ?? 0;


    ref.read(appStateProvider).setFoxhunterTarget(
      mac,
      channel: channel,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.foxhunter,
          content: Text('Foxhunting ${mac.toUpperCase().substring(0, 8)}...'),
        ),
      );
    }
  }
}

class _DetDropdown extends StatelessWidget {
  const _DetDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    final iconSize = barIconSize(context);
    return Material(
      color: active ? AppTheme.accent.withValues(alpha: 0.12) : t.surfaceLight,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension),
          padding: EdgeInsets.symmetric(horizontal: gap * 1.5, vertical: gap),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? AppTheme.accent : t.border,
              width: active ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: iconSize, color: active ? AppTheme.accent : t.textDim),
              SizedBox(width: gap),
              Text(label, style: barLabelStyle(context, t.textDim)),
              SizedBox(width: gap),
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: barLabelStyle(
                      context, active ? AppTheme.accent : t.textPrimary),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: iconSize, color: t.textDim),
            ],
          ),
        ),
      ),
    );
  }
}


class _DetectionRow extends ConsumerWidget {
  const _DetectionRow({
    required this.data,
    required this.onShowMap,
    required this.onDelete,
  });
  final Map<String, dynamic> data;
  final VoidCallback onShowMap;
  final VoidCallback onDelete;

  void _showDetailSheet(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    showDetectionDetails(
      context,
      ref,
      detectionFromDbRow(data),
      onShowMap: onShowMap,
      onDelete: () {
        final db = ref.read(databaseProvider);
        final id = data['id'] as int;
        final messenger = ScaffoldMessenger.of(context);
        (data['engine'] == 'signature'
                ? db.deleteClassAlerts(data['macAddress'] as String, data['alertClass'] as String)
                : Future.wait([
                    db.deleteDetectionById(id),
                    for (final (mac, cls) in (data['mergedClasses'] as List<(String, String)>?) ??
                        const <(String, String)>[])
                      db.deleteClassAlerts(mac, cls),
                  ]))
            .then((_) {
          onDelete();
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Detection removed'),
              backgroundColor: t.surface,
              duration: const Duration(seconds: 1),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DetectionRow(
      detection: detectionFromDbRow(data),
      onActivate: _showDetailSheet,
    );
  }

}

