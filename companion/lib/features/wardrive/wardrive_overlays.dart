part of 'wardrive_screen.dart';

class _NodeStatsOverlay extends ConsumerWidget {
  const _NodeStatsOverlay({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final appState = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final selfId = AppState.canonicalNodeId(appState.nodeId);
    final nodeCount =
        appState.liveKnownNodes
            .where((id) => id != selfId && !appState.isManagerNode(id))
            .length;
    final showHeader = appState.isManagerConnected && appState.meshEnabled;
    final label = '$nodeCount NODE${nodeCount == 1 ? '' : 'S'}';
    final color =
        nodeCount > 0 ? AppTheme.success : AppTheme.warning;
    final perNode = <String, int>{...wd.detectionsPerNode};
    final selfRaw = wd.localWifiCount + wd.localBleCount;
    final selfScans = appState.isConnected && !appState.isManagerConnected;
    if (selfRaw > 0 || selfScans) {
      final selfBucket = appState.nodeId.isNotEmpty ? appState.nodeId : 'LOCAL';
      perNode[selfBucket] = (perNode[selfBucket] ?? 0) + selfRaw;
    }
    if (ref.watch(phoneBleSourceProvider).scanning) {
      perNode[BleManager.phoneNodeId] ??= 0;
    }
    final nodeEntries = perNode.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (nodeEntries.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...nodeEntries.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: e.key == 'LOCAL'
                              ? AppTheme.accent
                              : AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        '${appState.labelForNode(e.key)}: ${e.value}',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _CurrentPosMarker extends StatefulWidget {
  const _CurrentPosMarker({required this.theme});
  final WardriveThemeData theme;

  @override
  State<_CurrentPosMarker> createState() => _CurrentPosMarkerState();
}

class _CurrentPosMarkerState extends State<_CurrentPosMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.theme.synthwaveSky) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _CurrentPosMarker old) {
    super.didUpdateWidget(old);
    if (widget.theme.synthwaveSky && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.theme.synthwaveSky && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.theme.currentPosColor;
    final dot = CustomPaint(
      size: const Size(14, 14),
      painter: _DotPainter(color: c),
    );
    if (!widget.theme.synthwaveSky) {
      return Center(child: dot);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = Curves.easeOut.transform(_ctrl.value);
        final ringSize = 56.0 * v;
        final ringOpacity = (1.0 - v).clamp(0.0, 1.0) * 0.55;
        return Stack(alignment: Alignment.center, children: [
          Opacity(
            opacity: ringOpacity,
            child: CustomPaint(
              size: Size(ringSize, ringSize),
              painter: _RingPainter(color: c, strokeWidth: 1.0),
            ),
          ),
          dot,
        ]);
      },
    );
  }
}

class _DotPainter extends CustomPainter {
  const _DotPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c, size.width / 2 + 1.5,
      Paint()..color = color.withValues(alpha: 0.25),
    );
    canvas.drawCircle(c, size.width / 2, Paint()..color = color);
    canvas.drawCircle(
      c, size.width / 2 - 1.2,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.drawCircle(c, 2.4, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant _DotPainter old) => old.color != color;
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}



class _SynthwaveSky extends StatefulWidget {
  const _SynthwaveSky({required this.theme});
  final WardriveThemeData theme;
  @override
  State<_SynthwaveSky> createState() => _SynthwaveSkyState();
}

class _SynthwaveSkyState extends State<_SynthwaveSky>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SynthwaveSkyPainter(
          phase: _ctrl.value,
          accent: widget.theme.accent,
          secondary: widget.theme.secondary,
          tertiary: widget.theme.tertiary,
        ),
      ),
    );
  }
}

class _SynthwaveSkyPainter extends CustomPainter {
  const _SynthwaveSkyPainter({
    required this.phase,
    required this.accent,
    required this.secondary,
    required this.tertiary,
  });
  final double phase;
  final Color accent;
  final Color secondary;
  final Color tertiary;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height;

