// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/assistant/assistant_grants.dart';
import 'package:oui_spy/core/assistant/assistant_tools.dart';
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

class AssistantSettingsBody extends StatelessWidget {
  const AssistantSettingsBody({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: const [
          AssistantGrantsSection(),
          SizedBox(height: 16),
          AssistantToolsSection(),
        ],
      );
}
