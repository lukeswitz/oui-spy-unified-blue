part of 'wardrive_screen.dart';

class _ScanningPill extends StatefulWidget {
  const _ScanningPill({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  State<_ScanningPill> createState() => _ScanningPillState();
}

class _ScanningPillState extends State<_ScanningPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.92),
        border: Border.all(color: widget.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(widget.label, style: TextStyle(
            color: widget.color, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1)),
        ],
      ),
    );
  }
}
