import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DUnderlineTabs<T> extends StatelessWidget {
  const DUnderlineTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.counts = const {},
    this.trailing = const [],
  });

  final List<(T value, String label)> items;
  final T selected;
  final ValueChanged<T> onSelect;
  final Map<T, int> counts;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (value, label) in items)
                    Semantics(
                      button: true,
                      selected: value == selected,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(value),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
                          margin: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: value == selected ? t.textPrimary : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: labelStyle?.copyWith(
                                  color: value == selected ? t.textPrimary : t.textDim,
                                ),
                              ),
                              if (counts[value] != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${counts[value]}',
                                  style: TextStyle(
                                    fontFamily: AppTheme.mono,
                                    fontSize: 12,
                                    color: t.textDim,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
