import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

double barIconSize(BuildContext context) {
  final base = Theme.of(context).textTheme.labelMedium?.fontSize ?? 12;
  final scaled = MediaQuery.textScalerOf(context).scale(base);
  return scaled.clamp(base, base * 1.5) * 1.7;
}

double barGap(BuildContext context, [double m = 1]) =>
    barIconSize(context) * 0.35 * m;

final kPillPalette =<Color>[
  AppTheme.accent,
  AppTheme.flockBle,
  AppTheme.wardrive,
  AppTheme.skySpy,
  AppTheme.flockWifi,
  AppTheme.foxhunter,
  AppTheme.warning,
  AppTheme.wdgwars,
  AppTheme.wdgwarsAlt,
  AppTheme.error,
];

Color pillColor(int i) => kPillPalette[i % kPillPalette.length];

final kPillAll =AppTheme.accent;
Color get kPillBle => AppTheme.flockBle;
Color get kPillWifi => AppTheme.wardrive;

(String, Color) wifiAuthMeta(int mode) => switch (mode) {
      0 => ('OPEN', AppTheme.error),
      1 => ('WEP', AppTheme.warning),
      2 => ('WPA', AppTheme.warning),
      3 => ('WPA2', AppTheme.success),
      4 => ('WPA/2', AppTheme.success),
      5 => ('ENT', AppTheme.accent),
      6 => ('WPA3', AppTheme.success),
      _ => ('WPA2', AppTheme.success),
    };

TextStyle barLabelStyle(BuildContext context, Color color,
    {bool bold = true}) {
  final base = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
  return base.copyWith(
    color: color,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
    letterSpacing: 0.8,
  );
}

