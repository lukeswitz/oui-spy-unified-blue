import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DSpecRow extends StatelessWidget {
  const DSpecRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.onTap,
    this.divider = true,
  });
  final String label;
  final String value;
  final bool mono;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: divider
            ? BoxDecoration(border: Border(bottom: BorderSide(color: t.border)))
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 42,
              child: Text(label, style: style?.copyWith(color: t.textSecondary)),
            ),
            Expanded(
              flex: 58,
              child: Text(
                value,
                style: style?.copyWith(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontFamily: mono ? AppTheme.mono : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