    // Sky gradient: deep space at top → magenta → cyan glow at horizon.
    final skyRect = Rect.fromLTWH(0, 0, size.width, horizonY);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF050014),
            const Color(0xFF1A0033),
            const Color(0xFF52004A),
            accent.withValues(alpha: 0.65),
            secondary.withValues(alpha: 0.45),
          ],
          stops: const [0.0, 0.35, 0.7, 0.92, 1.0],
        ).createShader(skyRect),
    );

    // Retro sun — full disc sits in the sky, kissing the horizon.
    final sunRadius = size.width * 0.22;
    final sunCenter = Offset(size.width / 2, horizonY - sunRadius * 0.15);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, horizonY));

    // Sun gradient body.
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tertiary, accent, accent.withValues(alpha: 0.9)],
        ).createShader(
          Rect.fromCircle(center: sunCenter, radius: sunRadius),
        ),
    );

    // Slatted horizontal bands cutting the sun (classic synthwave).
    final bandPaint = Paint()..color = const Color(0xFF050014);
    for (var i = 1; i <= 6; i++) {
      final t = i / 7.0;
      final y = horizonY - sunRadius * (t * t);
      final h = 2.0 + i * 0.6;
      canvas.drawRect(
        Rect.fromLTWH(sunCenter.dx - sunRadius, y, sunRadius * 2, h),
        bandPaint,
      );
    }
    canvas.restore();

    // Sun glow halo.
    canvas.drawCircle(
      sunCenter,
      sunRadius * 1.4,
      Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    // Stars — animated twinkle via phase.
    final starPaint = Paint()..color = Colors.white;
    double rng(int seed) => ((seed * 9301 + 49297) % 233280) / 233280.0;
    for (var i = 0; i < 60; i++) {
      final sx = rng(i * 7) * size.width;
      final sy = rng(i * 11) * horizonY * 0.7;
      final twinkle =
          (sin((phase * 2 * pi) + i.toDouble()) * 0.5 + 0.5) * 0.7 + 0.3;
      canvas.drawCircle(
        Offset(sx, sy),
        0.8 + rng(i * 13) * 0.6,
        starPaint..color = Colors.white.withValues(alpha: twinkle * 0.8),
      );
    }

    // Horizon hairline — crisp neon edge where sky meets ground.
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      Paint()
        ..color = secondary
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(0, horizonY + 1.2),
      Offset(size.width, horizonY + 1.2),
      Paint()
        ..color = secondary.withValues(alpha: 0.35)
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant _SynthwaveSkyPainter old) =>
      old.phase != phase;
}

class _SpeedLines extends StatefulWidget {
  const _SpeedLines({
    required this.color,
    required this.speed,
    required this.horizonY,
    required this.width,
  });
  final Color color;
  final double speed; // m/s
  final double horizonY;
  final double width;
  @override
  State<_SpeedLines> createState() => _SpeedLinesState();
}

class _SpeedLinesState extends State<_SpeedLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    // Intensity ramps with speed; idle = subtle, highway = strong.
    final intensity = (widget.speed / 25.0).clamp(0.0, 1.0);
    if (intensity < 0.02) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SpeedLinesPainter(
          phase: _ctrl.value,
          color: widget.color,
          intensity: intensity,
          horizonY: widget.horizonY,
        ),
      ),
    );
  }
}

