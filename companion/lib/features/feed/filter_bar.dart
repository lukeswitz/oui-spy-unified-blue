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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: TextField(
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'MAC, name, method...',
                prefixIcon: const Icon(Icons.search, size: 16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 24,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...Engine.values.map((engine) {
                  final active = activeFilters.contains(engine);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
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
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: active
                              ? engine.color.withValues(alpha: 0.2)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: active
                                ? engine.color.withValues(alpha: 0.5)
                                : AppTheme.border,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          engine.label.toUpperCase(),
                          style: TextStyle(
                            color: active ? engine.color : AppTheme.textDim,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (sourceNodes.isNotEmpty && onNodeChanged != null) ...[
                  Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    color: AppTheme.border,
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
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.warning.withValues(alpha: 0.2)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active
                  ? AppTheme.warning.withValues(alpha: 0.5)
                  : AppTheme.border,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != 'ALL' && label != 'LOCAL')
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(Icons.hub, size: 8, color: AppTheme.warning),
                ),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppTheme.warning : AppTheme.textDim,
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