TextStyle barLeadingStyle(BuildContext context, Color color) {
  final base = Theme.of(context).textTheme.titleSmall ?? const TextStyle();
  return base.copyWith(
    color: color,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}

class CommandBarAction {
  const CommandBarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
}

class CommandBarLeading {
  const CommandBarLeading({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

double _measureLabel(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

class BarLayout {
  const BarLayout({
    required this.flex,
    required this.padScale,
    required this.showLeadingLabel,
    required this.showActionLabels,
  });

  final List<int> flex;
  final double padScale;
  final bool showLeadingLabel;
  final bool showActionLabels;

  static const _rungs = <(double, bool, bool)>[
    (1.4, true, true),
    (0.7, true, true),
    (0.4, true, true),
    (1.0, true, false),
    (0.5, true, false),
    (0.4, false, false),
  ];

  static BarLayout resolve(
    BuildContext context, {
    required double available,
    required String? leadingLabel,
    required List<CommandBarAction> actions,
  }) {
    final iconSize = barIconSize(context);
    final gap = barGap(context);
    final style = barLabelStyle(context, const Color(0xFF000000));
    final leadStyle = barLeadingStyle(context, const Color(0xFF000000));
    final cellCount = actions.length + (leadingLabel == null ? 0 : 1);
    final budget = available - cellCount - 2;

    List<double> widths(
        double padScale, bool leadingLabelOn, bool actionLabelsOn) {
      final padding = barGap(context, padScale) * 2;
      double cell(String label, TextStyle labelStyle,
          {required bool withLabel, required bool withChevron}) {
        var w = padding + iconSize;
        if (withLabel) w += gap + _measureLabel(context, label, labelStyle);
        if (withChevron) w += gap * 0.5 + iconSize;
        return w;
      }

      return [
        if (leadingLabel != null)
          cell(leadingLabel, leadStyle,
                  withLabel: leadingLabelOn, withChevron: true) +
              gap * 2.4 +
              2,
        for (final a in actions)
          cell(a.label, style, withLabel: actionLabelsOn, withChevron: false),
      ];
    }

    double total(List<double> w) => w.fold(0.0, (a, b) => a + b);

    var chosen = _rungs.last;
    var w = widths(chosen.$1, chosen.$2, chosen.$3);
    for (final rung in _rungs) {
      final candidate = widths(rung.$1, rung.$2, rung.$3);
      if (total(candidate) <= budget) {
        chosen = rung;
        w = candidate;
        break;
      }
    }

    final sum = total(w);
    return BarLayout(
      flex: [
        for (final e in w) (e / sum * 10000).ceil().clamp(1, 1 << 24),
      ],
      padScale: chosen.$1,
      showLeadingLabel: chosen.$2,
      showActionLabels: chosen.$3,
    );
  }
}

class CommandBar extends StatelessWidget {
  const CommandBar({
    super.key,
    this.leading,
    this.actions = const <CommandBarAction>[],
  });

  final CommandBarLeading? leading;
  final List<CommandBarAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = BarLayout.resolve(
              context,
              available: constraints.maxWidth,
              leadingLabel: leading?.label,
              actions: actions,
            );
            var cell = 0;
            return Row(
              children: [
                if (leading != null)
                  Expanded(
                    flex: layout.flex[cell++],
                    child: CommandBarLeadingButton(
                      leading: leading!,
                      showLabel: layout.showLeadingLabel,
                      padScale: layout.padScale,
                    ),
                  ),
                for (int i = 0; i < actions.length; i++)
                  Expanded(
                    flex: layout.flex[cell++],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: i == 0 && leading == null
                            ? null
                            : Border(left: BorderSide(color: t.border)),
                      ),
                      child: CommandBarButton(
                        action: actions[i],
                        showLabel: layout.showActionLabels,
                        padScale: layout.padScale,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CommandBarTap extends StatelessWidget {
  const CommandBarTap({
    super.key,
    required this.onTap,
    required this.child,
    this.padScale = 1.4,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double padScale;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: barGap(context, padScale),
            vertical: barGap(context, 0.8),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class CommandBarLeadingButton extends StatelessWidget {
  const CommandBarLeadingButton({
    super.key,
    required this.leading,
    required this.showLabel,
    this.padScale = 1.4,
  });

  final CommandBarLeading leading;
  final bool showLabel;
  final double padScale;

  @override
  Widget build(BuildContext context) {
    final iconSize = barIconSize(context);
    final gap = barGap(context);
    return CommandBarTap(
      onTap: leading.onTap,
      padScale: padScale,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: gap * 1.2,
          vertical: gap * 0.6,
        ),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(gap * 1.5),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leading.icon, size: iconSize, color: AppTheme.accent),
            if (showLabel) ...[
              SizedBox(width: gap),
              Flexible(
                child: Text(
                  leading.label,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: barLeadingStyle(context, AppTheme.accent),
                ),
              ),
            ],
            SizedBox(width: gap * 0.5),
            Icon(Icons.expand_less, size: iconSize, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}

class CommandBarButton extends StatelessWidget {
  const CommandBarButton({
    super.key,
    required this.action,
    this.showLabel = true,
    this.padScale = 1.4,
  });

  final CommandBarAction action;
  final bool showLabel;
  final double padScale;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final tint = action.color ?? AppTheme.accent;
    final fg = action.onTap == null
        ? t.textDim.withValues(alpha: 0.4)
        : (action.active ? tint : t.textSecondary);
    final iconSize = barIconSize(context);
    final glyph = Icon(action.icon, size: iconSize, color: fg);
    return CommandBarTap(
      onTap: action.onTap,
      padScale: padScale,
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                glyph,
                SizedBox(width: barGap(context)),
                Flexible(
                  child: Text(
                    action.label,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: barLabelStyle(context, fg),
                  ),
                ),
              ],
            )
          : glyph,
    );
  }
}


class CommandSheet extends StatelessWidget {
  const CommandSheet({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: Container(
                width: barIconSize(context) * 2,
                height: gap * 0.4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(gap),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(gap * 2, gap * 1.5, gap * 0.5, gap),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: barLabelStyle(context, t.textDim)
                          .copyWith(letterSpacing: 2.5),
                    ),
                  ),
                  ?trailing,
                  IconButton(
                    icon: Icon(Icons.close,
                        size: barIconSize(context), color: t.textDim),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(gap * 2),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showCommandSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteSettings? routeSettings,
}) {
  final t = AppTheme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    routeSettings: routeSettings,
    backgroundColor: t.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: builder,
  );
}

class CommandSheetTile extends StatelessWidget {
  const CommandSheetTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final fg = onTap == null
        ? t.textDim.withValues(alpha: 0.4)
        : (color ?? t.textPrimary);
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: barGap(context),
      leading: Icon(icon, size: barIconSize(context), color: fg),
      title: Text(
        label,
        style: barLabelStyle(context, fg).copyWith(letterSpacing: 1),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: (Theme.of(context).textTheme.bodySmall ??
                      const TextStyle())
                  .copyWith(color: t.textDim),
            ),
      trailing: trailing,
    );
  }
}

class CommandSheetGroup extends StatelessWidget {
  const CommandSheetGroup({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: gap, top: gap * 0.5),
          child: Text(
            label,
            style: barLabelStyle(context, t.textDim).copyWith(letterSpacing: 2),
          ),
        ),
        child,
        SizedBox(height: gap * 1.5),
      ],
    );
  }
}

class CommandChip extends StatelessWidget {
  const CommandChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final gap = barGap(context);
    final radius = BorderRadius.circular(kMinInteractiveDimension);
    return Material(
      color: selected
          ? color.withValues(alpha: 0.22)
          : color.withValues(alpha: 0.06),
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension * 0.8),
          padding: EdgeInsets.symmetric(
            horizontal: gap * 1.75,
            vertical: gap,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.55),
              width: selected ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: barLabelStyle(context, color)),
              if (count != null) ...[
                SizedBox(width: gap * 0.75),
                Text(
                  '$count',
                  style: barLabelStyle(
                    context,
                    color.withValues(alpha: 0.65),
                    bold: false,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CommandActiveChip extends StatelessWidget {
  const CommandActiveChip({
    super.key,
    required this.label,
    required this.color,
    required this.onClear,
  });

  final String label;
  final Color color;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final gap = barGap(context);
    final radius = BorderRadius.circular(kMinInteractiveDimension);
    return Material(
      color: color.withValues(alpha: 0.18),
      borderRadius: radius,
      child: InkWell(
        onTap: onClear,
        borderRadius: radius,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension * 0.65),
          padding: EdgeInsets.fromLTRB(gap * 1.5, gap * 0.5, gap, gap * 0.5),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: barLabelStyle(context, color),
                ),
              ),
              SizedBox(width: gap * 0.5),
              Icon(Icons.close, size: barIconSize(context) * 0.8, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSortSheet<T>({
  required BuildContext context,
  required List<T> options,
  required String Function(T) label,
  required T Function() current,
  required bool Function() ascending,
  required void Function(T) onPick,
  required VoidCallback onToggleDirection,
  String Function()? hint,
}) {
  return showCommandSheet<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => CommandSheet(
        title: 'SORT',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommandSheetGroup(
              label: 'ORDER BY',
              child: Wrap(
                spacing: barGap(ctx),
                runSpacing: barGap(ctx),
                children: [
                  for (var i = 0; i < options.length; i++)
                    CommandChip(
                      label: label(options[i]),
                      selected: current() == options[i],
                      color: pillColor(i),
                      onTap: () {
                        onPick(options[i]);
                        setSheet(() {});
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            CommandSheetTile(
              icon: ascending() ? Icons.arrow_upward : Icons.arrow_downward,
              label: ascending() ? 'ASCENDING' : 'DESCENDING',
              subtitle: hint?.call(),
              color: AppTheme.accent,
              onTap: () {
                onToggleDirection();
                setSheet(() {});
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class CommandHeader extends StatelessWidget {
  const CommandHeader({
    super.key,
    required this.title,
    required this.count,
    this.chips = const [],
    this.indicators = const [],
    this.actions = const <CommandBarAction>[],
  });

  final String title;
  final String count;
  final List<Widget> chips;
  final List<Widget> indicators;
  final List<CommandBarAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    final style = Theme.of(context).textTheme.titleSmall;
    return Padding(
      padding: EdgeInsets.fromLTRB(gap * 2, gap * 1.5, gap * 2, gap * 1.5),
      child: Row(
        children: [
          Text(title, style: style?.copyWith(letterSpacing: 3, color: t.textDim, fontWeight: FontWeight.w700)),
          SizedBox(width: gap),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(spacing: gap * 0.75, children: chips),
            ),
          ),
          for (final i in indicators) ...[i, SizedBox(width: gap * 0.5)],
          Text(
            count,
            style: style?.copyWith(color: AppTheme.accent, fontFamily: 'monospace', fontWeight: FontWeight.w700),
          ),
          if (actions.isNotEmpty) SizedBox(width: gap * 0.5),
          for (final a in actions)
            IconButton(
              tooltip: a.label,
              onPressed: a.onTap,
              visualDensity: VisualDensity.compact,
              icon: Icon(a.icon, size: barIconSize(context)),
              color: a.color ?? (a.active ? AppTheme.accent : t.textSecondary),
            ),
        ],
      ),
    );
  }
}

class CommandEmptyState extends StatelessWidget {
  const CommandEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap * 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: barIconSize(context) * 3, color: t.textDim),
            SizedBox(height: gap * 1.5),
            Text(
              title,
              style: barLabelStyle(context, t.textDim)
                  .copyWith(letterSpacing: 2),
            ),
            SizedBox(height: gap * 0.75),
            Text(
              message,
              textAlign: TextAlign.center,
              style: (Theme.of(context).textTheme.bodySmall ??
                      const TextStyle())
                  .copyWith(color: t.textDim),
            ),
            if (action != null) ...[
              SizedBox(height: gap),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class CommandSearchField extends StatelessWidget {
  const CommandSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(gap * 1.5, gap, gap * 1.5, gap),
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: t.textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: gap * 1.5,
            vertical: gap * 1.5,
          ),
          prefixIcon: Icon(Icons.search, size: barIconSize(context)),
          suffixIcon: IconButton(
            icon: Icon(Icons.close, size: barIconSize(context)),
            onPressed: onClose,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(gap),
            borderSide: BorderSide(color: t.border),
          ),
        ),
      ),
    );
  }
}
