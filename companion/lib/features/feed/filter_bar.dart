import 'package:flutter/material.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/feed/feed_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';

enum RadioFilter { ble, wifi }

enum FilterPreset {
  all('ALL', null, null),
  ble('BLE', _bleEngines, RadioFilter.ble),
  wifi('WIFI', _wifiEngines, RadioFilter.wifi),
  flock('FLOCK', _flockEngines, null),
  alerts('ALERTS', _alertEngines, null);

  const FilterPreset(this.label, this.engines, this.radio);
  final String label;
  final Set<Engine>? engines;
  final RadioFilter? radio;

  static const _bleEngines = {
    Engine.detector,
    Engine.flockBle,
    Engine.foxhunter,
    Engine.uniPwn,
    Engine.wardrive,
  };
  static const _wifiEngines = {
    Engine.detector,
    Engine.flockWifi,
    Engine.foxhunter,
    Engine.skySpy,
    Engine.wardrive,
  };
  static const _flockEngines = {Engine.flockBle, Engine.flockWifi};
  static const _alertEngines = {Engine.detector};

  Set<Engine> resolve() => engines ?? Engine.values.toSet();

  bool matches(Set<Engine> active, RadioFilter? activeRadio) {
    if (radio != activeRadio) return false;
    final target = resolve();
    return active.length == target.length && active.containsAll(target);
  }
}

