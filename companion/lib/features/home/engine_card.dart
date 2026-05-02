import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class EngineCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final color = engine.color;

    return GestureDetector(
      onTap: () => _navigateToEngine(context),
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
                  isActive ? color.withValues(alpha: 0.06) : AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? color.withValues(alpha: 0.4)
                    : AppTheme.border,
                width: isActive ? 1.0 : 0.5,
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
                        color: isActive
                            ? color.withValues(alpha: 0.15)
                            : AppTheme.border.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(engine.icon,
                          color: isActive ? color : AppTheme.textDim,
                          size: iconInner),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        engine.label.toUpperCase(),
                        style: TextStyle(
                          color:
                              isActive ? color : AppTheme.textSecondary,
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
                        value: isActive,
                        onChanged: (v) => _toggleEngine(ref, v),
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
                      '$detectionCount',
                      style: TextStyle(
                        color: isActive
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
                        color: _stateColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _stateLabel,
                        style: TextStyle(
                          color: _stateColor,
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

  Color get _stateColor {
    return switch (engineState) {
      EngineState.disabled => AppTheme.textDim,
      EngineState.idle => AppTheme.textSecondary,
      EngineState.scanning => engine.color,
      EngineState.active => AppTheme.success,
      EngineState.alerting => AppTheme.warning,
      EngineState.exploiting => AppTheme.error,
      _ => engine.color,
    };
  }

  String get _stateLabel {
    return switch (engineState) {
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

  void _toggleEngine(WidgetRef ref, bool value) {
    final ble = ref.read(bleManagerProvider);
    if (value) {
      ble.enableEngine(engine);
    } else {
      ble.disableEngine(engine);
    }
    DebugLog.log('ENGINE: toggle ${engine.name} -> $value');
  }

  void _navigateToEngine(BuildContext context) {
    final route = switch (engine) {
      Engine.detector => '/engine/detector',
      Engine.foxhunter => '/engine/foxhunter',
      Engine.skySpy => '/engine/skyspy',
      Engine.uniPwn => '/engine/unipwn',
      _ => null,
    };
    if (route != null) context.push(route);
  }
}
