// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/assistant/assistant_chat.dart';
import 'package:oui_spy/core/assistant/assistant_grants.dart';
import 'package:oui_spy/core/assistant/assistant_intel.dart';
import 'package:oui_spy/core/assistant/assistant_reports.dart';
import 'package:oui_spy/core/assistant/assistant_settings.dart';
import 'package:oui_spy/core/assistant/assistant_tools.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/device_notes.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  late final AssistantChat _chat;

  @override
  void initState() {
    super.initState();
    _chat = ref.read(assistantChatProvider);
    _chat.confirm = _confirm;
  }

  @override
  void dispose() {
    _chat.confirm = null;
    super.dispose();
  }

  Future<bool> _confirm(ToolRequest req) async {
    if (!mounted) return false;
    final danger = req.risk == ToolRisk.danger;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(danger ? 'Allow an irreversible change?' : 'Allow this change?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(req.summary),
            if (req.args.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(prettyArgs(req.args), style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('DENY')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ALLOW', style: TextStyle(color: danger ? AppTheme.error : null)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(assistantChatProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Assistant'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear the conversation',
              onPressed: chat.items.isEmpty ? null : chat.clear,
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'ASK'), Tab(text: 'INTEL'), Tab(text: 'REPORTS')]),
        ),
        body: const SafeArea(
          child: TabBarView(children: [_AskPane(), _IntelPane(), _ReportsPane()]),
        ),
      ),
    );
  }
}

String _scopeLine(AssistantAccess a, bool linked, LlmKind? k) {
  final n = a.granted.length;
  return '$n of ${AssistantGrant.values.length} granted  ·  positions ${a.has(AssistantGrant.loc) ? 'shared' : 'off'}  ·  ${linked ? 'board linked' : 'no board'}'
      '${k == null ? '' : '  ·  ${k.isCloud ? '${k.vendor} receives what it reads' : 'Ollama, on your network'}'}';
}

class _AskPane extends ConsumerStatefulWidget {
  const _AskPane();

  @override
  ConsumerState<_AskPane> createState() => _AskPaneState();
}

