// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/dashboard/dashboard_meshtastic.dart';
import 'package:oui_spy/core/dashboard/dashboard_state.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

const meshTestText = 'OUI-APEX Mesh: test message from the dashboard.';

String meshAgo(DateTime at, [DateTime? now]) {
  final s = (now ?? DateTime.now()).difference(at).inSeconds;
  if (s < 5) return 'just now';
  if (s < 60) return '$s s ago';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return '${s ~/ 3600} h ago';
  return '${s ~/ 86400} d ago';
}

Future<void> showMeshtasticDashboardSheet(BuildContext context, {Duration pollEvery = const Duration(seconds: 5)}) {
  final t = AppTheme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surface,
    isScrollControlled: true,
    builder: (_) => MeshtasticDashboardSheet(pollEvery: pollEvery),
  );
}

/// The home dashboard's Meshtastic link: radio port, channel, which events it sends, a test message, its state
/// and what the radio hears. Everything is read from and saved to the dashboard.
class MeshtasticDashboardSheet extends ConsumerStatefulWidget {
  const MeshtasticDashboardSheet({super.key, this.pollEvery = const Duration(seconds: 5)});

  final Duration pollEvery;

  @override
  ConsumerState<MeshtasticDashboardSheet> createState() => _MeshtasticDashboardSheetState();
}

class _MeshtasticDashboardSheetState extends ConsumerState<MeshtasticDashboardSheet> {
  final _port = TextEditingController();
  final _recipients = TextEditingController();
  Timer? _timer;
  MeshtasticStatus _status = const MeshtasticStatus();
  MeshtasticConfig _cfg = const MeshtasticConfig();
  List<MeshPort> _ports = const [];
  String? _portsError;
  String _loadError = '';
  String _note = '';
  bool _loaded = false;
  bool _saving = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadPorts();
    _timer = Timer.periodic(widget.pollEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _port.dispose();
    _recipients.dispose();
    super.dispose();
  }

  DashboardNotifier get _dash => ref.read(dashboardProvider.notifier);

