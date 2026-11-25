// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/features/fpv/fpv_state.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

String fpvStateLabel(FpvState s) {
  if (!s.active) return 'OFF';
  if (s.locked) return 'LOCKED';
  return switch (s.modeEnum) {
    FpvMode.scan => 'SCANNING',
    FpvMode.sweep => 'SWEEPING',
    FpvMode.hop => 'HOPPING',
    FpvMode.stop => 'TUNED',
    FpvMode.off => 'STARTING',
  };
}

String fpvModeLabel(FpvMode m) => switch (m) {
      FpvMode.scan => 'SCAN',
      FpvMode.sweep => 'SWEEP',
      FpvMode.hop => 'HOP',
      FpvMode.stop => 'STOP',
      FpvMode.off => 'OFF',
    };

double fpvHeat(int? level, int floor) {
  if (level == null) return 0;
  return ((level - floor).clamp(0, 100)) / 100.0;
}

class FpvScreen extends ConsumerStatefulWidget {
  const FpvScreen({super.key});

  @override
  ConsumerState<FpvScreen> createState() => _FpvScreenState();
}

class _FpvScreenState extends ConsumerState<FpvScreen> {
  bool _pending = false;
  bool? _wantActive;
  Timer? _pendingTimeout;
  int? _thresholdDrag;

