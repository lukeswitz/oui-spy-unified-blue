import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/engine_control.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/features/wardrive/session_launch.dart';
import 'package:oui_spy/theme/app_theme.dart';

class _Look {
  const _Look({
    required this.bg,
    required this.name,
    required this.dim,
    required this.icon,
    required this.count,
    required this.state,
    required this.locked,
    required this.alert,
  });

  final Color? bg;
  final Color name;
  final Color dim;
  final Color icon;
  final Color count;
  final Color state;
  final Color locked;
  final bool alert;

  factory _Look.of(ResolvedTheme t, bool active, EngineState s) {
    if (s == EngineState.alerting || s == EngineState.exploiting) {
      final bg = s == EngineState.alerting ? AppTheme.warning : AppTheme.error;
      final onBlack = AppTheme.contrast(Colors.black, bg);
      final fg = onBlack >= 4.5 || onBlack >= AppTheme.contrast(Colors.white, bg)
          ? Colors.black
          : Colors.white;
      return _Look(
        bg: bg,
        name: fg,
        dim: fg,
        icon: fg,
        count: fg,
        state: fg,
        locked: fg,
        alert: true,
      );
    }
    return _Look(
      bg: null,
      name: t.textPrimary,
      dim: t.textSecondary,
      icon: active ? AppTheme.accent : t.textSecondary,
      count: active ? t.textPrimary : t.textDim,
      state: active ? AppTheme.accent : t.textSecondary,
      locked: t.textSecondary,
      alert: false,
    );
  }
}

class EngineCard extends ConsumerStatefulWidget {
  const EngineCard({
    super.key,
    required this.engine,
    this.detectionCount = 0,
    this.isActive = false,
    this.engineState = EngineState.disabled,
    this.lastDetection,
    this.rate = 0,
    this.nodeCount = 0,
  });

  final Engine engine;
  final int detectionCount;
  final bool isActive;
  final EngineState engineState;
  final DateTime? lastDetection;
  final int rate;
  final int nodeCount;

  @override
  ConsumerState<EngineCard> createState() => _EngineCardState();
}

class _EngineCardState extends ConsumerState<EngineCard> {
  bool? _optimisticValue;
  Timer? _optimisticTimer;

  bool get _displayActive => _optimisticValue ?? widget.isActive;

  @override
  void didUpdateWidget(EngineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  bool get _canToggle =>
      widget.engine == Engine.wardrive ||
      widget.engine == Engine.foxhunter ||
      ref.watch(appStateProvider).isConnected;

  void _toggleEngine(bool value) {
    if (widget.engine == Engine.wardrive) {
      if (value) {
        unawaited(startWardriveSession(context, ref, requireLocation: false));
      } else {
        ref.read(wardriveProvider).stopSession();
      }
      return;
    }

    final appState = ref.read(appStateProvider);
    if (widget.engine == Engine.foxhunter && appState.foxhuntViaPhone && !value) {
      appState.clearFoxhunterTarget();
      return;
    }
    if (widget.engine == Engine.foxhunter && value && !appState.isConnected) {
      _navigateToEngine();
      return;
    }
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

    setState(() => _optimisticValue = value);
    _optimisticTimer?.cancel();
    setEngineEnabled(ref, widget.engine, value,
            targetNodeId: widget.engine == Engine.foxhunter ? appState.foxhunterTargetNodeId : null)
        .catchError((Object e) {
      DebugLog.log('ENGINE: toggle ${widget.engine.name} -> $value FAILED: $e');
      if (!mounted) return;
      setState(() => _optimisticValue = null);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${widget.engine.label} ${value ? "enable" : "disable"} failed: $e')),
      );
    });
    DebugLog.log('ENGINE: toggle ${widget.engine.name} -> $value');
  }

  void _cycleRadio() {
    if (widget.isActive || _displayActive) return;
    if (widget.engine == Engine.wardrive && ref.read(wardriveProvider).isActive) return;

    final appState = ref.read(appStateProvider);
    final current = appState.engineRadio[widget.engine] ?? 0x03;
    final next = switch (current) {
      0x01 => 0x02,
      0x02 => 0x03,
      _ => 0x01,
    };
    if (widget.engine == Engine.wardrive) {
      setWardriveRadio(ref, next);
    } else {
      appState.setEngineRadio(widget.engine, next);
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

  String get _stateLabel {
    if (_optimisticValue != null && _optimisticValue != widget.isActive) {
      return _optimisticValue! ? 'Starting' : 'Stopping';
    }
    return switch (widget.engineState) {
      EngineState.disabled => 'Off',
      EngineState.idle => 'Idle',
      EngineState.scanning => 'Scanning',
      EngineState.active => 'Active',
      EngineState.alerting => 'Alert',
      EngineState.targetSelected => 'Target',
      EngineState.connecting => 'Linking',
      EngineState.exploiting => 'Exploit',
      EngineState.complete => 'Done',
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
    final t = AppTheme.of(context);
    final active = _displayActive;
    final look = _Look.of(t, active, widget.engineState);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _navigateToEngine,
      child: Container(
        color: look.bg,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _iconWell(t, active, look),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _titleLine(active, t, look),
                  const SizedBox(height: 3),
                  _detailLine(t, look),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _count(look),
            const SizedBox(width: 12),
            _engineSwitch(active),
          ],
        ),
      ),
    );
  }

