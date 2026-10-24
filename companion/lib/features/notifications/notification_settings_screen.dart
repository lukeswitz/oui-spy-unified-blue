import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

class NotificationSettingsBody extends ConsumerWidget {
  const NotificationSettingsBody({
    super.key,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notif = ref.watch(notificationServiceProvider);
    final t = AppTheme.of(context);

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: padding,
      children: [
        if (!notif.permissionGranted)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: AppTheme.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notification permission not granted. Enable in system settings.',
                    style: TextStyle(color: AppTheme.warning, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => notif.init(),
                  child: Text('RETRY', style: TextStyle(
                    color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w700,
                  )),
                ),
              ],
            ),
          ),

        if (notif.mutedAlerts.isNotEmpty) ...[
          const ConfigSectionHeader(label: 'Muted · logged, no notification'),
          for (final k in {for (final k in notif.mutedAlerts) NotificationService.muteLabel(k): k}.entries)
            ConfigToggleRow(
              icon: Icons.notifications_off_outlined,
              label: k.key,
              color: AppTheme.detector,
              value: false,
              onChanged: (_) => notif.setMuted(
                [for (final m in notif.mutedAlerts) if (NotificationService.muteLabel(m) == k.key) m],
                false,
              ),
            ),
          const SizedBox(height: 16),
        ],
        ConfigSectionHeader(label: 'Foxhunt'),
        ConfigToggleRow(
          icon: Icons.gps_fixed,
          label: 'Foxhunt Proximity',
          subtitle: 'Alert when target signal crosses thresholds',
          color: Engine.foxhunter.color,
          value: notif.foxhuntEnabled,
          onChanged: notif.setFoxhuntEnabled,
        ),

        const SizedBox(height: 16),
        ConfigSectionHeader(label: 'Wardrive'),
        ConfigToggleRow(
          icon: Icons.emoji_events,
          label: 'Milestone Alerts',
          subtitle: 'Notify every 1000 unique networks',
          color: AppTheme.accent,
          value: notif.milestoneAlertsEnabled,
          onChanged: notif.setMilestoneAlertsEnabled,
        ),

        const SizedBox(height: 16),
        ConfigSectionHeader(label: 'Behavior'),
        ConfigSliderRow(
          icon: Icons.timer,
          label: 'Cooldown per device',
          valueLabel: _formatCooldown(notif.cooldownSeconds),
          min: 30,
          max: 1800,
          divisions: 59,
          value: notif.cooldownSeconds.toDouble(),
          onChanged: (v) => notif.setCooldownSeconds(v.round()),
        ),
        ConfigSliderRow(
          icon: Icons.speed,
          label: 'Max alerts per minute',
          valueLabel: '${notif.maxPerMinute}',
          min: 1,
          max: 30,
          divisions: 29,
          value: notif.maxPerMinute.toDouble(),
          onChanged: (v) => notif.setMaxPerMinute(v.round()),
        ),

        const SizedBox(height: 16),
        ConfigSectionHeader(label: 'Output'),
        ConfigToggleRow(
          icon: Icons.volume_up,
          label: 'Sound',
          subtitle: 'Play alert sound',
          color: t.textSecondary,
          value: notif.soundEnabled,
          onChanged: notif.setSoundEnabled,
        ),
        ConfigToggleRow(
          icon: Icons.vibration,
          label: 'Vibration',
          subtitle: 'Haptic feedback on alert',
          color: t.textSecondary,
          value: notif.vibrationEnabled,
          onChanged: notif.setVibrationEnabled,
        ),
      ],
    );
  }

  static String _formatCooldown(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }
}
