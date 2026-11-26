// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_link.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_proto.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/text_prompt_dialog.dart';

/// The phone's Meshtastic radio: pair one over Bluetooth, pick a private channel, send a message or the phone's
/// position, and read what the radio hears on that channel.
class MeshtasticSection extends ConsumerStatefulWidget {
  const MeshtasticSection({super.key});

  @override
  ConsumerState<MeshtasticSection> createState() => _MeshtasticSectionState();
}

class _MeshtasticSectionState extends ConsumerState<MeshtasticSection> {
  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _find() async {
    final n = ref.read(meshtasticProvider.notifier);
    await n.scan();
    if (!mounted) return;
    final found = ref.read(meshtasticProvider).found;
    final pick = await showDialog<MtRadioFound>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Meshtastic radios nearby'),
        content: found.isEmpty
            ? const Text('None found. Turn the radio and its Bluetooth on, and disconnect it from the Meshtastic app '
                '(a radio takes one phone at a time).')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in found)
                      ListTile(
                        title: Text(r.name.isEmpty ? r.id : r.name),
                        subtitle: Text('${r.rssi} dBm'),
                        onTap: () => Navigator.pop(ctx, r),
                      ),
                  ],
                ),
              ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL'))],
      ),
    );
    if (pick != null) await n.connect(radio: pick);
  }

  Future<void> _pickChannel() async {
    final s = ref.read(meshtasticProvider);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Channel'),
        content: s.privateChannels.isEmpty
            ? const Text('This radio has no channel with a key of its own. Add a private channel in the Meshtastic app. '
                'The app never sends on the public channel.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in s.privateChannels)
                      ListTile(
                        title: Text(c.label),
                        subtitle: Text('Channel ${c.index}'),
                        selected: c.index == s.channelIndex,
                        onTap: () => Navigator.pop(ctx, c.index),
                      ),
                  ],
                ),
              ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL'))],
      ),
    );
    if (picked == null) return;
    final why = await ref.read(meshtasticProvider.notifier).selectChannel(picked);
    if (mounted && why != null) _say(why);
  }

  Future<void> _sendText() async {
    final s = ref.read(meshtasticProvider);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Send a message',
        confirmLabel: 'SEND',
        message: 'On ${s.channel?.label ?? 'the private channel'}. Everyone on it can read it.',
        maxLength: MeshtasticProto.maxTextBytes,
        isValid: (t) => t.trim().isNotEmpty,
      ),
    );
    if (text == null || !mounted) return;
    final why = await ref.read(meshtasticProvider.notifier).sendText(text);
    if (mounted) _say(why ?? 'Sent on the mesh');
  }

  Future<void> _sendPosition() async {
    final p = ref.read(gpsProvider).lastPosition;
    if (p == null) {
      _say('No position yet');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send your position?'),
        content: const Text('Your current position goes out by radio on the private channel. Everyone on it can read it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SEND')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final why = await ref.read(meshtasticProvider.notifier).sendPosition(p.latitude, p.longitude, altitude: p.altitude);
    if (mounted) _say(why ?? 'Position sent on the mesh');
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this radio?'),
        content: const Text('The app disconnects from it and forgets it and its channel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('FORGET'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(meshtasticProvider.notifier).forget();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(meshtasticProvider);
    final n = ref.read(meshtasticProvider.notifier);
    final t = AppTheme.of(context);
    final busy = s.link == MtLinkState.scanning || s.link == MtLinkState.connecting;
    final color = switch (s.link) {
      MtLinkState.ready => AppTheme.accent,
      MtLinkState.error => AppTheme.error,
      MtLinkState.scanning || MtLinkState.connecting => AppTheme.warning,
      MtLinkState.off => t.textDim,
    };
    final name = s.radioName.isEmpty ? 'radio' : s.radioName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConfigSectionHeader(label: 'Meshtastic radio', info: [
          "Pair this phone's own Meshtastic radio over Bluetooth to send messages and your position by LoRa when you have no network.",
          'Nothing is sent unless you tap a send button, and only on a private channel, never the public one.',
        ]),
        ConfigInfoRow(
          icon: Icons.settings_input_antenna,
          label: 'This phone\'s radio',
          value: s.hasRadio ? '${s.link.label}  ·  $name' : 'No radio',
          color: color,
        ),
        if (s.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(s.error, style: TextStyle(color: t.textDim, fontSize: 13)),
          ),
        if (!s.hasRadio || s.link == MtLinkState.scanning)
          ConfigActionRow(
            icon: Icons.bluetooth_searching,
            label: 'Find a radio',
            subtitle: s.link == MtLinkState.scanning ? 'Looking for radios' : 'Scans Bluetooth for Meshtastic radios',
            onTap: busy ? null : _find,
          ),
        if (s.hasRadio && s.link != MtLinkState.ready)
          ConfigActionRow(
            icon: Icons.bluetooth_connected,
            label: 'Connect to $name',
            subtitle: s.link == MtLinkState.connecting ? 'Connecting' : 'Out of range or held by another phone fails',
            onTap: busy ? null : () => n.connect(),
          ),
        if (s.link == MtLinkState.ready) ...[
          ConfigActionRow(
            icon: Icons.tag,
            label: 'Channel',
            subtitle: s.channel?.label ?? (s.privateChannels.isEmpty ? 'No private channel on this radio' : 'Pick a private channel'),
            onTap: _pickChannel,
          ),
          ConfigInfoRow(icon: Icons.hub_outlined, label: 'Nodes heard', value: '${s.nodes.length}'),
          ConfigInfoRow(icon: Icons.swap_vert, label: 'Sent / heard', value: '${s.sent} / ${s.heard}'),
          ConfigActionRow(
            icon: Icons.chat_bubble_outline,
            label: 'Send a message',
            subtitle: 'Up to ${MeshtasticProto.maxTextBytes} characters, on the private channel',
            onTap: s.channel == null ? null : _sendText,
          ),
          ConfigActionRow(
            icon: Icons.my_location,
            label: 'Send my position',
            subtitle: "This phone's last position, once",
            onTap: s.channel == null ? null : _sendPosition,
          ),
          if (s.inbox.isNotEmpty) ...[
            const SizedBox(height: 12),
            const ConfigSectionHeader(label: 'Heard on the radio'),
            for (final m in s.inbox.take(5))
              ConfigInfoRow(
                icon: Icons.chat_outlined,
                label: s.nodes[m.from]?.label ?? meshtasticNodeId(m.from),
                value: m.text,
                monospace: false,
              ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text('Nothing heard yet. Text messages on the private channel land here.',
                  style: TextStyle(color: t.textDim, fontSize: 13)),
            ),
        ],
        if (s.hasRadio) ...[
          if (s.link == MtLinkState.ready)
            ConfigActionRow(icon: Icons.link_off, label: 'Disconnect', onTap: n.disconnect),
          ConfigActionRow(icon: Icons.swap_horiz, label: 'Change radio', onTap: busy ? null : _find),
          ConfigActionRow(icon: Icons.delete_outline, label: 'Forget this radio', destructive: true, onTap: _forget),
        ],
      ],
    );
  }
}
