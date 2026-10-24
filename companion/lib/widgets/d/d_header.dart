import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DEyebrow extends StatelessWidget {
  const DEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color ?? t.textSecondary),
    );
  }
}

class DPageTitle extends StatelessWidget {
  const DPageTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.displaySmall?.copyWith(color: t.textPrimary),
    );
  }
}

class DSectionHeader extends StatelessWidget {
  const DSectionHeader({super.key, required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: TextStyle(color: t.textSecondary, fontSize: 13),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}
