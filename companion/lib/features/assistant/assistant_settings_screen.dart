// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/assistant/assistant_auto.dart';
import 'package:oui_spy/core/assistant/assistant_chat.dart';
import 'package:oui_spy/core/assistant/assistant_grants.dart';
import 'package:oui_spy/core/assistant/assistant_llm.dart';
import 'package:oui_spy/core/assistant/assistant_settings.dart';
import 'package:oui_spy/core/assistant/assistant_tools.dart';
import 'package:oui_spy/features/assistant/assistant_screen.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

const assistantSendsDataWarning =
    'The assistant gives a language model what you allow below. A cloud service (Claude, ChatGPT, Gemini) '
    'sends it to the provider\'s servers, where it may be logged, kept or reviewed under their terms. '
    'For data that must stay on your own network, use a local model (Ollama).';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final t = AppTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: TextStyle(color: destructive ? AppTheme.error : t.textPrimary)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

IconData grantIcon(AssistantGrant g) => switch (g) {
      AssistantGrant.devices => Icons.radar,
      AssistantGrant.drones => Icons.flight,
      AssistantGrant.wardrive => Icons.drive_eta,
      AssistantGrant.mesh => Icons.hub,
      AssistantGrant.files => Icons.folder_open,
      AssistantGrant.loc => Icons.place,
      AssistantGrant.control => Icons.tune,
      AssistantGrant.danger => Icons.warning_amber,
    };

class AssistantGrantsSection extends ConsumerWidget {
  const AssistantGrantsSection({super.key});

  Future<void> _toggleOn(BuildContext context, WidgetRef ref, bool on) async {
    final notifier = ref.read(assistantAccessProvider.notifier);
    if (!on) return notifier.setOn(false);
    final ok = await confirmDialog(
      context,
      title: 'Switch the assistant on?',
      message: '$assistantSendsDataWarning\n\nNothing is granted until you switch it on below.',
      action: 'SWITCH ON',
    );
    if (ok) await notifier.setOn(true);
  }

  Future<void> _toggleGrant(BuildContext context, WidgetRef ref, AssistantGrant g, bool on) async {
    final notifier = ref.read(assistantAccessProvider.notifier);
    if (!on || !g.needsConfirmToEnable) return notifier.setGrant(g, on);
    final ok = await confirmDialog(
      context,
      title: 'Grant ${g.label}?',
      message: g.warning,
      action: 'GRANT',
      destructive: g == AssistantGrant.danger,
    );
    if (ok) await notifier.setGrant(g, true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final access = ref.watch(assistantAccessProvider);
    final grantedCount = access.granted.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ConfigSectionHeader(label: 'Assistant'),
        ConfigToggleRow(
          icon: Icons.smart_toy_outlined,
          label: 'Assistant',
          subtitle: access.on
              ? 'On: a model can read and act within the grants below.'
              : 'Off: nothing is shared and no model is contacted.',
          color: AppTheme.accent,
          value: access.on,
          onChanged: (v) => _toggleOn(context, ref, v),
        ),
        const SizedBox(height: 16),
        ConfigSectionHeader(label: 'Grants  ·  $grantedCount of ${AssistantGrant.values.length}'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'Each grant is off until you switch it on. Device health is always readable while the assistant is on. '
            'Every change that reaches the board still asks you first, one call at a time.',
            style: TextStyle(color: t.textDim, fontSize: 13),
          ),
        ),
        for (final g in AssistantGrant.values)
          ConfigToggleRow(
            icon: grantIcon(g),
            label: g.label,
            subtitle: g.summary,
            color: g == AssistantGrant.danger ? AppTheme.error : AppTheme.accent,
            value: access.granted.contains(g),
            onChanged: access.on ? (v) => _toggleGrant(context, ref, g, v) : null,
          ),
      ],
    );
  }
}

