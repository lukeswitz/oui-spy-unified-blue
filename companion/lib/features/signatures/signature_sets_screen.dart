import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/core/classify/signature_sets.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:oui_spy/features/signatures/user_signatures_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

class SignatureSetsScreen extends ConsumerWidget {
  const SignatureSetsScreen({super.key});

  Future<void> _addLink(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => const _AddLinkDialog());
    if (result == null) return;
    try {
      await ref.read(signatureSetsProvider).addLink(result.$1, result.$2);
    } on SetError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addFile(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    const group = XTypeGroup(label: 'Signature set', extensions: ['json'], uniformTypeIdentifiers: ['public.json']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    try {
      if (await file.length() > SetParser.maxBytes) throw const SetError('The file is larger than 8 MB.');
      await ref.read(signatureSetsProvider).addFile(await file.readAsString(), file.name.replaceFirst(RegExp(r'\.json$'), ''));
    } on SetError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on FormatException {
      messenger.showSnackBar(const SnackBar(content: Text('The file is not UTF-8 text.')));
    }
  }

  void _add(BuildContext context, WidgetRef ref) => showCommandSheet<void>(
        context: context,
        builder: (ctx) => CommandSheet(
          title: 'ADD A SET',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommandSheetTile(
                icon: Icons.link,
                label: 'ADD A LINK',
                subtitle: 'An https:// link to a Fieldwatch signature file',
                onTap: () {
                  Navigator.pop(ctx);
                  _addLink(context, ref);
                },
              ),
              CommandSheetTile(
                icon: Icons.file_open_outlined,
                label: 'IMPORT A FILE',
                subtitle: 'A Fieldwatch signature file (.json) on this device',
                onTap: () {
                  Navigator.pop(ctx);
                  _addFile(context, ref);
                },
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final sets = ref.watch(signatureSetsProvider);
    final mine = ref.watch(userSignaturesProvider).items.length;
    final custom = sets.sets.where((s) => !s.preset).toList();
    Widget header(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(label, style: barLabelStyle(context, t.textDim).copyWith(letterSpacing: 2)),
        );
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Signature Sets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About signature sets',
            onPressed: () => showInfoSheet(context, t, 'Signature sets', const [
              'The built-in catalog is always on. Sets add more signatures to it.',
              'A set downloads only when you turn it on or tap Update.',
              'Entries the built-in catalog already has are skipped. Signatures from sets follow your class alert settings.',
              'Your own sets: an https:// link or a file in Fieldwatch signature format (JSON, up to 8 MB). Export My signatures to share them as a set.',
            ]),
          ),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add a set', onPressed: () => _add(context, ref)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            header('BUILT IN'),
            const ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('OUI-APEX catalog'),
              subtitle: Text('Always on'),
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('My signatures'),
              subtitle: Text('$mine saved'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserSignaturesScreen())),
            ),
            header('ONLINE SETS'),
            for (final s in sets.sets.where((s) => s.preset)) _SetTile(set: s, busy: sets.busy.contains(s.id)),
            header('YOUR SETS'),
            if (custom.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Add a link or a file with +.', style: TextStyle(color: t.textDim, fontSize: 12)),
              ),
            for (final s in custom) _SetTile(set: s, busy: sets.busy.contains(s.id)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SetTile extends ConsumerWidget {
  const _SetTile({required this.set, required this.busy});

  final SignatureSet set;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final s = set;
    final sets = ref.read(signatureSetsProvider);
    final status = busy
        ? 'Downloading'
        : s.error ??
            (s.updatedAt == null
                ? (s.enabled ? 'Not downloaded yet' : 'Off')
                : '${s.count == 0 ? 'Nothing beyond the built-in catalog' : 'Adds ${s.count} signature${s.count == 1 ? '' : 's'}'} · '
                    'updated ${AppTime.dateTime(DateTime.fromMillisecondsSinceEpoch(s.updatedAt!))}');
    return ListTile(
      leading: busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(s.url == null ? Icons.description_outlined : Icons.cloud_download_outlined, color: t.textSecondary),
      title: Text(s.name),
      subtitle: Text(
        [if (s.license.isNotEmpty) s.license, if (s.source.isNotEmpty) s.source, status].join(' · '),
        style: TextStyle(color: s.error != null && !busy ? AppTheme.error : t.textDim, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: s.enabled, onChanged: busy ? null : (v) => sets.setEnabled(s.id, v)),
          if (s.url != null || !s.preset)
            PopupMenuButton<String>(
              tooltip: 'More for ${s.name}',
              onSelected: (v) => v == 'update' ? sets.update(s.id) : sets.remove(s.id),
              itemBuilder: (_) => [
                if (s.url != null) PopupMenuItem(value: 'update', enabled: !busy, child: const Text('Update')),
                if (!s.preset) const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddLinkDialog extends StatefulWidget {
  const _AddLinkDialog();

  @override
  State<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<_AddLinkDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      title: Text('Add a link', style: TextStyle(color: t.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: TextStyle(color: t.textPrimary, fontFamily: AppTheme.mono, fontSize: 13),
            decoration: const InputDecoration(labelText: 'Link', hintText: 'https://example.com/signatures.json'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            style: TextStyle(color: t.textPrimary),
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, (_url.text, _name.text)),
          child: const Text('ADD'),
        ),
      ],
    );
  }
}
