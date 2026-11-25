// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oui_spy/core/find_it.dart';

/// A ring that pulses once per [findItInterval] of [rssi], and calls [onPulse] each time.
class FindItPulse extends StatefulWidget {
  const FindItPulse({
    super.key,
    required this.rssi,
    required this.color,
    required this.child,
    this.onPulse,
  });

  final int? rssi;
  final Color color;
  final Widget child;
  final VoidCallback? onPulse;

  @override
  State<FindItPulse> createState() => _FindItPulseState();
}

class _FindItPulseState extends State<FindItPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.rssi != null) _pulse();
  }

  @override
  void didUpdateWidget(FindItPulse old) {
    super.didUpdateWidget(old);
    if (old.rssi == null && widget.rssi != null && _timer == null) _pulse();
    if (widget.rssi == null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _pulse() {
    if (!mounted) return;
    _ring.forward(from: 0);
    widget.onPulse?.call();
    _timer = Timer(findItInterval(widget.rssi), () {
      _timer = null;
      if (widget.rssi != null) _pulse();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ring,
              builder: (_, _) => CustomPaint(
                key: const Key('find-it-ring'),
                painter: _RingPainter(_ring.value, widget.color, active: widget.rssi != null),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color, {required this.active});
  final double t;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active || t >= 1) return;
    final base = size.shortestSide / 2;
    canvas.drawCircle(
      size.center(Offset.zero),
      base * (0.82 + 0.3 * t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.7 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.color != color || old.active != active;
}
