import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/features/engines/foxhunter_screen.dart' show RssiGaugePainter;
import 'package:oui_spy/theme/app_theme.dart';

class SdrFoxhuntView extends ConsumerStatefulWidget {
  const SdrFoxhuntView({super.key, required this.targetKey, required this.title});

  final String targetKey;
  final String title;

  static String keyOf(SdrDetection d) {
    final f = d.fields;
    return switch (d.kind) {
      'adsb' => 'adsb|${f['icao']}',
      _ => '${d.kind}|${f['model']}|${f['id']}',
    };
  }

  @override
  ConsumerState<SdrFoxhuntView> createState() => _SdrFoxhuntViewState();
}

class _SdrFoxhuntViewState extends ConsumerState<SdrFoxhuntView> {
  StreamSubscription<SdrFrame>? _sub;
  int _rssi = -60;
  int _prev = -60;
  int _best = -120;
  DateTime? _lastSeen;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(sdrControllerProvider).frameStream.listen(_onFrame);
    _tick = Timer.periodic(const Duration(milliseconds: 500),
        (_) { if (mounted) setState(() {}); });
  }

  void _onFrame(SdrFrame f) {
    final d = f.detection;
    if (d == null || SdrFoxhuntView.keyOf(d) != widget.targetKey) return;
    final r = (d.fields['rssi'] as num?)?.toInt();
    if (r == null) return;
    setState(() {
      _prev = _rssi;
      _rssi = r;
      if (r > _best) _best = r;
      _lastSeen = DateTime.now();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final lost = _lastSeen == null ||
        DateTime.now().difference(_lastSeen!).inSeconds > 10;
    final normalized = ((_rssi + 60) / 60).clamp(0.0, 1.0);
    final trend = _rssi - _prev;
    final color =
        lost ? t.textDim : Color.lerp(AppTheme.error, AppTheme.success, normalized)!;
    final hint = lost
        ? 'NO SIGNAL — move or wait for the next burst'
        : trend > 0
            ? 'WARMER'
            : trend < 0
                ? 'COLDER'
                : 'HOLD';
    return Scaffold(
      appBar: AppBar(title: Text('Foxhunt: ${widget.title}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(260, 260),
                    painter: RssiGaugePainter(
                        rssi: _rssi, normalized: normalized, color: color),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$_rssi',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 52,
                            fontFamily: AppTheme.mono,
                            fontWeight: FontWeight.w700,
                          )),
                      Text(lost ? 'LOST' : 'dBFS',
                          style: TextStyle(color: t.textDim, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(hint,
                style: TextStyle(
                    color: color, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('best $_best dBFS',
                style: TextStyle(color: t.textDim, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Walk toward the strongest reading; it updates on each burst.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
