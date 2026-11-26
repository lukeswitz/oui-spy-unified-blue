// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DStatsStrip extends StatelessWidget {
  const DStatsStrip({super.key, required this.items, this.onTap});
  final List<(String value, String label)> items;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    final labelStyle = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .merge(TextStyle(color: t.textSecondary, fontSize: 12));
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        var need = 0.0;
        for (final item in items) {
          final tp = TextPainter(
            text: TextSpan(text: item.$2, style: labelStyle),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          if (tp.width + 24 > need) need = tp.width + 24;
        }
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : need * items.length;
        var cols = items.isEmpty ? 1 : items.length;
        while (cols > 1 && (maxW - gap * (cols - 1)) / cols < need) {
          cols--;
        }
        final tileW = (maxW - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: tileW,
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
                            style: labelStyle,
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
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
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
        );
      },
    );
  }
}