class _AskPaneState extends ConsumerState<_AskPane> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final v = _text.text;
    if (v.trim().isEmpty) return;
    _text.clear();
    ref.read(assistantChatProvider).ask(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final chat = ref.watch(assistantChatProvider);
    final access = ref.watch(assistantAccessProvider);
    final kind = ref.watch(assistantSettingsProvider).provider;
    final linked = chat.boardLinked();
    if (chat.items.length != _shown) {
      _shown = chat.items.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_scopeLine(access, linked, kind), style: TextStyle(color: t.textDim, fontSize: 12)),
          ),
        ),
        Expanded(
          child: chat.items.isEmpty
              ? const CommandEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Ask about anything seen',
                  message: 'A model answers from the app\'s data within what you granted: devices, alerts, drones, the wardriver, the mesh. '
                      'Every tool it runs shows here, and a change to the board waits for your OK.',
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: chat.items.length + (chat.busy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == chat.items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text('Working...', style: TextStyle(color: t.textDim)),
                        ]),
                      );
                    }
                    return _ItemView(chat.items[i]);
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Ask about anything the app has seen', border: InputBorder.none),
                ),
              ),
              if (chat.busy)
                IconButton(icon: const Icon(Icons.stop_circle_outlined), tooltip: 'Stop', onPressed: chat.stop)
              else
                IconButton(icon: const Icon(Icons.send), tooltip: 'Send', onPressed: _send),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemView extends StatelessWidget {
  const _ItemView(this.item);
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return switch (item) {
      AskItem(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOU', style: TextStyle(color: t.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 2),
            SelectableText(text, style: TextStyle(color: t.textPrimary, fontSize: 15)),
          ]),
        ),
      ReplyItem(:final text, :final model) => Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: t.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(model.isEmpty ? 'ASSISTANT' : model.toUpperCase(),
                style: TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 4),
            SelectableText(text, style: TextStyle(color: t.textPrimary, fontSize: 15)),
          ]),
        ),
      NoteItem(:final text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text, style: TextStyle(color: t.textDim, fontSize: 13)),
        ),
      final ToolItem tool => _ToolRow(tool),
    };
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow(this.tool);
  final ToolItem tool;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final status = tool.pending ? 'Running' : (tool.isError ? 'Error' : 'OK');
    final color = tool.pending ? t.textDim : (tool.isError ? AppTheme.error : AppTheme.accent);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: t.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(tool.title, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          trailing: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tool.args.isNotEmpty) ...[
              Text('ARGUMENTS', style: TextStyle(color: t.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
              SelectableText(prettyArgs(tool.args), style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12)),
              const SizedBox(height: 8),
            ],
            Text('RESULT', style: TextStyle(color: t.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
            SelectableText(tool.output ?? '(waiting)', style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _IntelPane extends ConsumerWidget {
  const _IntelPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final access = ref.watch(assistantAccessProvider);
    final intel = ref.watch(assistantIntelProvider);
    final masked = ref.watch(privacyScreenProvider);
    ref.watch(deviceNotesProvider);
    if (!access.has(AssistantGrant.devices)) {
      return const CommandEmptyState(
        icon: Icons.lock_outline,
        title: 'Intel needs DEVICES',
        message: 'Grant it in Settings > Data > Assistant. Until then the model is given none of it.',
      );
    }
    final reg = ref.watch(deviceRegistryProvider);
    final devices = reg.devices.toList()..sort((a, b) => b.obs.lastSeenMs.compareTo(a.obs.lastSeenMs));
    if (devices.isEmpty) {
      return const CommandEmptyState(
        icon: Icons.radar,
        title: 'Nothing seen yet',
        message: 'Devices show here as the app hears them.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'What the model makes of a device from all the app knows of it: maker, likely kind, why it may matter. Its name, MAC and how it was heard go to the model; never where it was.',
            style: TextStyle(color: t.textDim, fontSize: 12),
          ),
        ),
        for (final d in devices.take(50)) _IntelRow(device: d, intel: intel, masked: masked),
      ],
    );
  }
}

class _IntelRow extends ConsumerWidget {
  const _IntelRow({required this.device, required this.intel, required this.masked});
  final ClassifiedDevice device;
  final AssistantIntel intel;
  final bool masked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final mac = device.obs.mac.toUpperCase();
    final alias = DeviceNotesNotifier.nameFor(mac);
    final name = alias ?? (device.obs.name.isEmpty ? '(no name)' : device.obs.name);
    final note = intel.notes[mac];
    final working = intel.working.contains(mac);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(maskName(name, masked), style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          Text('${maskMac(mac, masked)}  ·  ${device.vendor ?? device.baseVendor ?? 'unknown maker'}', style: TextStyle(color: t.textDim, fontSize: 12)),
          if (note != null) ...[
            const SizedBox(height: 8),
            SelectableText(note.text, style: TextStyle(color: note.error ? AppTheme.error : t.textPrimary, fontSize: 14)),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: () => intel.lookInto(mac), child: Text(note == null ? 'LOOK INTO IT' : 'ASK AGAIN')),
          ),
        ],
      ),
    );
  }
}

class _ReportsPane extends ConsumerStatefulWidget {
  const _ReportsPane();

  @override
  ConsumerState<_ReportsPane> createState() => _ReportsPaneState();
}

class _ReportsPaneState extends ConsumerState<_ReportsPane> {
  int _hours = 24;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final reports = ref.watch(assistantReportsProvider);
    final fmt = DateFormat('MMM d, HH:mm');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text('REPORT ON THE LAST', style: TextStyle(color: t.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final h in reportHours) ChoiceChip(label: Text('$h h'), selected: _hours == h, onSelected: (_) => setState(() => _hours = h)),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed: reports.writing ? null : () => reports.writeNow(_hours),
            child: Text(reports.writing ? 'WRITING...' : 'WRITE ONE NOW'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sums up new devices, alerts, drones, the wardriver and the mesh within your grants. Positions are never included. Reports are written only when you ask.',
          style: TextStyle(color: t.textDim, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (reports.reports.isEmpty)
          Text('No reports yet.', style: TextStyle(color: t.textDim))
        else
          for (final r in reports.reports)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('${fmt.format(DateTime.fromMillisecondsSinceEpoch(r.atMs))}  ·  last ${r.hours} h${r.model.isEmpty ? '' : '  ·  ${r.model}'}',
                          style: TextStyle(color: t.textDim, fontSize: 12)),
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 20), tooltip: 'Delete', onPressed: () => reports.remove(r)),
                  ]),
                  SelectableText(r.text, style: TextStyle(color: r.error ? AppTheme.error : t.textPrimary, fontSize: 14)),
                ],
              ),
            ),
      ],
    );
  }
}