class _SpeedLinesPainter extends CustomPainter {
  const _SpeedLinesPainter({
    required this.phase,
    required this.color,
    required this.intensity,
    required this.horizonY,
  });
  final double phase;
  final Color color;
  final double intensity;
  final double horizonY;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Offset(size.width / 2, horizonY);
    double rng(int seed) => ((seed * 9301 + 49297) % 233280) / 233280.0;
    const count = 22;
    for (var i = 0; i < count; i++) {
      final t = ((i / count) + phase) % 1.0;
      final eased = t * t; // accelerate toward viewer
      // Pick an exit angle around the lower 2/3 of screen.
      final angle = (rng(i) * 1.6 - 0.8) + (rng(i * 3) - 0.5) * 0.4;
      final dirX = sin(angle);
      final dirY = cos(angle).abs() + 0.4;
      final maxLen = size.height * 1.4;
      final start = Offset(
        vp.dx + dirX * (maxLen * eased * 0.85),
        vp.dy + dirY * (maxLen * eased * 0.85),
      );
      final end = Offset(
        vp.dx + dirX * (maxLen * eased),
        vp.dy + dirY * (maxLen * eased),
      );
      final alpha = (intensity * (0.55 - (eased * 0.4))).clamp(0.0, 0.7);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 1.2 + eased * 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter old) =>
      old.phase != phase ||
      old.color != color ||
      old.intensity != intensity ||
      old.horizonY != horizonY;
}

