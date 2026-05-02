import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class EngineCard extends ConsumerStatefulWidget {
  const EngineCard({
    super.key,
    required this.engine,
    this.detectionCount = 0,
    this.isActive = false,
    this.engineState = EngineState.disabled,
  });

  final Engine engine;
  final int detectionCount;
  final bool isActive;
  final EngineState engineState;

  @override
  ConsumerState<EngineCard> createState() => _EngineCardState();
}

class _EngineCardState extends ConsumerState<EngineCard> {
  /// Optimistic override — holds toggled value until firmware confirms or timeout.
  bool? _optimisticValue;
  Timer? _optimisticTimer;

  bool get _displayActive => _optimisticValue ?? widget.isActive;

  @override
  void didUpdateWidget(EngineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Firmware confirmed the state we optimistically set — clear override
    if (_optimisticValue != null && widget.isActive == _optimisticValue) {
      _optimisticValue = null;
      _optimisticTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _optimisticTimer?.cancel();
    super.dispose();
  }

  void _toggleEngine(bool value) {
    final ble = ref.read(bleManagerProvider);
    if (value) {
      ble.enableEngine(widget.engine);
    } else {
      ble.disableEngine(widget.engine);
    }
    DebugLog.log('ENGINE: toggle ${widget.engine.name} -> $value');

    // Optimistic update — hold for 3s max, then revert to firmware truth
    setState(() => _optimisticValue = value);
    _optimisticTimer?.cancel();
    _optimisticTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _optimisticValue = null);
    });
  }

  void _navigateToEngine() {
    final route = switch (widget.engine) {
      Engine.detector => '/engine/detector',
      Engine.foxhunter => '/engine/foxhunter',
      Engine.skySpy => '/engine/skyspy',
      Engine.uniPwn => '/engine/unipwn',
      Engine.wardrive => '/wardrive',
      _ => null,
    };
    if (route != null) context.push(route);
  }

  Color _stateColor(bool active) {
    if (_optimisticValue != null && _optimisticValue != widget.isActive) {
      // Pending state change — show amber
      return AppTheme.warning;
    }
    return switch (widget.engineState) {
      EngineState.disabled => AppTheme.textDim,
      EngineState.idle => AppTheme.textSecondary,
      EngineState.scanning => widget.engine.color,
      EngineState.active => AppTheme.success,
      EngineState.alerting => AppTheme.warning,
      EngineState.exploiting => AppTheme.error,
      _ => widget.engine.color,
    };
  }

  String get _stateLabel {
    if (_optimisticValue != null && _optimisticValue != widget.isActive) {
      return _optimisticValue! ? 'STARTING...' : 'STOPPING...';
    }
    return switch (widget.engineState) {
      EngineState.disabled => 'OFF',
      EngineState.idle => 'IDLE',
      EngineState.scanning => 'SCANNING',
      EngineState.active => 'ACTIVE',
      EngineState.alerting => 'ALERT',
      EngineState.targetSelected => 'TARGET SET',
      EngineState.connecting => 'CONNECTING',
      EngineState.exploiting => 'EXPLOITING',
      EngineState.complete => 'DONE',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.engine.color;
    final active = _displayActive;

    return GestureDetector(
      onTap: _navigateToEngine,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 160;
          final iconSize = compact ? 24.0 : 28.0;
          final iconInner = compact ? 14.0 : 16.0;
          final pad = compact ? 10.0 : 14.0;
          final labelSize = compact ? 10.0 : 11.0;
          final countSize = compact ? 22.0 : 28.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color:
                  active ? color.withValues(alpha: 0.06) : AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? color.withValues(alpha: 0.4)
                    : AppTheme.border,
                width: active ? 1.0 : 0.5,
              ),
            ),
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: active
                            ? color.withValues(alpha: 0.15)
                            : AppTheme.border.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(widget.engine.icon,
                          color: active ? color : AppTheme.textDim,
                          size: iconInner),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.engine.label.toUpperCase(),
                        style: TextStyle(
                          color:
                              active ? color : AppTheme.textSecondary,
                          fontSize: labelSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Transform.scale(
                      scale: compact ? 0.6 : 0.7,
                      child: Switch(
                        value: active,
                        onChanged: _toggleEngine,
                        activeTrackColor: color.withValues(alpha: 0.3),
                        activeThumbColor: color,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.detectionCount}',
                      style: TextStyle(
                        color: active
                            ? AppTheme.textPrimary
                            : AppTheme.textDim,
                        fontSize: countSize,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'monospace',
                        height: 1,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _stateColor(active).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _stateLabel,
                        style: TextStyle(
                          color: _stateColor(active),
                          fontSize: compact ? 8 : 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
