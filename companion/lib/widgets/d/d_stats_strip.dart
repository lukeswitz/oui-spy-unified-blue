import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DStatsStrip extends StatelessWidget {
  const DStatsStrip({super.key, required this.items, this.onTap});
  final List<(String value, String label)> items;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: t.surface,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap == null ? null : () => onTap!(i),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          items[i].$1,
                          maxLines: 1,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppTheme.mono,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
