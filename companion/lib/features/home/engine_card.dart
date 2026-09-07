import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/theme/app_theme.dart';

enum CardSize { hero, medium, compact }

class EngineCard extends ConsumerStatefulWidget {
  const EngineCard({
    super.key,
    required this.engine,
    this.detectionCount = 0,
    this.isActive = false,
    this.engineState = EngineState.disabled,
    this.lastDetection,
    this.rate = 0,
    this.size = CardSize.medium,
    this.nodeCount = 0,
  });

  final Engine engine;
  final int detectionCount;
  final bool isActive;
  final EngineState engineState;
  final DateTime? lastDetection;
  final int rate;
  final CardSize size;
  final int nodeCount;

  @override
  ConsumerState<EngineCard> createState() => _EngineCardState();
}

class _EngineCardState extends ConsumerState<EngineCard>
    with SingleTickerProviderStateMixin {
  bool? _optimisticValue;
  Timer? _optimisticTimer;
  late final AnimationController _pulse;

  bool get _displayActive => _optimisticValue ?? widget.isActive;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.rate > 0 && widget.isActive) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(EngineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticValue != null && widget.isActive == _optimisticValue) {
      _optimisticValue = null;
      _optimisticTimer?.cancel();
    }
    final shouldPulse = widget.rate > 0 && widget.isActive;
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldPulse && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _optimisticTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _toggleEngine(bool value) {
    if (widget.engine == Engine.wardrive) {
      final wd = ref.read(wardriveProvider);
      if (value) {
        wd.startSession();
        // Sync wardrive to peers with channel split
        _syncToPeers(value);
      } else {
        wd.stopSession();
        _syncToPeers(value);
      }
      return;
    }

    final wd = ref.read(wardriveProvider);
    final ownedByWardrive = wd.isActive &&
        (wd.activeEngines.contains(widget.engine) ||
            (wd.includesFlock &&
                (widget.engine == Engine.flockBle ||
                    widget.engine == Engine.flockWifi)));
    if (!value && ownedByWardrive) {
      setState(() => _optimisticValue = false);
      _optimisticTimer?.cancel();
      wd.stopOwnedEngine(widget.engine).catchError((e) {
        DebugLog.log('ENGINE: home stopOwned ${widget.engine.name} FAILED: $e');
        if (mounted) setState(() => _optimisticValue = null);
      });
      DebugLog.log('ENGINE: home stop ${widget.engine.name} via wardrive session');
      return;
    }

    final appState = ref.read(appStateProvider);
    if (widget.engine == Engine.foxhunter && value) {
      if (appState.foxhunterTarget == null ||
          (appState.isManagerConnected && appState.foxhunterTargetNodeId == null)) {
        _navigateToEngine();
        return;
      }
    }
    if ((widget.engine == Engine.uniPwn || widget.engine == Engine.pcap) &&
        value && appState.isManagerConnected) {
      _navigateToEngine();
      return;
    }

    final ble = ref.read(bleManagerProvider);
    final targetNode = (widget.engine == Engine.foxhunter)
        ? appState.foxhunterTargetNodeId
        : null;
    setState(() => _optimisticValue = value);
    _optimisticTimer?.cancel();
    final fut = value
        ? ble.enableEngine(widget.engine, targetNodeId: targetNode,
            radio: appState.engineRadio[widget.engine])
        : ble.disableEngine(widget.engine, targetNodeId: targetNode);
    if (widget.engine == Engine.foxhunter && !value) {
      appState.endFoxhuntLiveActivity();
    }
    fut.catchError((e) {
      DebugLog.log('ENGINE: toggle ${widget.engine.name} -> $value FAILED: $e');
      if (!mounted) return;
      setState(() => _optimisticValue = null);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${widget.engine.label} ${value ? "enable" : "disable"} failed: $e')),
      );
    });
    _syncToPeers(value);
    DebugLog.log('ENGINE: toggle ${widget.engine.name} -> $value');
  }

  void _syncToPeers(bool enable) {
    // Mesh orchestration removed — single node only for now
  }

  void _cycleRadio() {
    // Don't allow radio change while engine is active
    if (widget.isActive || _displayActive) return;
    if (widget.engine == Engine.wardrive && ref.read(wardriveProvider).isActive) return;

    final appState = ref.read(appStateProvider);
    final current = appState.engineRadio[widget.engine] ?? 0x03;
    final next = switch (current) {
      0x01 => 0x02,
      0x02 => 0x03,
      _ => 0x01,
    };
    appState.setEngineRadio(widget.engine, next);
    if (widget.engine == Engine.wardrive) {
      ref.read(wardriveProvider).setRadio(switch (next) {
        0x01 => WardriveRadio.wifi,
        0x02 => WardriveRadio.ble,
        _ => WardriveRadio.both,
      });
    }
  }

  String _radioLabel(int radio) => switch (radio) {
    0x01 => 'WiFi',
    0x02 => 'BLE',
    _ => 'W+B',
  };

  IconData _radioIcon(int radio) => switch (radio) {
    0x01 => Icons.wifi,
    0x02 => Icons.bluetooth,
    _ => Icons.sensors,
  };

  void _navigateToEngine() {
    final route = switch (widget.engine) {
      Engine.detector => '/engine/detector',
      Engine.foxhunter => '/engine/foxhunter',
      Engine.skySpy => '/engine/skyspy',
      Engine.uniPwn => '/engine/unipwn',
      Engine.wardrive => '/wardrive',
      Engine.pcap => '/engine/pcap',
      _ => null,
    };
    if (route != null) context.push(route);
  }

  String get _engineDescription {
    if (widget.engine == Engine.wardrive) {
      final wd = ref.read(wardriveProvider);
      if (wd.isActive) {
        return '${wd.activeLabel} \u2022 ${wd.radio.label}';
      }
    }
    if (widget.engine == Engine.foxhunter) {
      final appState = ref.read(appStateProvider);
      final target = appState.foxhunterTarget;
      if (target != null) {
        final ch = appState.foxhunterChannel;
        return '${target.toUpperCase().substring(0, 8)}... ${ch > 0 ? 'ch$ch' : ''}';
      }
      return 'Set target to enable';
    }
    return widget.engine.description;
  }

  Color _stateColor(bool active, ResolvedTheme t) {
    if (_optimisticValue != null && _optimisticValue != widget.isActive) {
      return AppTheme.warning;
    }
    return switch (widget.engineState) {
      EngineState.disabled => t.textDim,
      EngineState.idle => t.textSecondary,
      EngineState.scanning => widget.engine.color,
      EngineState.active => AppTheme.success,
      EngineState.alerting => AppTheme.warning,
      EngineState.exploiting => AppTheme.error,
      _ => widget.engine.color,
    };
  }

  String get _stateLabel {
    if (_optimisticValue != null && _optimisticValue != widget.isActive) {
      return _optimisticValue! ? 'START' : 'STOP';
    }
    return switch (widget.engineState) {
      EngineState.disabled => 'OFF',
      EngineState.idle => 'IDLE',
      EngineState.scanning => 'SCAN',
      EngineState.active => 'ACTIVE',
      EngineState.alerting => 'ALERT',
      EngineState.targetSelected => 'TARGET',
      EngineState.connecting => 'LINK',
      EngineState.exploiting => 'EXPLOIT',
      EngineState.complete => 'DONE',
    };
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.size) {
      CardSize.hero => _buildHero(context),
      CardSize.medium => _buildMedium(context),
      CardSize.compact => _buildCompact(context),
    };
  }

  Widget _buildHero(BuildContext context) {
    final t = AppTheme.of(context);
    final color = widget.engine.color;
    final active = _displayActive;
    final hasActivity = widget.rate > 0 && active;

    return GestureDetector(
      onTap: _navigateToEngine,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = hasActivity ? _pulse.value * 0.15 : 0.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.06 + glow)
                  : t.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active ? color.withValues(alpha: 0.35) : t.border,
                width: active ? 1.0 : 0.5,
              ),
              boxShadow: hasActivity
                  ? [BoxShadow(color: color.withValues(alpha: 0.08 + glow), blurRadius: 20, spreadRadius: -2)]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: active
                        ? color.withValues(alpha: 0.15 + glow)
                        : t.border.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: hasActivity
                        ? [BoxShadow(color: color.withValues(alpha: 0.15 + glow), blurRadius: 12)]
                        : null,
                  ),
                  child: Icon(widget.engine.icon, color: active ? color : t.textDim, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.engine.label.toUpperCase(),
                        style: TextStyle(
                          color: active ? color : t.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _engineDescription,
                        style: TextStyle(color: t.textSecondary, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${widget.detectionCount}',
                            style: TextStyle(
                              color: active && widget.detectionCount > 0
                                  ? t.textPrimary : t.textSecondary,
                              fontSize: 24,
                              fontWeight: FontWeight.w200,
                              fontFamily: 'monospace',
                              height: 1,
                            ),
                          ),
                          if (widget.rate > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${widget.rate}/min',
                              style: TextStyle(
                                color: color.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (widget.engine == Engine.pcap) _autoPcapBadge(),
                          _stateBadge(active, t),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.scale(
                      scale: 0.65,
                      child: Switch(
                        value: active,
                        onChanged: _toggleEngine,
                        activeTrackColor: color.withValues(alpha: 0.25),
                        activeThumbColor: color,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16,
                        color: active ? color.withValues(alpha: 0.5) : t.textDim),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMedium(BuildContext context) {
    final t = AppTheme.of(context);
    final color = widget.engine.color;
    final active = _displayActive;
    final hasActivity = widget.rate > 0 && active;

    return GestureDetector(
      onTap: _navigateToEngine,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = hasActivity ? _pulse.value * 0.15 : 0.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.04 + glow)
                  : t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? color.withValues(alpha: 0.3) : t.border,
                width: active ? 1.0 : 0.5,
              ),
              boxShadow: hasActivity
                  ? [BoxShadow(color: color.withValues(alpha: 0.06 + glow), blurRadius: 16, spreadRadius: -2)]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: active
                            ? color.withValues(alpha: 0.12 + glow)
                            : t.border.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: hasActivity
                            ? [BoxShadow(color: color.withValues(alpha: 0.12 + glow), blurRadius: 8)]
                            : null,
                      ),
                      child: Icon(widget.engine.icon, color: active ? color : t.textDim, size: 18),
                    ),
                    const Spacer(),
                    Transform.scale(
                      scale: 0.55,
                      child: Switch(
                        value: active,
                        onChanged: _toggleEngine,
                        activeTrackColor: color.withValues(alpha: 0.25),
                        activeThumbColor: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.engine.label.toUpperCase(),
                  style: TextStyle(
                    color: active ? color : t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.engine.description,
                  style: TextStyle(color: t.textSecondary, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.detectionCount}',
                      style: TextStyle(
                        color: active && widget.detectionCount > 0
                            ? t.textPrimary : t.textSecondary,
                        fontSize: 26,
                        fontWeight: FontWeight.w200,
                        fontFamily: 'monospace',
                        height: 1,
                      ),
                    ),
                    if (widget.rate > 0) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${widget.rate}/min',
                          style: TextStyle(
                            color: color.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    _stateBadge(active, t),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final t = AppTheme.of(context);
    final color = widget.engine.color;
    final active = _displayActive;
    final hasActivity = widget.rate > 0 && active;

    return GestureDetector(
      onTap: _navigateToEngine,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = hasActivity ? _pulse.value * 0.15 : 0.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.04 + glow)
                  : t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? color.withValues(alpha: 0.3) : t.border,
                width: active ? 1.0 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: active
                        ? color.withValues(alpha: 0.12 + glow)
                        : t.border.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(widget.engine.icon, color: active ? color : t.textDim, size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.engine.label.toUpperCase(),
                        style: TextStyle(
                          color: active ? color : t.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        widget.engine.description,
                        style: TextStyle(color: t.textSecondary, fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.detectionCount > 0) ...[
                  Text(
                    '${widget.detectionCount}',
                    style: TextStyle(
                      color: active ? t.textPrimary : t.textSecondary,
                      fontSize: 18,
                      fontWeight: FontWeight.w300,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (widget.engine == Engine.pcap) _autoPcapBadge(),
                _stateBadge(active, t),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.5,
                  child: Switch(
                    value: active,
                    onChanged: _toggleEngine,
                    activeTrackColor: color.withValues(alpha: 0.25),
                    activeThumbColor: color,
                  ),
                ),
                Icon(Icons.chevron_right, size: 14,
                    color: active ? color.withValues(alpha: 0.5) : t.textDim),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _autoPcapBadge() {
    final ble = ref.read(bleManagerProvider);
    return StreamBuilder<PcapStats>(
      stream: ble.pcapStats,
      initialData: ble.latestPcapStats,
      builder: (context, snap) {
        final s = snap.data ?? PcapStats.empty;
        if (!s.autoEnabled) return const SizedBox.shrink();
        final live = s.autoRemainingMs > 0;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (live ? AppTheme.success : AppTheme.accent).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (live ? AppTheme.success : AppTheme.accent).withValues(alpha: 0.5),
                width: 0.8,
              ),
            ),
            child: Text(
              live ? 'AUTO ${(s.autoRemainingMs / 1000).ceil()}s' : 'AUTO ${s.autoDurationSec}s',
              style: TextStyle(
                color: live ? AppTheme.success : AppTheme.accent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stateBadge(bool active, ResolvedTheme t) {
    final appState = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final radio = (widget.engine == Engine.wardrive && wd.isActive)
        ? wd.radioBitmask
        : appState.engineRadio[widget.engine] ?? 0x03;

    final isLocked = active || (widget.engine == Engine.wardrive && wd.isActive);
    final chipColor = isLocked ? t.textDim : widget.engine.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.engine.isDualRadio) ...[
          GestureDetector(
            onTap: isLocked ? null : _cycleRadio,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: chipColor.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLocked)
                    Icon(Icons.lock, size: 10, color: chipColor)
                  else
                    Icon(_radioIcon(radio), size: 14, color: chipColor),
                  const SizedBox(width: 4),
                  Text(
                    _radioLabel(radio),
                    style: TextStyle(
                      color: chipColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _stateColor(active, t).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _stateColor(active, t).withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Text(
                _stateLabel,
                style: TextStyle(
                  color: _stateColor(active, t),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (widget.nodeCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.flockBle.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub, size: 8, color: AppTheme.flockBle.withValues(alpha: 0.8)),
                    const SizedBox(width: 3),
                    Text(
                      '+${widget.nodeCount}',
                      style: const TextStyle(
                        color: AppTheme.flockBle,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (widget.lastDetection != null) ...[
          const SizedBox(height: 3),
          Text(
            _formatLastSeen(widget.lastDetection!),
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}
