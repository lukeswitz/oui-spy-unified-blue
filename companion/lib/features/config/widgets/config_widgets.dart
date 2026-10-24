import 'package:flutter/material.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';

BoxDecoration _hairline(ResolvedTheme t, {Color? color}) =>
    BoxDecoration(border: Border(bottom: BorderSide(color: color ?? t.border)));

class ConfigSectionHeader extends StatelessWidget {
  const ConfigSectionHeader({super.key, required this.label, this.topPadding = 4});
  final String label;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6, top: topPadding),
      child: DSectionHeader(label: label),
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
    this.notify = true,
    this.onNotify,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool notify;
  final ValueChanged<bool>? onNotify;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: _hairline(t),
      child: Row(
        children: [
          Icon(icon, size: 22, color: value ? color : t.textDim),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
                )),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(
                    color: t.textDim, fontSize: 13,
                  )),
                ],
              ],
            ),
          ),
          if (onNotify != null)
            IconButton(
              tooltip: notify ? 'Notifications on' : 'Notifications off, still logged',
              icon: Icon(
                notify ? Icons.notifications_active : Icons.notifications_off_outlined,
                color: value && notify ? color : t.textDim,
              ),
              onPressed: value ? () => onNotify!(!notify) : null,
            ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
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
    this.onChangeEnd,
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
  final ValueChanged<double>? onChangeEnd;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final c = color ?? AppTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: _hairline(t),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: c),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label, style: TextStyle(
                  color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
                )),
              ),
              Text(valueLabel, style: TextStyle(
                color: c, fontSize: 14,
                fontFamily: AppTheme.mono, fontWeight: FontWeight.w600,
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
              onChangeEnd: onChangeEnd,
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: _hairline(t),
      child: Row(
        children: [
          Icon(icon, size: 22, color: c),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(
            color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w500,
          )),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
            color: AppTheme.accent,
            fontSize: 15,
            fontFamily: monospace ? AppTheme.mono : null,
            fontWeight: FontWeight.w600,
          ))),
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
    this.prominent = false,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;
  final bool destructive;
  final Widget? trailing;
  final bool prominent;

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
        child: Container(
          padding: EdgeInsets.symmetric(vertical: prominent ? 16 : 12),
          decoration: _hairline(t, color: destructive ? AppTheme.error : null),
          child: Row(
            children: [
              Icon(icon, size: prominent ? 26 : 22, color: c),
              SizedBox(width: prominent ? 16 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(
                      color: destructive ? AppTheme.error : t.textPrimary,
                      fontSize: prominent ? 18 : 16,
                      fontWeight: FontWeight.w600,
                    )),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(
                        color: t.textDim, fontSize: prominent ? 14 : 13,
                      )),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!
              else Icon(Icons.chevron_right, size: 22, color: t.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfigCompactButton extends StatelessWidget {
  const ConfigCompactButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final c = destructive ? AppTheme.error : (color ?? AppTheme.accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: destructive ? AppTheme.error : t.textPrimary),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: c),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: destructive ? AppTheme.error : t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: _hairline(t),
      child: Row(
        children: [
          Icon(icon, size: 22, color: t.textDim),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: TextStyle(color: t.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: t.textDim, fontSize: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: _hairline(t),
      child: Row(
        children: [
          Icon(widget.icon, size: 22, color: t.textDim),
          const SizedBox(width: 14),
          Expanded(
            child: Text(widget.label, style: TextStyle(
              color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w500,
            )),
          ),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                color: AppTheme.accent,
                fontFamily: AppTheme.mono,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                suffixText: widget.suffix,
                suffixStyle: TextStyle(
                  color: t.textDim, fontSize: 11, fontFamily: AppTheme.mono,
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
