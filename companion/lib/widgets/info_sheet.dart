import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

void showInfoSheet(BuildContext context, ResolvedTheme t, String title, List<String> lines) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surface,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l,
                          style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.35)),
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
