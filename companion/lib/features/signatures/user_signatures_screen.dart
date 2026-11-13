import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/classify/signature_sets.dart';
import 'package:oui_spy/core/classify/signature_suggest.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

class UserSignaturesScreen extends ConsumerWidget {
  const UserSignaturesScreen({super.key});

  Future<void> _export(BuildContext context, List<Signature> items) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : const Rect.fromLTWH(0, 0, 100, 100);
    final f = File('${(await getTemporaryDirectory()).path}/oui-apex-signatures.json');
    await f.writeAsString(SetParser.exportPack(items));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)],
      subject: 'OUI-APEX signature set',
      sharePositionOrigin: origin,
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final sigs = ref.watch(userSignaturesProvider);
    final masked = ref.watch(privacyScreenProvider);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('My Signatures'),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export as a set',
              onPressed: sigs.items.isEmpty ? null : () => _export(context, sigs.items),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About my signatures',
            onPressed: () => showInfoSheet(context, t, 'My signatures', const [
              'Signatures you saved from suggested groups. The app checks every radio from the node and this phone against them.',
              'Alert on: a new match sends a notification and goes in the Alerts list. Alert off: matches are only labeled.',
              'They stay on this phone.',
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: sigs.items.isEmpty
            ? const CommandEmptyState(
                icon: Icons.fingerprint,
                title: 'No signatures yet',
                message: 'Save one from DEVICES → More → SUGGESTED SIGNATURES.',
              )
            : ListView.separated(
                itemCount: sigs.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = sigs.items[i];
                  return ListTile(
                    leading: Icon(Icons.fingerprint, color: t.textSecondary),
                    title: Text(s.name),
                    subtitle: Text(
                      [for (final r in s.rules) ruleSummary(r, masked: masked), s.kind.label].join(' · '),
                      style: TextStyle(color: t.textDim, fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: s.alert,
                          onChanged: (v) => sigs.setAlert(s.id, v),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove ${s.name}',
                          onPressed: () => sigs.remove(s.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