  void _fill(MeshtasticConfig c) {
    _cfg = c;
    _port.text = c.port;
    _recipients.text = c.recipients.join(' ');
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await _dash.loadMeshtastic();
      if (!mounted) return;
      setState(() {
        final s = r.status;
        if (s == null) {
          _loadError = r.error ?? '';
          return;
        }
        _loadError = '';
        _status = s;
        if (!_loaded) {
          _loaded = true;
          _fill(s.config);
        }
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadPorts() async {
    final r = await _dash.loadPorts();
    if (!mounted) return;
    setState(() {
      _ports = r.ports;
      _portsError = r.error;
    });
  }

  MeshtasticConfig _current() => _cfg.copyWith(
        port: _port.text.trim(),
        recipients: _recipients.text.split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList(),
      );

  bool get _dirty {
    final c = _current(), s = _status.config;
    return c.enabled != s.enabled ||
        c.port != s.port ||
        c.channel != s.channel ||
        c.recipients.join(' ') != s.recipients.join(' ') ||
        meshEventKinds.any((k) => c.send[k] != s.send[k]);
  }

  Future<void> _save() async {
    final c = _current();
    if (c.recipients.any((r) => !isMeshNodeId(r))) {
      setState(() => _note = 'A node id is ! and 8 hex digits, like !0a1b2c3d');
      return;
    }
    setState(() {
      _saving = true;
      _note = '';
    });
    final why = await _dash.saveMeshtastic(c);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _note = why != null ? 'Not saved: $why' : 'Meshtastic settings saved';
    });
    if (why == null) await _refresh();
  }

  Future<void> _test() async {
    final saved = _status.config;
    final unsaved = _dirty;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send a test?'),
        content: Text('The dashboard sends "$meshTestText" on channel ${saved.channel}'
            '${saved.recipients.isEmpty ? '' : ' and to each recipient'}, as last saved. '
            'Everyone on that channel sees it.'
            '${unsaved ? '\n\nThe changes on this screen are not saved yet, so they are not used.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SEND')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final why = await _dash.testMeshtastic();
    if (!mounted) return;
    setState(() => _note = why != null ? 'Test not sent: $why' : 'Test queued');
    await _refresh();
  }

  Color _stateColor(String state, ResolvedTheme t) => switch (state) {
        'connected' => AppTheme.accent,
        'connecting' || 'retrying' => AppTheme.warning,
        'error' => AppTheme.error,
        _ => t.textDim,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final s = _status;
    final heading = TextStyle(color: t.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 3);
    final note = TextStyle(color: t.textDim, fontSize: 13);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('MESHTASTIC', style: heading),
              if (_loadError.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_loadError, style: note)),
              if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note, style: note)),
              const SizedBox(height: 8),
              ConfigToggleRow(
                icon: Icons.settings_input_antenna,
                label: 'Enabled',
                subtitle: 'Send alerts over the Meshtastic mesh',
                color: AppTheme.accent,
                value: _cfg.enabled,
                notify: false,
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(enabled: v)),
              ),
              const SizedBox(height: 12),
              const ConfigSectionHeader(label: 'Ports'),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextField(
                  controller: _port,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Radio port', hintText: '/dev/ttyUSB0, or tcp:<host>'),
                ),
              ),
              if (_ports.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_portsError ?? 'No serial ports.', style: note),
                ),
              for (final p in _ports)
                ConfigActionRow(
                  icon: Icons.usb,
                  label: p.device,
                  subtitle: [if (p.desc.isNotEmpty) p.desc, if (p.espressif) 'an ESP32 (likely one of our nodes)'].join('  ·  '),
                  trailing: _port.text.trim() == p.device ? Icon(Icons.check, color: AppTheme.accent) : const SizedBox(width: 22),
                  onTap: () => setState(() => _port.text = p.device),
                ),
              const SizedBox(height: 12),
              const ConfigSectionHeader(label: 'CHANNEL'),
              if (s.channels.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                      'Channel ${_cfg.channel}. The channels of the radio show here once the dashboard is connected to it.',
                      style: note),
                ),
              for (final c in s.channels)
                ConfigActionRow(
                  icon: Icons.forum_outlined,
                  label: '${c.index}: ${c.name}',
                  subtitle: c.private ? null : 'Public channel: the dashboard does not send on it',
                  trailing: _cfg.channel == c.index ? Icon(Icons.check, color: AppTheme.accent) : const SizedBox(width: 22),
                  onTap: c.private ? () => setState(() => _cfg = _cfg.copyWith(channel: c.index)) : null,
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _recipients,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Also send to nodes (optional)', helperText: 'Up to 4, like !0a1b2c3d'),
                ),
              ),
              const SizedBox(height: 12),
              const ConfigSectionHeader(label: 'Send'),
              for (final k in meshEventKinds)
                ConfigToggleRow(
                  icon: switch (k) {
                    'new_devices' => Icons.fiber_new,
                    'drones' => Icons.flight,
                    'lost_nodes' => Icons.wifi_off,
                    _ => Icons.hub_outlined,
                  },
                  label: meshEventTitle(k),
                  subtitle: meshEventHint(k),
                  color: AppTheme.accent,
                  value: _cfg.send[k] ?? false,
                  notify: false,
                  onChanged: (v) => setState(() => _cfg = _cfg.copyWith(send: {..._cfg.send, k: v})),
                ),
              ConfigActionRow(
                icon: Icons.save_outlined,
                label: _saving ? 'Saving' : 'Save',
                subtitle: _dirty ? 'Changes not saved yet' : null,
                onTap: _saving ? null : _save,
              ),
              if (_dirty)
                ConfigActionRow(
                  icon: Icons.undo,
                  label: 'Undo',
                  onTap: () => setState(() => _fill(_status.config)),
                ),
              const SizedBox(height: 12),
              const ConfigSectionHeader(label: 'Link'),
              ConfigInfoRow(
                  icon: Icons.link, label: 'Link', value: meshStateLabel(s.state), color: _stateColor(s.state, t)),
              ConfigInfoRow(
                  icon: Icons.router_outlined,
                  label: 'Radio',
                  value: s.radio.isEmpty ? '-' : (s.radioName.isEmpty ? s.radio : '${s.radioName} ${s.radio}')),
              ConfigInfoRow(icon: Icons.forum_outlined, label: 'Channel', value: s.channelName.isEmpty ? '-' : s.channelName),
              ConfigInfoRow(icon: Icons.send_outlined, label: 'Sent', value: '${s.sent}'),
              ConfigInfoRow(icon: Icons.error_outline, label: 'Failed', value: '${s.failed}'),
              ConfigInfoRow(icon: Icons.schedule, label: 'Queued', value: '${s.queued}'),
              ConfigInfoRow(icon: Icons.hearing, label: 'Heard', value: '${s.heard}'),
              ConfigInfoRow(
                  icon: Icons.history, label: 'Last sent', value: s.last == null ? 'never' : meshAgo(s.last!)),
              if (s.error.isNotEmpty)
                ConfigInfoRow(icon: Icons.warning_amber, label: 'Last error', value: s.error, color: AppTheme.warning),
              ConfigActionRow(
                icon: Icons.outgoing_mail,
                label: 'Send a test',
                subtitle: s.connected ? 'On the channel, as last saved' : 'Needs a connected radio',
                onTap: s.connected ? _test : null,
              ),
              const SizedBox(height: 12),
              const ConfigSectionHeader(label: 'Heard on the radio'),
              if (s.inbox.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('Nothing heard yet. Text messages on the channel land here.', style: note),
                ),
              for (final m in s.inbox.take(20))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m.who}  ·  ${meshAgo(m.at)}', style: note),
                      Text(m.text, style: TextStyle(color: t.textPrimary, fontSize: 15)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Meshtastic airtime is shared by every radio in range: the dashboard batches new devices and spaces '
                  "its messages out. It only sends on a channel with a key of its own. Pick a channel the fleet's "
                  'Meshtastic radios share.',
                  style: note,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
