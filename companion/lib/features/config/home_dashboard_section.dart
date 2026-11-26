// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/dashboard/dashboard_api.dart';
import 'package:oui_spy/core/dashboard/dashboard_state.dart';
import 'package:oui_spy/features/config/meshtastic_dashboard_sheet.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/text_prompt_dialog.dart';

String connectorStatus(DashboardConnector c, ConnectorInfo i) {
  if (!i.enabled) return 'Off';
  final sent = i.sent == null ? '' : ', ${i.sent} sent';
  if (i.up) return 'Connected$sent';
  if (i.state == 'connecting') return 'Connecting';
  if (i.state == 'retrying') return 'Not connected: retrying';
  final why = i.error.isNotEmpty ? i.error : i.detail;
  return why.isEmpty ? 'Down' : 'Down: $why';
}

/// The home dashboard link: where it is, whether it answers, its MQTT, TAK and Reticulum links, and how
/// long it keeps history.
class HomeDashboardSection extends ConsumerStatefulWidget {
  const HomeDashboardSection({super.key});

  @override
  ConsumerState<HomeDashboardSection> createState() => _HomeDashboardSectionState();
}

class _HomeDashboardSectionState extends ConsumerState<HomeDashboardSection> {
  late final TextEditingController _host;
  late final TextEditingController _token;
  bool _hostLoaded = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController();
    _token = TextEditingController();
  }

  @override
  void dispose() {
    _host.dispose();
    _token.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _saveHost() async {
    final text = _host.text.trim();
    if (text.isNotEmpty && DashboardEndpoint.parse(text) == null) {
      _say('Enter an IP address or name, with a port if it is not 5077');
      return;
    }
    await ref.read(dashboardProvider.notifier).setHost(text);
    if (mounted) _say(text.isEmpty ? 'Dashboard address cleared' : 'Dashboard address saved: $text');
  }

  Future<void> _saveToken() async {
    await ref.read(dashboardProvider.notifier).setToken(_token.text);
    if (!mounted) return;
    final empty = _token.text.trim().isEmpty;
    _token.clear();
    _say(empty ? 'Access token removed' : 'Access token saved');
  }

  Future<void> _toggle(DashboardConnector c, bool on) async {
    final why = await ref.read(dashboardProvider.notifier).setConnector(c, on);
    if (mounted && why != null) _say('Not changed: $why');
  }

  Future<void> _editRetention(int current) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'Keep history for',
        confirmLabel: 'SAVE',
        initial: '$current',
        labelText: 'Days',
        message: 'A whole number of days. 0 keeps everything.',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        isValid: (t) => int.tryParse(t.trim()) != null,
      ),
    );
    final days = int.tryParse((text ?? '').trim());
    if (days == null || !mounted) return;
    final why = await ref.read(dashboardProvider.notifier).setRetention(days);
    if (!mounted) return;
    _say(why != null
        ? 'Not saved: $why'
        : (days == 0 ? 'History kept forever' : 'History kept $days days'));
  }

  Future<void> _clearHistory() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear detection history?'),
        content: const Text('Every detection the dashboard has stored, from every node, is deleted. '
            'Devices, names, groups and drones stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONTINUE')),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete it all?'),
        content: const Text('This cannot be undone. Every open dashboard drops them too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE HISTORY'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;
    final r = await ref.read(dashboardProvider.notifier).clearHistory();
    if (mounted) _say(r.error != null ? 'Not cleared: ${r.error}' : 'Cleared ${r.cleared} detections');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(dashboardProvider);
    final c = ref.read(dashboardProvider.notifier);
    final t = AppTheme.of(context);
    if (!_hostLoaded && s.settings.host.isNotEmpty) {
      _hostLoaded = true;
      _host.text = s.settings.host;
    }
    final sum = s.summary;
    final linkColor = switch (s.link) {
      DashboardLink.live => AppTheme.accent,
      DashboardLink.homeDown || DashboardLink.connecting || DashboardLink.waiting => AppTheme.warning,
      DashboardLink.refused || DashboardLink.notConnected => AppTheme.error,
      DashboardLink.off => t.textDim,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConfigToggleRow(
          icon: Icons.dns_outlined,
          label: 'Home dashboard',
          subtitle: 'The web dashboard on your computer (tools/home-dashboard)',
          color: AppTheme.accent,
          value: s.settings.enabled,
          notify: false,
          onChanged: c.setEnabled,
        ),
        if (s.settings.enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Address', helperText: 'Port 5077 unless you add one'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.check), tooltip: 'Save address', onPressed: _saveHost),
              ],
            ),
          ),
          ConfigToggleRow(
            icon: Icons.wifi_find,
            label: 'Find on this network',
            subtitle: 'Looks for a dashboard started with --lan --advertise. Uses multicast DNS on this network',
            color: AppTheme.warning,
            value: s.settings.discover,
            notify: false,
            onChanged: c.setDiscover,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _token,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Access token',
                      helperText: s.hasToken ? 'A token is saved. Enter a new one to replace it' : 'Only needed when the dashboard asks',
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.check), tooltip: 'Save token', onPressed: _saveToken),
              ],
            ),
          ),
          ConfigInfoRow(icon: Icons.link, label: 'Link', value: s.link.label, color: linkColor),
          if (s.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(s.error, style: TextStyle(color: t.textDim, fontSize: 13)),
            ),
          if (sum != null) ...[
            ConfigInfoRow(
              icon: Icons.usb,
              label: 'Board on USB',
              value: sum.boardConnected ? 'Connected' : 'None',
              color: sum.boardConnected ? AppTheme.accent : t.textDim,
            ),
            ConfigInfoRow(
              icon: Icons.hub_outlined,
              label: 'Nodes',
              value: '${sum.nodesOnline} of ${sum.nodesTotal} online',
            ),
            const SizedBox(height: 16),
            const ConfigSectionHeader(label: 'Connectors', info: [
              "Hosts, certificates and passwords are set on the dashboard's Settings tab.",
              'This page turns each connector on or off; Meshtastic has its own settings above.',
            ]),
            for (final k in DashboardConnector.values)
              ConfigToggleRow(
                icon: switch (k) {
                  DashboardConnector.mqtt => Icons.sensors,
                  DashboardConnector.tak => Icons.map_outlined,
                  DashboardConnector.rns => Icons.cell_tower,
                  DashboardConnector.meshtastic => Icons.settings_input_antenna,
                },
                label: k.title,
                subtitle: '${k.subtitle}. ${connectorStatus(k, sum.connectors[k] ?? const ConnectorInfo())}',
                color: AppTheme.accent,
                value: sum.connectors[k]?.enabled ?? false,
                notify: false,
                onChanged: (v) => _toggle(k, v),
              ),
            ConfigActionRow(
              icon: Icons.tune,
              label: 'Meshtastic settings',
              subtitle: 'Radio port, channel, events, test and inbox',
              onTap: () => showMeshtasticDashboardSheet(context),
            ),
            const SizedBox(height: 8),
            const ConfigSectionHeader(label: 'Dashboard data'),
            ConfigActionRow(
              icon: Icons.history,
              label: 'History kept',
              subtitle: sum.retentionDays == 0 ? 'Forever' : '${sum.retentionDays} days',
              onTap: () => _editRetention(sum.retentionDays),
            ),
            ConfigActionRow(
              icon: Icons.delete_outline,
              label: 'Clear detection history',
              subtitle: 'On the dashboard, for every node',
              destructive: true,
              onTap: _clearHistory,
            ),
          ],
        ],
      ],
    );
  }
}
