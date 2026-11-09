import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/signature_suggest.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

class UserSignaturesScreen extends ConsumerWidget {
  const UserSignaturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final sigs = ref.watch(userSignaturesProvider);
    final masked = ref.watch(privacyScreenProvider);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('My signatures'),
        actions: [
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