  @override
  void dispose() {
    _pendingTimeout?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String what) async {
    try {
      await action();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$what failed: $e')),
      );
    }
  }

  void _toggle(bool active) {
    final ble = ref.read(bleManagerProvider);
    setState(() {
      _pending = true;
      _wantActive = !active;
    });
    _pendingTimeout?.cancel();
    _pendingTimeout = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _pending = false);
    });
    _run(() => active ? ble.fpvLeave() : ble.fpvEnter(), active ? 'Leave FPV' : 'Start FPV');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final ble = ref.read(bleManagerProvider);
    final supported = ble.board.toLowerCase().contains('c5') && ble.fpvAvailable;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('FPV RECEIVER'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showInfoSheet(context, t, 'FPV receiver', const [
              'Finds analog 5.8 GHz FPV video transmitters with the ESP32-C5. Receive only.',
              'Scans 44 of the 48 standard channels. R8, E6, E7 and E8 are above the 5885 MHz tuning limit and stay dimmed.',
              'Wi-Fi scanning pauses while FPV is on and resumes when you leave.',
              'Flagged transmitters also show up in the Sky Spy list and the feed.',
              'Levels are relative receiver counts, not dBm. The picture is not shown: Bluetooth cannot carry live video.',
            ]),
          ),
        ],
      ),
      body: !supported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'FPV needs a connected ESP32-C5 board running firmware with the FPV receiver.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.textDim, fontSize: 13),
                ),
              ),
            )
          : StreamBuilder<FpvState>(
              stream: ble.fpvState,
              initialData: ble.latestFpvState,
              builder: (context, snap) {
                final s = snap.data ?? FpvState.empty;
                if (_pending && _wantActive == s.active) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _pendingTimeout?.cancel();
                      setState(() => _pending = false);
                    }
                  });
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FpvStateCard(state: s, t: t),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pending ? null : () => _toggle(s.active),
                        icon: _pending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(s.active ? Icons.stop : Icons.play_arrow),
                        label: Text(_pending
                            ? (s.active ? 'LEAVING…' : 'STARTING…')
                            : (s.active ? 'LEAVE FPV' : 'START')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: s.active ? AppTheme.error : AppTheme.success,
                          side: BorderSide(color: s.active ? AppTheme.error : AppTheme.success),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FpvModeSelector(
                        mode: s.active ? s.modeEnum : FpvMode.off,
                        onChanged: (m) => _run(() => ble.fpvSetMode(m), 'Mode change'),
                      ),
                      const SizedBox(height: 12),
                      FpvChannelStepper(
                        state: s,
                        onStep: (d) => _run(() => ble.fpvStep(d), 'Channel step'),
                      ),
                      const SizedBox(height: 16),
                      FpvHeatMap(
                        state: s,
                        onTune: (i) => _run(() => ble.fpvTune(i), 'Tune'),
                      ),
                      const SizedBox(height: 16),
                      _ThresholdCard(
                        value: _thresholdDrag ?? s.threshold,
                        onChanged: (v) => setState(() => _thresholdDrag = v),
                        onChangeEnd: (v) async {
                          await _run(() => ble.fpvSetThreshold(v), 'Threshold');
                          if (mounted) setState(() => _thresholdDrag = null);
                        },
                      ),
                      const SizedBox(height: 16),
                      FpvFlaggedList(
                        state: s,
                        onTune: (i) => _run(() => ble.fpvTune(i), 'Tune'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class FpvStateCard extends StatelessWidget {
  const FpvStateCard({super.key, required this.state, required this.t});
  final FpvState state;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final Color stateColor;
    if (!s.active) {
      stateColor = t.textDim;
    } else if (s.hasError) {
      stateColor = AppTheme.error;
    } else if (s.locked) {
      stateColor = AppTheme.success;
    } else {
      stateColor = AppTheme.accent;
    }
    final err = FpvError.label(s.error);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(fpvStateLabel(s),
                  key: const ValueKey('fpv-state'),
                  style: TextStyle(
                      color: stateColor,
                      fontFamily: AppTheme.mono,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
              const SizedBox(width: 12),
              if (s.active)
                Text(fpvModeLabel(s.modeEnum),
                    style: TextStyle(
                        color: t.textDim,
                        fontFamily: AppTheme.mono,
                        fontSize: 11,
                        letterSpacing: 2)),
              const Spacer(),
              Text('${fpvChannelName(s.channel)}  ${s.mhz} MHz',
                  key: const ValueKey('fpv-channel'),
                  style: TextStyle(color: t.textDim, fontFamily: AppTheme.mono)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.active
                ? 'level ${s.level}  •  coherence ${s.coherence}%  •  floor ${s.floor}  •  flagged ${s.flaggedCount}  •  passes ${s.passes}'
                : 'FPV is off.',
            style: TextStyle(color: t.textDim, fontSize: 12, fontFamily: AppTheme.mono),
          ),
          if (s.active && s.parked) ...[
            const SizedBox(height: 6),
            Text('Wi-Fi scanning is paused while FPV is on.',
                style: TextStyle(color: AppTheme.warning, fontSize: 12)),
          ],
          if (err.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(err, style: TextStyle(color: AppTheme.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class FpvModeSelector extends StatelessWidget {
  const FpvModeSelector({super.key, required this.mode, required this.onChanged});
  final FpvMode mode;
  final ValueChanged<FpvMode> onChanged;

  static const _modes = [FpvMode.scan, FpvMode.sweep, FpvMode.hop, FpvMode.stop];

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          for (final m in _modes) Expanded(child: _modeBtn(context, m)),
        ],
      ),
    );
  }

  Widget _modeBtn(BuildContext context, FpvMode m) {
    final t = AppTheme.of(context);
    final selected = mode == m;
    return GestureDetector(
      key: ValueKey('fpv-mode-${m.name}'),
      onTap: () => onChanged(m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        alignment: Alignment.center,
        child: Text(fpvModeLabel(m),
            style: TextStyle(
              color: selected ? AppTheme.accent : t.textPrimary,
              fontFamily: AppTheme.mono,
              letterSpacing: 2,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            )),
      ),
    );
  }
}

class FpvChannelStepper extends StatelessWidget {
  const FpvChannelStepper({super.key, required this.state, required this.onStep});
  final FpvState state;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('fpv-ch-down'),
            tooltip: 'Previous channel',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onStep(-1),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('CHANNEL',
                    style: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 2)),
                const SizedBox(height: 2),
                Text('${fpvChannelName(state.channel)}  ${state.mhz} MHz',
                    style: TextStyle(
                        color: t.textPrimary,
                        fontFamily: AppTheme.mono,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(fpvBandNames[(state.channel ~/ fpvPerBand).clamp(0, fpvBandNames.length - 1)],
                    style: TextStyle(color: t.textDim, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('fpv-ch-up'),
            tooltip: 'Next channel',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onStep(1),
          ),
        ],
      ),
    );
  }
}

class FpvHeatMap extends StatelessWidget {
  const FpvHeatMap({super.key, required this.state, required this.onTune});
  final FpvState state;
  final ValueChanged<int> onTune;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHANNELS', style: TextStyle(color: t.textDim, letterSpacing: 2, fontSize: 11)),
          const SizedBox(height: 8),
          for (var band = 0; band < fpvBandLetters.length; band++) ...[
            if (band > 0) const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(fpvBandLetters[band],
                      style: TextStyle(
                          color: t.textDim, fontFamily: AppTheme.mono, fontWeight: FontWeight.bold)),
                ),
                for (var n = 0; n < fpvPerBand; n++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: _cell(context, t, band * fpvPerBand + n),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Brighter is stronger over the noise floor. A bolt marks a flagged transmitter. Dimmed channels are outside the 5180 to 5885 MHz tuning window. Tap a channel to tune it.',
            style: TextStyle(color: t.textDim, fontSize: 10, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, ResolvedTheme t, int idx) {
    final supported = state.isSupported(idx);
    final level = supported ? state.levelOf(idx) : null;
    final flagged = state.isFlagged(idx);
    final current = state.active && state.channel == idx;
    final heat = fpvHeat(level, state.floor);
    final fill = !supported
        ? t.surfaceLight.withValues(alpha: 0.4)
        : AppTheme.accent.withValues(alpha: 0.06 + 0.7 * heat);
    final border = current
        ? AppTheme.accent
        : flagged
            ? AppTheme.warning
            : t.border;
    return GestureDetector(
      key: ValueKey('fpv-cell-$idx'),
      behavior: HitTestBehavior.opaque,
      onTap: supported ? () => onTune(idx) : null,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.chip - 4),
          border: Border.all(color: border, width: current || flagged ? 1.6 : 0.6),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fpvChannelName(idx),
                      style: TextStyle(
                          color: supported ? t.textPrimary : t.textDim,
                          fontFamily: AppTheme.mono,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  Text(supported ? (level == null ? '·' : '$level') : 'N/A',
                      style: TextStyle(color: t.textDim, fontFamily: AppTheme.mono, fontSize: 9)),
                ],
              ),
            ),
            if (flagged)
              Positioned(
                top: 1,
                right: 1,
                child: Icon(Icons.bolt, size: 10, color: AppTheme.warning),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdCard extends StatelessWidget {
  const _ThresholdCard({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FLAG THRESHOLD',
                  style: TextStyle(color: t.textDim, letterSpacing: 2, fontSize: 11)),
              const Spacer(),
              Text('+$value over floor',
                  style: TextStyle(color: t.textPrimary, fontFamily: AppTheme.mono, fontSize: 12)),
            ],
          ),
          Slider(
            key: const ValueKey('fpv-threshold'),
            value: value.clamp(fpvMinThreshold, fpvMaxThreshold).toDouble(),
            min: fpvMinThreshold.toDouble(),
            max: fpvMaxThreshold.toDouble(),
            divisions: fpvMaxThreshold - fpvMinThreshold,
            onChanged: (v) => onChanged(v.round()),
            onChangeEnd: (v) => onChangeEnd(v.round()),
          ),
          Text(
            'A channel is flagged when its level is this far above the measured noise floor and the carrier is steady (coherence at least $fpvMinCoherence%).',
            style: TextStyle(color: t.textDim, fontSize: 10, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class FpvFlaggedList extends StatelessWidget {
  const FpvFlaggedList({super.key, required this.state, required this.onTune});
  final FpvState state;
  final ValueChanged<int> onTune;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final flagged = state.flaggedChannels;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRANSMITTERS', style: TextStyle(color: t.textDim, letterSpacing: 2, fontSize: 11)),
          const SizedBox(height: 6),
          if (flagged.isEmpty)
            Text(
              state.active ? 'None flagged yet.' : 'Start FPV to look for transmitters.',
              style: TextStyle(color: t.textDim, fontSize: 12),
            )
          else
            for (final idx in flagged)
              InkWell(
                key: ValueKey('fpv-flag-$idx'),
                onTap: () => onTune(idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 16, color: AppTheme.warning),
                      const SizedBox(width: 8),
                      Text(fpvChannelName(idx),
                          style: TextStyle(
                              color: t.textPrimary,
                              fontFamily: AppTheme.mono,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Text('${fpvChannelMhz(idx)} MHz',
                          style: TextStyle(color: t.textDim, fontFamily: AppTheme.mono, fontSize: 12)),
                      const Spacer(),
                      Text('LVL ${state.levels[idx]}  COH ${state.coherences[idx]}%',
                          style: TextStyle(color: t.textDim, fontFamily: AppTheme.mono, fontSize: 11)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
