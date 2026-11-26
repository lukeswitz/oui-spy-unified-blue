// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/meshtastic/mesh_alerts.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/features/config/meshtastic_section.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/text_prompt_dialog.dart';

/// Settings > Data > Meshtastic radio: the phone's radio, then the alerts it sends on its own.
class MeshtasticSettingsPage extends StatelessWidget {
  const MeshtasticSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: const [
        MeshtasticSection(),
        SizedBox(height: 16),
        MeshtasticAlertsSection(),
      ],
    );
  }
}

String meshGapLabel(int seconds) {
  if (seconds < 60) return '$seconds s';
  final m = seconds ~/ 60, s = seconds % 60;
  return s == 0 ? '$m min' : '$m min $s s';
}

IconData _typeIcon(MeshAlertType t) => switch (t) {
      MeshAlertType.flock => Icons.camera_outdoor,
      MeshAlertType.drone => Icons.flight,
      MeshAlertType.detector => Icons.radar,
      MeshAlertType.foxhunt => Icons.my_location,
      MeshAlertType.nodes => Icons.wifi_off,
    };

class MeshtasticAlertsSection extends ConsumerStatefulWidget {
  const MeshtasticAlertsSection({super.key});

  @override
  ConsumerState<MeshtasticAlertsSection> createState() => _MeshtasticAlertsSectionState();
}

class _MeshtasticAlertsSectionState extends ConsumerState<MeshtasticAlertsSection> {
  double? _gap;
  double? _cap;

  Future<void> _toggle(bool on) async {
    final n = ref.read(meshAlertProvider.notifier);
    if (!on) {
      await n.setEnabled(false);
      return;
    }
    final channel = ref.read(meshtasticProvider).channel?.label;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send alerts automatically?'),
        content: Text('Each alert you choose below goes out by LoRa radio without a tap, on '
            '${channel ?? 'the private channel'} or straight to the nodes you pick. Everyone on the channel can read it, '
            'including what was detected and the device address. Your position is never sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('TURN ON')),
        ],
      ),
    );
    if (ok == true && mounted) await n.setEnabled(true);
  }

  Future<void> _pickNodes() async {
    final current = ref.read(meshAlertProvider).nodes.join(' ');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Send to nodes',
        confirmLabel: 'SAVE',
        initial: current,
        message: 'Leave it empty to send on the private channel. Otherwise each alert goes straight to these nodes. '
            'Up to $meshAlertMaxNodes, like !0a1b2c3d.',
        labelText: 'Send to nodes instead (optional)',
        hintText: '!0a1b2c3d',
        isValid: (t) {
          final r = parseMeshNodeIds(t);
          return r.bad.isEmpty && r.nodes.length <= meshAlertMaxNodes;
        },
      ),
    );
    if (text == null || !mounted) return;
    await ref.read(meshAlertProvider.notifier).setNodes(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(meshAlertProvider);
    final mesh = ref.watch(meshtasticProvider);
    final n = ref.read(meshAlertProvider.notifier);
    final t = AppTheme.of(context);
    final now = n.now;
    final gap = _gap ?? s.gapSeconds.toDouble();
    final cap = _cap ?? s.dailyCap.toDouble();
    final blocked = mesh.link != MtLinkState.ready || mesh.channel == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConfigSectionHeader(label: 'Automatic alerts', info: [
          "Send the app's alerts by LoRa through the paired radio without a tap, on the private channel or straight to chosen nodes.",
          'Only alerts that already notify you are sent. Silenced alerts and silent suspected detections are not.',
          'Nothing goes out unless the radio is connected and a private channel is picked. An alert that cannot go out is counted as skipped.',
          'A message holds what was detected, including the device address. A position is never sent.',
        ]),
        ConfigToggleRow(
          icon: Icons.sensors,
          label: 'Send alerts automatically',
          subtitle: s.enabled ? 'On: alerts go out by radio without a tap' : 'Off: nothing is sent unless you tap send',
          color: AppTheme.accent,
          value: s.enabled,
          notify: false,
          onChanged: _toggle,
        ),
        if (s.enabled && blocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text('Alerts are skipped until the radio is connected and a private channel is picked.',
                style: TextStyle(color: t.textDim, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        const ConfigSectionHeader(label: 'Alert types', info: [
          'Choose which alerts go out. Foxhunt is off by default because it is frequent.',
        ]),
        for (final type in MeshAlertType.values)
          ConfigToggleRow(
            icon: _typeIcon(type),
            label: type.label,
            subtitle: type.hint,
            color: AppTheme.accent,
            value: s.types.contains(type),
            notify: false,
            onChanged: (v) => n.setType(type, v),
          ),
        const SizedBox(height: 12),
        const ConfigSectionHeader(label: 'Limits', info: [
          'LoRa airtime is shared by every radio in range. The gap spaces messages out and the daily cap stops a busy day from flooding the channel.',
          'Alerts over a limit are skipped, not queued.',
        ]),
        ConfigSliderRow(
          icon: Icons.timer_outlined,
          label: 'Minimum gap between messages',
          valueLabel: meshGapLabel(gap.round()),
          min: meshAlertMinGap.toDouble(),
          max: meshAlertMaxGap.toDouble(),
          divisions: (meshAlertMaxGap - meshAlertMinGap) ~/ 10,
          value: gap.clamp(meshAlertMinGap.toDouble(), meshAlertMaxGap.toDouble()),
          onChanged: (v) => setState(() => _gap = v),
          onChangeEnd: (v) async {
            await n.setGap(v.round());
            if (mounted) setState(() => _gap = null);
          },
        ),
        ConfigSliderRow(
          icon: Icons.stacked_bar_chart,
          label: 'Messages per day',
          valueLabel: '${cap.round()}',
          min: meshAlertMinCap.toDouble(),
          max: meshAlertMaxCap.toDouble(),
          divisions: meshAlertMaxCap - meshAlertMinCap,
          value: cap.clamp(meshAlertMinCap.toDouble(), meshAlertMaxCap.toDouble()),
          onChanged: (v) => setState(() => _cap = v),
          onChangeEnd: (v) async {
            await n.setCap(v.round());
            if (mounted) setState(() => _cap = null);
          },
        ),
        ConfigInfoRow(
          icon: Icons.today,
          label: 'Sent today',
          value: '${s.sentOn(now)} of ${s.dailyCap} · skipped ${s.skippedOn(now)}',
          monospace: false,
        ),
        const SizedBox(height: 12),
        const ConfigSectionHeader(label: 'Destination', info: [
          'By default an alert goes to everyone on the private channel picked above.',
          'Name up to $meshAlertMaxNodes nodes to send each alert straight to them instead. They need the same channel key to read it.',
        ]),
        ConfigActionRow(
          icon: Icons.alt_route,
          label: 'Send to',
          subtitle: s.nodes.isEmpty ? 'The private channel${mesh.channel == null ? '' : ': ${mesh.channel!.label}'}' : s.nodes.join(', '),
          onTap: _pickNodes,
          trailing: Icon(Icons.chevron_right, size: 18, color: t.textDim),
        ),
      ],
    );
  }
}