  Widget _iconWell(ResolvedTheme t, bool active, _Look look) {
    return Container(
      key: const ValueKey('engine-well'),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: look.alert
            ? look.icon.withValues(alpha: 0.16)
            : active
                ? AppTheme.accent.withValues(alpha: 0.16)
                : t.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Icon(widget.engine.icon, size: 18, color: look.icon),
    );
  }

  Widget _detailLine(ResolvedTheme t, _Look look) {
    final pending = _optimisticValue != null && _optimisticValue != widget.isActive;
    final stateColor = pending &&
            !look.alert &&
            AppTheme.contrast(AppTheme.warning, look.bg ?? t.surface) >= 4.5
        ? AppTheme.warning
        : pending && !look.alert
            ? t.textSecondary
            : look.state;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _stateLabel,
            style: TextStyle(color: stateColor, fontWeight: FontWeight.w500),
          ),
          TextSpan(text: ' · ${widget.engine.description}'),
          if (widget.lastDetection != null)
            TextSpan(text: ' · ${_formatLastSeen(widget.lastDetection!)}'),
          if (widget.rate > 0) TextSpan(text: ' · ${widget.rate}/min'),
        ],
      ),
      key: const ValueKey('engine-sub'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: look.dim, fontSize: 12),
    );
  }

  TextStyle _meta(Color color) => TextStyle(
        color: color,
        fontSize: 10,
        fontFamily: AppTheme.mono,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _count(_Look look) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 28, maxWidth: 56),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          '${widget.detectionCount}',
          maxLines: 1,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: look.count,
            fontSize: 17,
            fontWeight: FontWeight.w500,
            fontFamily: AppTheme.mono,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget _engineSwitch(bool active) {
    return SizedBox(
      height: 28,
      child: FittedBox(
        child: Switch(
          value: active,
          onChanged: _canToggle ? _toggleEngine : null,
        ),
      ),
    );
  }

  Widget _autoPcapBadge(_Look look) {
    final ble = ref.read(bleManagerProvider);
    return StreamBuilder<PcapStats>(
      stream: ble.pcapStats,
      initialData: ble.latestPcapStats,
      builder: (context, snap) {
        final s = snap.data ?? PcapStats.empty;
        if (!s.autoEnabled) return const SizedBox.shrink();
        final live = s.autoRemainingMs > 0;
        final color = look.dim;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: live ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            live ? 'AUTO ${(s.autoRemainingMs / 1000).ceil()}s' : 'AUTO ${s.autoDurationSec}s',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              fontFamily: AppTheme.mono,
            ),
          ),
        );
      },
    );
  }

  Widget _titleLine(bool active, ResolvedTheme t, _Look look) {
    final appState = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final radio = (widget.engine == Engine.wardrive && wd.isActive)
        ? wd.radioBitmask
        : appState.engineRadio[widget.engine] ?? 0x03;

    final isLocked = active || (widget.engine == Engine.wardrive && wd.isActive);
    final dim = look.dim;
    final extras = <Widget>[
      if (widget.engine.isDualRadio)
        GestureDetector(
          onTap: isLocked ? null : _cycleRadio,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: look.alert ? look.icon.withValues(alpha: 0.16) : t.surfaceLight,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isLocked ? Icons.lock_outline : _radioIcon(radio),
                    size: 11, color: isLocked ? look.locked : dim),
                const SizedBox(width: 3),
                Text(
                  _radioLabel(radio),
                  style: TextStyle(
                    color: isLocked ? look.locked : dim,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (widget.engine == Engine.pcap) _autoPcapBadge(look),
      if (widget.nodeCount > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 10, color: dim),
            const SizedBox(width: 3),
            Text('+${widget.nodeCount}', style: _meta(dim)),
          ],
        ),
    ];

    return SizedBox(
      height: 20,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.engine.label,
              maxLines: 1,
              style: TextStyle(color: look.name, fontSize: 15, fontWeight: FontWeight.w500),
            ),
            for (var i = 0; i < extras.length; i++) ...[
              const SizedBox(width: 8),
              extras[i],
            ],
          ],
        ),
      ),
    );
  }
}
