import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';

class ConfigSectionHeader extends StatelessWidget {
  const ConfigSectionHeader({super.key, required this.label, this.topPadding = 4});
  final String label;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8, top: topPadding),
      child: Text(label, style: TextStyle(
        color: t.textDim, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 2,
      )),
    );
  }
}

class ConfigToggleRow extends StatelessWidget {
  const ConfigToggleRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? color : t.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600,
                )),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(
                    color: t.textDim, fontSize: 10,
                  )),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: color.withValues(alpha: 0.5),
            activeThumbColor: color,
          ),
        ],
      ),
    );
  }
}

class ConfigSliderRow extends StatelessWidget {
  const ConfigSliderRow({
    super.key,
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    this.color,
  });
  final IconData icon;
  final String label;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final c = color ?? AppTheme.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: t.textDim),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w500,
              )),
              const Spacer(),
              Text(valueLabel, style: TextStyle(
                color: c, fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
              )),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 2,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: c,
              inactiveColor: t.border,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class ConfigInfoRow extends StatelessWidget {
  const ConfigInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.monospace = true,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final c = color ?? t.textDim;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w500,
          )),
          const Spacer(),
          Text(value, style: TextStyle(
            color: AppTheme.accent,
            fontSize: 12,
            fontFamily: monospace ? 'monospace' : null,
            fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}

class ConfigActionRow extends StatelessWidget {
  const ConfigActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.color,
    this.destructive = false,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final c = destructive
        ? AppTheme.error
        : (color ?? AppTheme.accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: destructive ? AppTheme.error.withValues(alpha: 0.4) : t.border,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(
                      color: destructive ? AppTheme.error : t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(
                        color: t.textDim, fontSize: 10,
                      )),
                  ],
                ),
              ),
              if (trailing != null) trailing!
              else Icon(Icons.chevron_right, size: 18, color: t.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfigTextField extends StatelessWidget {
  const ConfigTextField({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
  });
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: t.textDim, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConfigNumberField extends StatefulWidget {
  const ConfigNumberField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
  });
  final IconData icon;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? suffix;

  @override
  State<ConfigNumberField> createState() => _ConfigNumberFieldState();
}

class _ConfigNumberFieldState extends State<ConfigNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text);
    if (parsed != null) {
      if (parsed != widget.value) widget.onChanged(parsed);
    } else {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void didUpdateWidget(ConfigNumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && !_focusNode.hasFocus) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(widget.icon, size: 16, color: t.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.label, style: TextStyle(
              color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w500,
            )),
          ),
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                color: AppTheme.accent,
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                suffixText: widget.suffix,
                suffixStyle: TextStyle(
                  color: t.textDim, fontSize: 11, fontFamily: 'monospace',
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              onTapOutside: (_) => _focusNode.unfocus(),
              onFieldSubmitted: (_) {
                _commit();
                _focusNode.unfocus();
              },
            ),
          ),
        ],
      ),
    );
  }
}