class _SpeedoHud extends StatelessWidget {
  const _SpeedoHud({
    required this.theme,
    required this.speed,
    required this.unit,
  });
  final WardriveThemeData theme;
  final double speed;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final s = speed.clamp(0, 999).toInt();
    // Chrome shader — vertical sunset gradient across the digits.
    final chromeShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFFFE066),
        theme.tertiary,
        theme.accent,
        const Color(0xFFB0008C),
      ],
      stops: const [0.0, 0.35, 0.65, 1.0],
    ).createShader(const Rect.fromLTWH(0, 0, 240, 56));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.accent.withValues(alpha: 0.75),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accent.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Lightning bolt accent.
          Icon(
            Icons.electric_bolt,
            color: theme.secondary,
            size: 22,
            shadows: [
              Shadow(
                color: theme.secondary.withValues(alpha: 0.85),
                blurRadius: 10,
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Chrome-gradient digits with magenta neon glow under.
          Stack(children: [
            // Glow layer.
            Text(
              s.toString().padLeft(3, '0'),
              style: TextStyle(
                color: theme.accent.withValues(alpha: 0.0),
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 44,
                height: 1.0,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                    color: theme.accent.withValues(alpha: 0.9),
                    blurRadius: 22,
                  ),
                ],
              ),
            ),
            // Chrome shader fill.
            Text(
              s.toString().padLeft(3, '0'),
              style: TextStyle(
                foreground: Paint()..shader = chromeShader,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 44,
                height: 1.0,
                letterSpacing: 4,
              ),
            ),
          ]),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unit,
                style: TextStyle(
                  color: theme.secondary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 36, height: 2,
                decoration: BoxDecoration(
                  color: theme.secondary,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(
                      color: theme.secondary.withValues(alpha: 0.7),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.theme, required this.score});
  final WardriveThemeData theme;
  final int score;

  @override
  Widget build(BuildContext context) {
    final s = score.clamp(0, 999999);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.tertiary.withValues(alpha: 0.85),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.tertiary.withValues(alpha: 0.55),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'SCORE',
            style: TextStyle(
              color: theme.secondary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            s.toString().padLeft(6, '0'),
            style: TextStyle(
              color: theme.tertiary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: theme.tertiary.withValues(alpha: 0.85),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _MountainsPainter extends CustomPainter {
  const _MountainsPainter({required this.ridge, required this.glow});
  final Color ridge;
  final Color glow;

  static const _peaks = <double>[
    0.0, 0.18, 0.04, 0.40, 0.10, 0.55, 0.22, 0.72, 0.30,
    0.62, 0.42, 0.80, 0.55, 0.50, 0.66, 0.78, 0.78, 0.45,
    0.88, 0.62, 1.0, 0.30,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path();
    final baseY = size.height;
    path.moveTo(0, baseY);
    for (var i = 0; i < _peaks.length; i += 2) {
      final x = _peaks[i] * size.width;
      final y = baseY - _peaks[i + 1] * size.height;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, baseY);
    path.close();
    // Fill = deep silhouette.
    canvas.drawPath(path, Paint()..color = const Color(0xFF0A0014));
    // Underline glow.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = ridge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Crisp top edge.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = glow.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _MountainsPainter old) =>
      old.ridge != ridge || old.glow != glow;
}


class _SynthwaveGrid extends StatefulWidget {
  const _SynthwaveGrid({
    required this.color,
    required this.accent,
    required this.speed,
  });
  final Color color;
  final Color accent;
  final double speed;
  @override
  State<_SynthwaveGrid> createState() => _SynthwaveGridState();
}

class _SynthwaveGridState extends State<_SynthwaveGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _SynthwaveGridPainter(
          phase: _ctrl.value,
          color: widget.color,
          accent: widget.accent,
          speed: widget.speed,
        ),
      ),
    );
  }
}

class _SynthwaveGridPainter extends CustomPainter {
  const _SynthwaveGridPainter({
    required this.phase,
    required this.color,
    required this.accent,
    required this.speed,
  });
  final double phase;
  final Color color;
  final Color accent;
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Offset(size.width / 2, 0);
    final bottomY = size.height;

    // Speed factor influences scroll rate. Idle = lazy drift; highway = rush.
    final scrollRate = 1.0 + (speed / 8.0).clamp(0.0, 4.0);
    final scrolled = (phase * scrollRate) % 1.0;

    const verticalCount = 14;
    for (var i = -verticalCount ~/ 2; i <= verticalCount ~/ 2; i++) {
      final t = i / (verticalCount / 2);
      final x = vp.dx + t * size.width * 1.4;
      final fadeT = 1.0 - (t.abs() * 0.5);
      canvas.drawLine(
        vp,
        Offset(x, bottomY),
        Paint()
          ..shader = ui.Gradient.linear(
            vp,
            Offset(x, bottomY),
            [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.45 * fadeT),
              color.withValues(alpha: 0.85 * fadeT),
            ],
            const [0.0, 0.5, 1.0],
          )
          ..strokeWidth = 0.9 + (1.0 - t.abs()) * 0.6,
      );
    }

    const horizontalCount = 12;
    for (var i = 0; i < horizontalCount; i++) {
      final t = ((i / horizontalCount) + scrolled) % 1.0;
      // Perspective y curve.
      final yT = t * t;
      final y = yT * bottomY;
      // Alpha fades at horizon and viewer extremes.
      final alpha = (sin(t * pi) * 0.65 + 0.2).clamp(0.0, 0.85);
      // Width grows with t (closer = bigger).
      final spread = size.width * (0.2 + 1.2 * t);
      final xStart = vp.dx - spread;
      final xEnd = vp.dx + spread;
      canvas.drawLine(
        Offset(xStart, y),
        Offset(xEnd, y),
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 0.8 + t * 1.4,
      );
      // Subtle glow underneath the closest lines.
      if (t > 0.6) {
        canvas.drawLine(
          Offset(xStart, y),
          Offset(xEnd, y),
          Paint()
            ..color = accent.withValues(alpha: alpha * 0.35)
            ..strokeWidth = 4.0
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SynthwaveGridPainter old) =>
      old.phase != phase ||
      old.color != color ||
      old.accent != accent ||
      old.speed != speed;
}


class _PalmStreaker extends StatefulWidget {
  const _PalmStreaker({
    required this.silhouette,
    required this.glow,
    required this.speed,
  });
  final Color silhouette;
  final Color glow;
  final double speed;
  @override
  State<_PalmStreaker> createState() => _PalmStreakerState();
}

class _PalmStreakerState extends State<_PalmStreaker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _PalmStreakerPainter(
          phase: _ctrl.value,
          silhouette: widget.silhouette,
          glow: widget.glow,
          speed: widget.speed,
        ),
      ),
    );
  }
}

class _PalmStreakerPainter extends CustomPainter {
  const _PalmStreakerPainter({
    required this.phase,
    required this.silhouette,
    required this.glow,
    required this.speed,
  });
  final double phase;
  final Color silhouette;
  final Color glow;
  final double speed;

