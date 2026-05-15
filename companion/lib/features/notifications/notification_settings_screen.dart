import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/theme/app_theme.dart';

class NotificationSettingsBody extends ConsumerWidget {
  const NotificationSettingsBody({super.key, this.shrinkWrap = false, this.physics});

  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final notif = ref.watch(notificationServiceProvider);

    return ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Permission status
          if (!notif.permissionGranted)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppTheme.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notification permission not granted. Enable in system settings.',
                      style: TextStyle(color: AppTheme.warning, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => notif.init(),
                    child: const Text('RETRY', style: TextStyle(
                      color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w700,
                    )),
                  ),
                ],
              ),
            ),

          // Engine toggles
          _SectionHeader(label: 'DETECTION ALERTS', t: t),
          _ToggleRow(
            icon: Icons.videocam,
            label: 'Flock Safety',
            subtitle: 'Alert on new camera detection',
            color: const Color(0xFFB44AFF),
            value: notif.flockEnabled,
            onChanged: notif.setFlockEnabled,
            t: t,
          ),
          _ToggleRow(
            icon: Icons.radar,
            label: 'Watchlist / Detector',
            subtitle: 'Alert on watchlist MAC hits',
            color: const Color(0xFF4A9EFF),
            value: notif.detectorEnabled,
            onChanged: notif.setDetectorEnabled,
            t: t,
          ),
          _ToggleRow(
            icon: Icons.flight,
            label: 'Drone / Sky Spy',
            subtitle: 'Alert on Remote ID drone detection',
            color: const Color(0xFF4AFFEA),
            value: notif.droneEnabled,
            onChanged: notif.setDroneEnabled,
            t: t,
          ),
          _ToggleRow(
            icon: Icons.gps_fixed,
            label: 'Foxhunt Proximity',
            subtitle: 'Alert when target signal crosses thresholds',
            color: const Color(0xFF4AFF8A),
            value: notif.foxhuntEnabled,
            onChanged: notif.setFoxhuntEnabled,
            t: t,
          ),

          const SizedBox(height: 16),
          _SectionHeader(label: 'WARDRIVE', t: t),
          _ToggleRow(
            icon: Icons.emoji_events,
            label: 'Milestone Alerts',
            subtitle: 'Notify every 1000 unique networks',
            color: AppTheme.accent,
            value: notif.milestoneAlertsEnabled,
            onChanged: notif.setMilestoneAlertsEnabled,
            t: t,
          ),

          const SizedBox(height: 16),
          _SectionHeader(label: 'BEHAVIOR', t: t),

          // Cooldown slider
          _SliderRow(
            icon: Icons.timer,
            label: 'Cooldown per device',
            valueLabel: _formatCooldown(notif.cooldownSeconds),
            min: 30,
            max: 1800,
            divisions: 59,
            value: notif.cooldownSeconds.toDouble(),
            onChanged: (v) => notif.setCooldownSeconds(v.round()),
            t: t,
          ),

          // Rate limit slider
          _SliderRow(
            icon: Icons.speed,
            label: 'Max alerts per minute',
            valueLabel: '${notif.maxPerMinute}',
            min: 1,
            max: 30,
            divisions: 29,
            value: notif.maxPerMinute.toDouble(),
            onChanged: (v) => notif.setMaxPerMinute(v.round()),
            t: t,
          ),

          const SizedBox(height: 16),
          _SectionHeader(label: 'OUTPUT', t: t),
          _ToggleRow(
            icon: Icons.volume_up,
            label: 'Sound',
            subtitle: 'Play alert sound',
            color: t.textSecondary,
            value: notif.soundEnabled,
            onChanged: notif.setSoundEnabled,
            t: t,
          ),
          _ToggleRow(
            icon: Icons.vibration,
            label: 'Vibration',
            subtitle: 'Haptic feedback on alert',
            color: t.textSecondary,
            value: notif.vibrationEnabled,
            onChanged: notif.setVibrationEnabled,
            t: t,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.t});
  final String label;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(label, style: TextStyle(
        color: t.textDim, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 2,
      )),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
    required this.t,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? color : t.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600,
                )),
                Text(subtitle, style: TextStyle(
                  color: t.textDim, fontSize: 10,
                )),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: color.withValues(alpha: 0.5),
            activeThumbColor: color,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    required this.t,
  });
  final IconData icon;
  final String label;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;
  final ResolvedTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: t.textDim),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w500,
              )),
              const Spacer(),
              Text(valueLabel, style: TextStyle(
                color: AppTheme.accent, fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.w600,
              )),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 2,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: AppTheme.accent,
              inactiveColor: t.border,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