class AssistantToolsSection extends ConsumerWidget {
  const AssistantToolsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final access = ref.watch(assistantAccessProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ConfigSectionHeader(label: 'What it can use'),
        for (final tool in AssistantToolbox.all)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  AssistantToolbox.granted(tool, access) ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: AssistantToolbox.granted(tool, access) ? AppTheme.accent : t.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tool.title, style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                        switch (tool.risk) {
                              ToolRisk.read => 'Reads',
                              ToolRisk.local => 'Changes the app',
                              ToolRisk.board => 'Changes the board, asks you first',
                              ToolRisk.danger => 'Irreversible, asks you first',
                            } +
                            (tool.needs.isEmpty ? '' : '  ·  needs ${tool.needs.map((g) => g.label).join(', ')}'),
                        style: TextStyle(color: t.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class AssistantProviderSection extends ConsumerStatefulWidget {
  const AssistantProviderSection({super.key});

  @override
  ConsumerState<AssistantProviderSection> createState() => _AssistantProviderSectionState();
}

class _AssistantProviderSectionState extends ConsumerState<AssistantProviderSection> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _busy = false;
  bool _replacing = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(assistantSettingsProvider);
    _url.text = s.ollamaUrl;
    if (s.provider != null) _model.text = s.modelOf(s.provider!);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pick(LlmKind k) async {
    final s = ref.read(assistantSettingsProvider);
    final n = ref.read(assistantSettingsProvider.notifier);
    if (k.isCloud && !s.acked.contains(k)) {
      final ok = await confirmDialog(
        context,
        title: 'Use ${k.label}?',
        message: '${k.vendor}\'s cloud receives your questions and everything the model reads within the grants: '
            'device names and MACs, alerts, drone IDs and the rest you granted, and positions only with LOCATION. '
            'Ollama keeps all of it on your own network.',
        action: 'USE ${k.label.toUpperCase()}',
      );
      if (!ok) return;
      await n.acknowledge(k);
    }
    await n.setProvider(k);
    _model.text = ref.read(assistantSettingsProvider).modelOf(k);
    setState(() => _replacing = false);
    _key.clear();
  }

  Future<LlmProvider?> _checker(LlmKind k) {
    final s = ref.read(assistantSettingsProvider);
    return buildProviderForChecks(k, s.ollamaUrl, ref.read(assistantKeyStoreProvider), dio: ref.read(assistantDioProvider), model: s.modelOf(k));
  }

  Future<void> _check(LlmKind k) async {
    setState(() => _busy = true);
    try {
      final p = await _checker(k);
      if (p == null) {
        _toast(k == LlmKind.ollama ? 'Save the server address first.' : 'Save the API key first.');
        return;
      }
      _toast(await p.check());
    } on LlmError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickModel(LlmKind k) async {
    setState(() => _busy = true);
    List<String> names;
    try {
      final p = await _checker(k);
      if (p == null) {
        _toast(k == LlmKind.ollama ? 'Save the server address first.' : 'Save the API key first.');
        return;
      }
      names = await p.models();
    } on LlmError catch (e) {
      _toast(e.message);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (names.isEmpty) {
      _toast('No models came back.');
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${k.label} models'),
        children: [for (final m in names) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, m), child: Text(m))],
      ),
    );
    if (picked == null) return;
    _model.text = picked;
    await ref.read(assistantSettingsProvider.notifier).setModel(k, picked);
  }

  Future<void> _saveKey(LlmKind k) async {
    await ref.read(assistantSettingsProvider.notifier).setKey(k, _key.text);
    _key.clear();
    if (mounted) setState(() => _replacing = false);
  }

  Future<void> _removeKey(LlmKind k) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove the ${k.label} key?',
      message: 'It is deleted from this phone. The assistant stops working until a key is set again.',
      action: 'REMOVE',
      destructive: true,
    );
    if (ok) await ref.read(assistantSettingsProvider.notifier).removeKey(k);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final s = ref.watch(assistantSettingsProvider);
    final k = s.provider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ConfigSectionHeader(label: 'Model provider'),
        for (final p in LlmKind.values)
          ConfigActionRow(
            icon: p.isCloud ? Icons.cloud_outlined : Icons.dns_outlined,
            label: p.label,
            subtitle: p.isCloud ? '${p.vendor}\'s cloud receives what the model reads' : 'On your network: nothing leaves it',
            color: p == k ? AppTheme.accent : t.textDim,
            onTap: () => _pick(p),
            trailing: Icon(p == k ? Icons.check_circle : Icons.circle_outlined, size: 22, color: p == k ? AppTheme.accent : t.textDim),
          ),
        if (k == LlmKind.ollama) ...[
          const SizedBox(height: 8),
          ConfigTextField(icon: Icons.dns_outlined, label: 'Ollama server, e.g. 192.0.2.10', controller: _url, keyboardType: TextInputType.url),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              'A computer on your network running Ollama. A bare address gets port 11434. The link is plain http unless you give https, '
              'so anything on that network can read it.',
              style: TextStyle(color: t.textDim, fontSize: 12),
            ),
          ),
          ConfigActionRow(
            icon: Icons.save_outlined,
            label: 'Save server',
            onTap: () async {
              await ref.read(assistantSettingsProvider.notifier).setOllamaUrl(_url.text);
              final saved = ref.read(assistantSettingsProvider).ollamaUrl;
              _url.text = saved;
              if (saved.isEmpty) _toast('That is not a usable address.');
            },
          ),
        ],
        if (k != null && k.isCloud) ...[
          const SizedBox(height: 8),
          if (s.hasKey.contains(k) && !_replacing) ...[
            ConfigInfoRow(icon: Icons.key, label: 'API key', value: 'in secure storage', monospace: false),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text('Kept in secure storage on this phone and sent only to ${k.vendor}.', style: TextStyle(color: t.textDim, fontSize: 12)),
            ),
            ConfigActionRow(icon: Icons.swap_horiz, label: 'Replace key', onTap: () => setState(() => _replacing = true)),
            ConfigActionRow(icon: Icons.delete_outline, label: 'Remove key', destructive: true, onTap: () => _removeKey(k)),
          ] else ...[
            ConfigTextField(icon: Icons.key, label: '${k.label} API key', controller: _key, obscure: true),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                'Kept in secure storage on this phone, never in settings, logs or exports. Sent only to ${k.vendor}.',
                style: TextStyle(color: t.textDim, fontSize: 12),
              ),
            ),
            ConfigActionRow(icon: Icons.save_outlined, label: 'Save key', onTap: () => _saveKey(k)),
          ],
        ],
        if (k != null) ...[
          const SizedBox(height: 8),
          ConfigTextField(icon: Icons.memory, label: 'Model name', controller: _model),
          ConfigActionRow(
            icon: Icons.save_outlined,
            label: 'Save model',
            onTap: () => ref.read(assistantSettingsProvider.notifier).setModel(k, _model.text),
          ),
          ConfigActionRow(
            icon: Icons.list_alt,
            label: 'Pick from the provider\'s list',
            subtitle: 'Needs the ${k == LlmKind.ollama ? 'server address' : 'API key'} saved first',
            onTap: _busy ? null : () => _pickModel(k),
          ),
          ConfigActionRow(
            icon: Icons.network_check,
            label: _busy ? 'Checking...' : 'Check',
            subtitle: k == LlmKind.ollama ? 'That the server answers' : 'That the key works (no tokens spent)',
            onTap: _busy ? null : () => _check(k),
          ),
        ],
      ],
    );
  }
}