  void _drawPalm(Canvas canvas, Offset base, double scale, Color fill) {
    // Trunk
    final trunk = Paint()..color = fill;
    canvas.drawRect(
      Rect.fromCenter(
        center: base.translate(0, -22 * scale),
        width: 3.0 * scale,
        height: 44 * scale,
      ),
      trunk,
    );
    // Fronds — 6 angled blades from top of trunk.
    final top = base.translate(0, -44 * scale);
    final fronds = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = (-pi / 2) + (i - 2.5) * 0.45;
      final dx = cos(a) * 18 * scale;
      final dy = sin(a) * 18 * scale;
      canvas.drawLine(top, top.translate(dx, dy), fronds);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Scroll rate ramps with speed. Idle = slow drift; fast = blur past.
    final scrollRate = 1.0 + (speed / 6.0).clamp(0.0, 4.0);
    const totalPalms = 6;
    for (var side = 0; side < 2; side++) {
      // side 0 = left, 1 = right.
      final isRight = side == 1;
      for (var i = 0; i < totalPalms; i++) {
        // Phase per palm — staggered so they don't all line up.
        final t = ((i / totalPalms) + phase * scrollRate +
                (isRight ? 0.5 / totalPalms : 0.0)) %
            1.0;
        // y curve: t² so palms bunch near horizon, spread near bottom.
        final yT = t * t;
        final y = yT * size.height;
        // x curve: palms drift outward from the road edge as they approach.
        final edge = isRight ? size.width : 0.0;
        final centerPull = isRight ? -1.0 : 1.0;
        final x = edge + centerPull * (size.width * 0.18) * (1.0 - t) +
            centerPull * (size.width * 0.08) * t;
        // Scale grows with distance traveled.
        final scale = 0.25 + t * 1.4;
        final alpha = (sin(t * pi) * 0.95 + 0.05).clamp(0.15, 1.0);
        // Subtle pink rim light first.
        _drawPalm(
          canvas,
          Offset(x, y),
          scale * 1.08,
          glow.withValues(alpha: alpha * 0.4),
        );
        // Solid silhouette on top.
        _drawPalm(canvas, Offset(x, y), scale, silhouette.withValues(alpha: alpha));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PalmStreakerPainter old) =>
      old.phase != phase || old.speed != speed;
}


class _CrtScanlines extends StatelessWidget {
  const _CrtScanlines();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CrtScanlinesPainter());
  }
}

class _CrtScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = const Color(0x14000000);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), dark);
    }
    // Soft chromatic-aberration vignette edge tint.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: const [
            Color(0x00000000),
            Color(0x33000000),
          ],
          stops: const [0.7, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _CrtScanlinesPainter old) => false;
}


class _CaptureFlash extends StatefulWidget {
  const _CaptureFlash({required this.color, required this.score});
  final Color color;
  final int score;
  @override
  State<_CaptureFlash> createState() => _CaptureFlashState();
}

class _CaptureFlashState extends State<_CaptureFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _lastScore = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _lastScore = widget.score;
  }

  @override
  void didUpdateWidget(covariant _CaptureFlash old) {
    super.didUpdateWidget(old);
    if (widget.score > _lastScore) {
      _lastScore = widget.score;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        if (_ctrl.value == 0 || _ctrl.value == 1) {
          return const SizedBox.shrink();
        }
        final v = _ctrl.value;
        return CustomPaint(
          painter: _CaptureFlashPainter(
            phase: v,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _CaptureFlashPainter extends CustomPainter {
  const _CaptureFlashPainter({required this.phase, required this.color});
  final double phase;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    // Two stages — initial pop then fade.
    final pop = (1.0 - phase) * (1.0 - phase); // ease-out
    final ringR = size.shortestSide * (0.1 + phase * 1.6);
    final center = Offset(size.width / 2, size.height / 2);
    // Full-screen tint pop.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.12 * pop),
    );
    // Expanding ring.
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: pop * 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: pop),
    );
  }

  @override
  bool shouldRepaint(covariant _CaptureFlashPainter old) =>
      old.phase != phase || old.color != color;
}