class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.activeFilters,
    required this.activeRadio,
    required this.searchQuery,
    required this.onFiltersChanged,
    required this.onPresetApplied,
    required this.onSearchChanged,
    required this.sortMetric,
    required this.sortAscending,
    required this.onSortChanged,
    this.sourceNodes = const {},
    this.selectedNode,
    this.onNodeChanged,
    this.labelForNode,
  });

  final Set<Engine> activeFilters;
  final RadioFilter? activeRadio;
  final String searchQuery;
  final ValueChanged<Set<Engine>> onFiltersChanged;
  final ValueChanged<FilterPreset> onPresetApplied;
  final ValueChanged<String> onSearchChanged;
  final FeedMetric sortMetric;
  final bool sortAscending;
  final void Function(FeedMetric metric, bool ascending) onSortChanged;
  final Set<String> sourceNodes;
  final String? selectedNode;
  final ValueChanged<String?>? onNodeChanged;
  final String Function(String id)? labelForNode;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  bool _searchOpen = false;
  late final TextEditingController _searchCtrl =
      TextEditingController(text: widget.searchQuery);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(FilterPreset preset) {
    widget.onPresetApplied(preset);
  }

  String _nodeLabel() {
    if (widget.selectedNode == null) return 'ALL';
    if (widget.selectedNode!.isEmpty) return 'LOCAL';
    final fn = widget.labelForNode;
    return fn != null ? fn(widget.selectedNode!) : widget.selectedNode!;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final activeCount = widget.activeFilters.length;
    final allEngines = Engine.values.length;
    final enginesLabel = activeCount == allEngines
        ? 'ALL'
        : activeCount == 0
            ? 'NONE'
            : '$activeCount';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final preset in FilterPreset.values)
                _PresetChip(
                  label: preset.label,
                  active: preset.matches(widget.activeFilters, widget.activeRadio),
                  onTap: () => _applyPreset(preset),
                ),
              _Divider(t: t),
              _DropdownButton(
                icon: Icons.tune,
                label: 'ENGINES',
                value: enginesLabel,
                accent: AppTheme.accent,
                onTap: () => _showEnginesMenu(context),
              ),
              if (widget.sourceNodes.isNotEmpty && widget.onNodeChanged != null)
                _DropdownButton(
                  icon: Icons.hub,
                  label: 'SOURCE',
                  value: _nodeLabel(),
                  accent: AppTheme.warning,
                  onTap: () => _showNodeMenu(context),
                ),
              _DropdownButton(
                icon: Icons.sort,
                label: 'SORT',
                value:
                    '${widget.sortMetric.label}${widget.sortAscending ? ' ↑' : ' ↓'}',
                accent: AppTheme.accent,
                onTap: () => _showSortMenu(context),
              ),
              _IconToggle(
                icon: _searchOpen ? Icons.search_off : Icons.search,
                active: _searchOpen || widget.searchQuery.isNotEmpty,
                onTap: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    widget.onSearchChanged('');
                  }
                }),
              ),
            ],
          ),
          if (_searchOpen) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: widget.onSearchChanged,
                style: TextStyle(fontSize: 12, color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: 'MAC, name, method, node…',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: t.border),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showEnginesMenu(BuildContext context) async {
    final t = AppTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final active = Set<Engine>.from(widget.activeFilters);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('ENGINES',
                          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              letterSpacing: 3, color: t.textDim)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          widget.onFiltersChanged(Engine.values.toSet());
                          setSheet(() {});
                        },
                        child: const Text('ALL',
                            style: TextStyle(fontSize: 11, letterSpacing: 1)),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.onFiltersChanged(<Engine>{});
                          setSheet(() {});
                        },
                        child: const Text('NONE',
                            style: TextStyle(fontSize: 11, letterSpacing: 1)),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final engine in Engine.values)
                          CheckboxListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: engine.color,
                            value: active.contains(engine),
                            onChanged: (v) {
                              final next =
                                  Set<Engine>.from(widget.activeFilters);
                              if (v ?? false) {
                                next.add(engine);
                              } else {
                                next.remove(engine);
                              }
                              widget.onFiltersChanged(next);
                              setSheet(() {});
                            },
                            title: Row(
                              children: [
                                Icon(engine.icon,
                                    size: 14, color: engine.color),
                                const SizedBox(width: 8),
                                Text(engine.label.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 1,
                                        color: t.textPrimary)),
                              ],
                            ),
                            subtitle: Text(engine.description,
                                style: TextStyle(
                                    fontSize: 10, color: t.textDim)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showNodeMenu(BuildContext context) async {
    final t = AppTheme.of(context);
    final entries = <_NodeEntry>[
      const _NodeEntry(null, 'ALL'),
      const _NodeEntry('', 'LOCAL'),
      ...widget.sourceNodes.map((n) => _NodeEntry(n, widget.labelForNode?.call(n) ?? n)),
    ];
    await showMenu<String?>(
      context: context,
      position: _menuPositionFromOverlay(context),
      color: t.surface,
      items: [
        for (final e in entries)
          PopupMenuItem<String?>(
            value: e.id,
            child: Row(
              children: [
                Icon(
                  e.id == null
                      ? Icons.public
                      : e.id!.isEmpty
                          ? Icons.smartphone
                          : Icons.hub,
                  size: 14,
                  color: widget.selectedNode == e.id
                      ? AppTheme.warning
                      : t.textDim,
                ),
                const SizedBox(width: 8),
                Text(e.label,
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        color: widget.selectedNode == e.id
                            ? AppTheme.warning
                            : t.textPrimary)),
              ],
            ),
          ),
      ],
    ).then((v) {
      if (v != null || widget.selectedNode != null) {
        widget.onNodeChanged?.call(v);
      }
    });
  }

  Future<void> _showSortMenu(BuildContext context) async {
    final t = AppTheme.of(context);
    await showMenu<_SortChoice>(
      context: context,
      position: _menuPositionFromOverlay(context),
      color: t.surface,
      items: [
        for (final m in FeedMetric.values) ...[
          PopupMenuItem<_SortChoice>(
            value: _SortChoice(m, false),
            child: _sortRow(t, m, false),
          ),
          PopupMenuItem<_SortChoice>(
            value: _SortChoice(m, true),
            child: _sortRow(t, m, true),
          ),
        ],
      ],
    ).then((v) {
      if (v != null) widget.onSortChanged(v.metric, v.asc);
    });
  }

  Widget _sortRow(ResolvedTheme t, FeedMetric m, bool asc) {
    final active =
        widget.sortMetric == m && widget.sortAscending == asc;
    return Row(
      children: [
        Icon(asc ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: active ? AppTheme.accent : t.textDim),
        const SizedBox(width: 8),
        Text('${m.label} ${asc ? 'ASC' : 'DESC'}',
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 1,
                color: active ? AppTheme.accent : t.textPrimary)),
      ],
    );
  }
}

RelativeRect _menuPositionFromOverlay(BuildContext context) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final box = context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight =
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  return RelativeRect.fromLTRB(
    topLeft.dx,
    bottomRight.dy,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - bottomRight.dy,
  );
}

class _NodeEntry {
  const _NodeEntry(this.id, this.label);
  final String? id;
  final String label;
}

class _SortChoice {
  const _SortChoice(this.metric, this.asc);
  final FeedMetric metric;
  final bool asc;

  @override
  bool operator ==(Object other) =>
      other is _SortChoice && other.metric == metric && other.asc == asc;
  @override
  int get hashCode => Object.hash(metric, asc);
}

class _PresetChip extends StatelessWidget {
  const _PresetChip(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.18)
              : t.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.7)
                : t.border,
            width: active ? 1.2 : 0.6,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppTheme.accent : t.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownButton extends StatelessWidget {
  const _DropdownButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border, width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: t.textDim),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: t.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                )),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace',
                )),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: t.textDim),
          ],
        ),
      ),
    );
  }
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.18)
              : t.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.6)
                : t.border,
            width: active ? 1.2 : 0.6,
          ),
        ),
        child: Icon(icon,
            size: 18, color: active ? AppTheme.accent : t.textDim),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.t});
  final ResolvedTheme t;
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: t.border,
      );
}
