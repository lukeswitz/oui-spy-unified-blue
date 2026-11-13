import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/signature_suggest.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

Future<void> showSuggestionsSheet(BuildContext context) =>
    showCommandSheet<void>(context: context, builder: (_) => const SuggestionsSheet());

class SuggestionsSheet extends ConsumerStatefulWidget {
  const SuggestionsSheet({super.key});

  @override
  ConsumerState<SuggestionsSheet> createState() => _SuggestionsSheetState();
}

class _SuggestionsSheetState extends ConsumerState<SuggestionsSheet> {
  late final List<Suggestion> _groups = SignatureSuggest.of(ref.read(deviceRegistryProvider).devices);

  Future<void> _save(Suggestion g) async {
    final sig = await showDialog<Signature>(
      context: context,
      builder: (_) => _SaveDialog(group: g, masked: ref.read(privacyScreenProvider)),
    );
    if (sig != null) await ref.read(userSignaturesProvider).add(sig);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final masked = ref.watch(privacyScreenProvider);
    final saved = ref.watch(userSignaturesProvider);
    final small = (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(color: t.textDim);
    return CommandSheet(
      title: 'SUGGESTED SIGNATURES',
      trailing: IconButton(
        icon: Icon(Icons.info_outline, size: barIconSize(context), color: t.textDim),
        tooltip: 'About suggested signatures',
        visualDensity: VisualDensity.compact,
        onPressed: () => showInfoSheet(context, t, 'Suggested signatures', const [
          'Groups of 3 or more unclassified radios that share a name, a Bluetooth service, a vendor prefix or a Bluetooth company ID.',
          'SAVE makes the group a signature of your own. The app then classifies every matching radio it hears, from the node and this phone.',
          'With alerts on, a new match sends a notification and goes in the Alerts list.',
          'Edit or remove them in Settings → Detection & Alerts → Your Lists → My signatures.',
        ]),
      ),
      child: _groups.isEmpty
          ? Text(
              'No group of 3 or more unclassified radios shares a name, service, vendor prefix or company yet.',
              style: small,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in _groups)
                  _GroupTile(
                    group: g,
                    masked: masked,
                    saved: saved.hasRule(g.matchRule),
                    onSave: () => _save(g),
                  ),
              ],
            ),
    );
  }
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({required this.group, required this.masked});

  final Suggestion group;
  final bool masked;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late final _name = TextEditingController(text: widget.group.defaultName);
  var _kind = SignatureClass.other;
  var _alert = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final g = widget.group;
    return AlertDialog(
      backgroundColor: t.surface,
      title: Text('Save signature', style: TextStyle(color: t.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ruleSummary(g.matchRule, masked: widget.masked),
                style: TextStyle(color: t.textDim, fontFamily: AppTheme.mono, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              style: TextStyle(color: t.textPrimary),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SignatureClass>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Class'),
              items: [for (final c in alertableClasses) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (c) => setState(() => _kind = c ?? _kind),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Alert on new matches', style: TextStyle(color: t.textSecondary, fontSize: 13)),
              value: _alert,
              onChanged: (v) => setState(() => _alert = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () {
            final n = _name.text.trim();
            Navigator.pop(context, g.toSignature(name: n.isEmpty ? g.defaultName : n, kind: _kind, alert: _alert));
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.masked, required this.saved, required this.onSave});

  final Suggestion group;
  final bool masked;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final gap = barGap(context);
    final small = (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(color: t.textDim);
    final names = {for (final d in group.devices) if (d.obs.name.trim().isNotEmpty) maskName(d.obs.name.trim(), masked)};
    final examples = (names.isNotEmpty
            ? names
            : {for (final d in group.devices) if (d.obs.mac.isNotEmpty) maskMac(d.obs.mac, masked)})
        .take(3)
        .join(', ');
    return Padding(
      padding: EdgeInsets.only(bottom: gap * 1.5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${group.devices.length} radios · ${group.label(masked: masked)}',
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
                ),
                if (examples.isNotEmpty) Text('e.g. $examples', style: small),
                if (group.also.isNotEmpty)
                  Text('Also share: ${group.also.map((a) => a.label(masked: masked)).join(' · ')}', style: small),
              ],
            ),
          ),
          saved
              ? Text('SAVED', style: barLabelStyle(context, t.textDim))
              : TextButton(onPressed: onSave, child: const Text('SAVE')),
        ],
      ),
    );
  }
}
