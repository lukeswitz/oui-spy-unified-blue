import 'package:flutter/material.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.activeFilters,
    required this.searchQuery,
    required this.onFiltersChanged,
    required this.onSearchChanged,
    this.sourceNodes = const {},
    this.selectedNode,
    this.onNodeChanged,
  });

  final Set<Engine> activeFilters;
  final String searchQuery;
  final ValueChanged<Set<Engine>> onFiltersChanged;
  final ValueChanged<String> onSearchChanged;
  final Set<String> sourceNodes;
  final String? selectedNode;
  final ValueChanged<String?>? onNodeChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: TextField(
              onChanged: onSearchChanged,
              style: TextStyle(fontSize: 12, color: t.textPrimary),
              decoration: InputDecoration(
                hintText: 'MAC, name, method...',
                prefixIcon: const Icon(Icons.search, size: 16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: t.border),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              ...Engine.values.map((engine) {
                final active = activeFilters.contains(engine);
                final chipBg = isLight
                    ? (active ? engine.color : const Color(0xFF2A2D3A))
                    : (active
                        ? engine.color.withValues(alpha: 0.2)
                        : t.surface);
                final chipBorder = isLight
                    ? (active ? engine.color : const Color(0xFF2A2D3A))
                    : (active
                        ? engine.color.withValues(alpha: 0.6)
                        : t.border);
                final chipText = isLight
                    ? Colors.white
                    : (active ? engine.color : t.textSecondary);
                final chipIcon = isLight
                    ? Colors.white
                    : (active ? engine.color : t.textSecondary);
                return GestureDetector(
                  onTap: () {
                    final newFilters = Set<Engine>.from(activeFilters);
                    if (active) {
                      newFilters.remove(engine);
                    } else {
                      newFilters.add(engine);
                    }
                    onFiltersChanged(newFilters);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: chipBorder,
                        width: active ? 1.0 : 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          engine.icon,
                          size: 10,
                          color: chipIcon,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          engine.label.toUpperCase(),
                          style: TextStyle(
                            color: chipText,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (sourceNodes.isNotEmpty && onNodeChanged != null) ...[
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: t.border,
                ),
                _NodeFilterChip(
                  label: 'ALL',
                  active: selectedNode == null,
                  onTap: () => onNodeChanged!(null),
                ),
                _NodeFilterChip(
                  label: 'LOCAL',
                  active: selectedNode == '',
                  onTap: () => onNodeChanged!(''),
                ),
                ...sourceNodes.map((nodeId) => _NodeFilterChip(
                  label: nodeId,
                  active: selectedNode == nodeId,
                  onTap: () => onNodeChanged!(nodeId),
                )),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NodeFilterChip extends StatelessWidget {
  const _NodeFilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final chipBg = isLight
        ? (active ? AppTheme.warning : const Color(0xFF2A2D3A))
        : (active ? AppTheme.warning.withValues(alpha: 0.2) : t.surface);
    final chipBorder = isLight
        ? (active ? AppTheme.warning : const Color(0xFF2A2D3A))
        : (active ? AppTheme.warning.withValues(alpha: 0.5) : t.border);
    final chipText = isLight
        ? Colors.white
        : (active ? AppTheme.warning : t.textDim);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: chipBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != 'ALL' && label != 'LOCAL')
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Icon(Icons.hub, size: 8, color: chipText),
                ),
              Text(
                label,
                style: TextStyle(
                  color: chipText,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