String autoSendsDataNote(AssistantSettings s, String what) {
  final k = s.provider;
  final where = k == null
      ? 'the model provider you set up'
      : (k.isCloud ? '${k.vendor}\'s cloud (${k.label})' : 'your Ollama server');
  final terms = k != null && k.isCloud ? ' There it may be logged, kept or reviewed under ${k.vendor}\'s terms.' : '';
  return 'While the app is running, $what goes to $where without a tap from you.$terms '
      'Positions are never included. You can switch it off here at any time.';
}

class AssistantAutoSection extends ConsumerWidget {
  const AssistantAutoSection({super.key});

  Future<void> _toggleIntel(BuildContext context, WidgetRef ref, bool on) async {
    final notifier = ref.read(assistantSettingsProvider.notifier);
    if (!on) return notifier.setAutoIntel(false);
    final ok = await confirmDialog(
      context,
      title: 'Look into alerts automatically?',
      message: autoSendsDataNote(
        ref.read(assistantSettingsProvider),
        'the name, MAC, maker and how it was heard of each newly alerted device',
      ),
      action: 'SWITCH ON',
    );
    if (ok) await notifier.setAutoIntel(true);
  }

  Future<void> _toggleReports(BuildContext context, WidgetRef ref, bool on) async {
    final notifier = ref.read(assistantSettingsProvider.notifier);
    if (!on) return notifier.setReportSchedule(every: ReportEvery.off);
    final ok = await confirmDialog(
      context,
      title: 'Write reports automatically?',
      message: autoSendsDataNote(
        ref.read(assistantSettingsProvider),
        'a summary of what the app saw since the last report, within your grants,',
      ),
      action: 'SWITCH ON',
    );
    if (ok) await notifier.setReportSchedule(every: ReportEvery.every);
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref, int minutes) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    if (picked == null) return;
    await ref.read(assistantSettingsProvider.notifier).setReportSchedule(dailyMinutes: picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final access = ref.watch(assistantAccessProvider);
    final s = ref.watch(assistantSettingsProvider);
    final notifier = ref.read(assistantSettingsProvider.notifier);
    final next = nextReportAt(s, DateTime.now());
    final reportsOn = s.reportEvery != ReportEvery.off;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ConfigSectionHeader(label: 'Automatic'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'Both are off until you switch them on. They send data to the model without a tap from you, only while the app is running, '
            'the assistant is on and a model provider is set up. Positions are never included.',
            style: TextStyle(color: t.textDim, fontSize: 13),
          ),
        ),
        ConfigToggleRow(
          icon: Icons.manage_search,
          label: 'Look into new alerts automatically',
          subtitle: 'Each new alert, by itself. At most one every 20 s and 40 a day. Skips a device that already has a note. Needs DEVICES.',
          color: AppTheme.accent,
          value: s.autoIntel,
          onChanged: access.on || s.autoIntel ? (v) => _toggleIntel(context, ref, v) : null,
        ),
        ConfigToggleRow(
          icon: Icons.schedule,
          label: 'Write a report automatically',
          subtitle: !reportsOn
              ? 'Off: no reports until you set when they come.'
              : 'Next: ${next == null ? '-' : AppTime.dateTimeShort(next)}, covering the time since the last one.',
          color: AppTheme.accent,
          value: reportsOn,
          onChanged: access.on || reportsOn ? (v) => _toggleReports(context, ref, v) : null,
        ),
        if (reportsOn) ...[
          const SizedBox(height: 8),
          Text('REPORTS COME', style: TextStyle(color: t.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          for (final mode in const [ReportEvery.every, ReportEvery.daily])
            ConfigActionRow(
              icon: mode == ReportEvery.every ? Icons.update : Icons.today,
              label: mode.label,
              subtitle: mode == ReportEvery.every ? 'A set number of hours apart' : 'Once a day, at a time you pick',
              color: s.reportEvery == mode ? AppTheme.accent : t.textDim,
              onTap: () => notifier.setReportSchedule(every: mode),
              trailing: Icon(
                s.reportEvery == mode ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: s.reportEvery == mode ? AppTheme.accent : t.textDim,
              ),
            ),
          if (s.reportEvery == ReportEvery.every)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final h in reportEveryHours)
                    ChoiceChip(
                      label: Text('$h h'),
                      selected: s.reportHours == h,
                      onSelected: (_) => notifier.setReportSchedule(hours: h),
                    ),
                ],
              ),
            )
          else
            ConfigActionRow(
              icon: Icons.access_time,
              label: 'At ${AppTime.time(DateTime(2000, 1, 1, s.reportDailyMinutes ~/ 60, s.reportDailyMinutes % 60))}',
              onTap: () => _pickTime(context, ref, s.reportDailyMinutes),
            ),
        ],
      ],
    );
  }
}

class AssistantOpenRow extends ConsumerWidget {
  const AssistantOpenRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(assistantAccessProvider).on;
    final ready = ref.watch(assistantSettingsProvider).ready;
    return ConfigActionRow(
      icon: Icons.chat_bubble_outline,
      label: 'Open the assistant',
      subtitle: !on
          ? 'Switch the assistant on first'
          : (ready ? 'Ask, intel and reports' : 'Set up a model provider first'),
      prominent: true,
      onTap: on && ready ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssistantScreen())) : null,
    );
  }
}

class AssistantSettingsBody extends StatelessWidget {
  const AssistantSettingsBody({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: const [
          AssistantOpenRow(),
          SizedBox(height: 16),
          AssistantGrantsSection(),
          SizedBox(height: 16),
          AssistantProviderSection(),
          SizedBox(height: 16),
          AssistantAutoSection(),
          SizedBox(height: 16),
          AssistantToolsSection(),
        ],
      );
}
