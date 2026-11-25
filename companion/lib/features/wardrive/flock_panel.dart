import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/feed/detection_row.dart'
    show detectionHeadline, detectorTitle, methodLabel;
import 'package:oui_spy/features/wardrive/drone_markers.dart' show droneColorForMac;
import 'package:oui_spy/theme/app_theme.dart';

Color _flockConfColor(FlockConfidence c) => switch (c) {
  FlockConfidence.verified => AppTheme.success,
  FlockConfidence.high => AppTheme.success,
  FlockConfidence.suspected => AppTheme.warning,
};

class FlockPanel extends StatefulWidget {
  const FlockPanel(
      {super.key,
      required this.detections,
      this.onDetectionTap,
      this.icon = Icons.videocam,
      this.accent});
  final List<Detection> detections;
  final void Function(Detection)? onDetectionTap;
  final IconData icon;
  final Color? accent;

  @override
  State<FlockPanel> createState() => _FlockPanelState();
}

class _FlockPanelState extends State<FlockPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final count = widget.detections.length;
    final accent = widget.accent ?? AppTheme.flockBle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: count > 0 ? () => setState(() => _expanded = !_expanded) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: count > 0
                  ? accent.withValues(alpha: 0.2)
                  : t.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: count > 0
                    ? accent.withValues(alpha: 0.5)
                    : t.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15,
                    color: count > 0 ? accent : t.textDim),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    color: count > 0 ? accent : t.textDim,
                    fontSize: 11, fontWeight: FontWeight.w700,
                    fontFamily: AppTheme.mono,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 11, color: accent,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded && widget.detections.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.background.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 2),
              shrinkWrap: true,
              itemCount: widget.detections.length,
              itemBuilder: (_, i) => _Row(
                d: widget.detections[i],
                onTap: widget.onDetectionTap,
              ),
            ),
          ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );
}

class _Row extends ConsumerWidget {
  const _Row({required this.d, this.onTap});
  final Detection d;
  final void Function(Detection)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final priv = ref.watch(privacyScreenProvider);
    final rssiNorm = ((d.rssi + 100) / 70).clamp(0.0, 1.0);
    final rssiColor = Color.lerp(AppTheme.error, AppTheme.success, rssiNorm)!;
    final hasGps = d.latitude != null && d.longitude != null;

    final macUpper = d.macAddress.toUpperCase();
    final headline = detectionHeadline(d);
    final named = headline != macUpper;
    final cls = detectionAlertClass[d];
    final isFlock = d.engine == Engine.flockBle || d.engine == Engine.flockWifi;
    final isDrone = d.engine == Engine.skySpy;
    final uasId = d.odid?.uavId ?? '';

    final String title;
    if (named) {
      title = maskName(headline, priv);
    } else if (isFlock) {
      title = 'Flock Safety device';
    } else if (isDrone) {
      title = uasId.isNotEmpty ? 'UAS $uasId' : 'Drone';
    } else if (d.detector != null) {
      title = detectorTitle(d);
    } else if (cls != null) {
      title = alertKindLabel(cls);
    } else {
      title = maskMac(macUpper, priv);
    }

    final Color color;
    final String typeLabel;
    if (isFlock) {
      color = d.engine == Engine.flockBle ? AppTheme.flockBle : AppTheme.flockWifi;
      typeLabel = d.engine == Engine.flockBle ? 'FLOCK BLE' : 'FLOCK WIFI';
    } else if (isDrone) {
      color = droneColorForMac(d.macAddress);
      typeLabel = 'DRONE';
    } else {
      color = cls != null ? alertKindColor(cls) : d.engine.color;
      typeLabel = (cls != null ? alertKindLabel(cls) : methodLabel(d.method)).toUpperCase();
    }

    final flock = d.flock;

    return GestureDetector(
      onTap: hasGps && onTap != null ? () => onTap!(d) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${d.rssi}',
                  style: TextStyle(
                    color: rssiColor,
                    fontSize: 13,
                    fontFamily: AppTheme.mono,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 6,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Tag(typeLabel, color),
                if (flock?.isRaven ?? false) _Tag('RAVEN', AppTheme.warning),
                if (flock != null)
                  Builder(builder: (_) {
                    final fc = flock.confidence(d.method);
                    return _Tag(fc.name.toUpperCase(), _flockConfColor(fc));
                  }),
                Text(
                  maskMac(macUpper, priv),
                  style: TextStyle(
                    color: t.textDim,
                    fontSize: 11,
                    fontFamily: AppTheme.mono,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
