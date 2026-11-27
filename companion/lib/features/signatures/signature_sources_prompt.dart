// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/signature_sets.dart';
import 'package:oui_spy/core/classify/user_signatures.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/prefs.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

const kSignatureSourcesSeenKey = 'signature_sources_seen_version';

Future<String?> signatureSourcesPromptVersion(WidgetRef ref) async {
  final String version;
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } on Exception catch (e) {
    DebugLog.log('SETS: app version unknown, sources prompt skipped: $e');
    return null;
  }
  final seen = ref.read(sharedPreferencesProvider).getString(kSignatureSourcesSeenKey);
  return seen == version ? null : version;
}

Future<void> showSignatureSourcesPrompt(BuildContext context, WidgetRef ref, String version) async {
  await ref.read(signatureSetsProvider).loaded;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const SignatureSourcesDialog(),
  );
  await ref.read(sharedPreferencesProvider).setString(kSignatureSourcesSeenKey, version);
}

class SignatureSourcesDialog extends ConsumerStatefulWidget {
  const SignatureSourcesDialog({super.key});

  @override
  ConsumerState<SignatureSourcesDialog> createState() => _SignatureSourcesDialogState();
}

class _SignatureSourcesDialogState extends ConsumerState<SignatureSourcesDialog> {
  final _want = <String, bool>{};
  bool _extWant = false;
  bool? _extBoard;
  bool _boardReady = false;
  StreamSubscription<NodeConnectionState>? _sub;

  @override
  void initState() {
    super.initState();
    for (final s in ref.read(signatureSetsProvider).sets) {
      _want[s.id] = s.enabled;
    }
    final ble = ref.read(bleManagerProvider);
    _sub = ble.connectionState.listen(_onConnection);
    _onConnection(ble.currentConnectionState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onConnection(NodeConnectionState s) async {
    final ready = s == NodeConnectionState.ready;
    if (ready == _boardReady) return;
    setState(() {
      _boardReady = ready;
      _extBoard = null;
    });
    if (!ready) return;
    try {
      final on = await ref.read(bleManagerProvider).readFlockExtendedOui();
      if (!mounted) return;
      setState(() {
        _extBoard = on;
        _extWant = on ?? false;
      });
    } on Exception catch (e) {
      DebugLog.log('SETS: board extended OUI read failed: $e');
    }
  }

  Future<void> _save() async {
    final sets = ref.read(signatureSetsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ble = ref.read(bleManagerProvider);
    final extChange = _boardReady && _extBoard != null && _extWant != _extBoard;
    Navigator.of(context).pop();
    for (final s in sets.sets) {
      final want = _want[s.id];
      if (want != null && want != s.enabled) unawaited(sets.setEnabled(s.id, want));
    }
    if (!extChange) return;
    try {
      if (!await ble.setFlockExtendedOui(_extWant)) {
        messenger.showSnackBar(const SnackBar(content: Text('The board disconnected before the extended OUI set changed.')));
      }
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not change the extended OUI set: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final sets = ref.watch(signatureSetsProvider).sets;
    final mine = ref.watch(userSignaturesProvider).items.length;
    final dim = TextStyle(color: t.textDim, fontSize: 12);
    final extEnabled = _boardReady && _extBoard != null;
    final extNote = !_boardReady
        ? 'Needs a connected board.'
        : _extBoard == null
            ? 'This board does not have it.'
            : 'Saved on the board.';
    return AlertDialog(
      backgroundColor: t.surface,
      title: Text('Signature sources', style: TextStyle(color: t.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Pick what to match devices against. Change it later in Your Lists.',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('OUI-APEX catalog'),
              subtitle: Text('Always on', style: dim),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fingerprint),
              title: const Text('My signatures'),
              subtitle: Text('$mine saved, always on', style: dim),
            ),
            for (final s in sets)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(s.url == null ? Icons.description_outlined : Icons.cloud_download_outlined),
                title: Text(s.name),
                subtitle: Text(s.url == null ? 'Built in' : 'Downloads when on', style: dim),
                value: _want[s.id] ?? s.enabled,
                onChanged: (v) => setState(() => _want[s.id] = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.lan),
              title: const Text('Extended Flock OUI set'),
              subtitle: Text('More Flock hits, more false alarms. $extNote', style: dim),
              value: _extWant,
              onChanged: extEnabled ? (v) => setState(() => _extWant = v) : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
        TextButton(onPressed: _save, child: Text('Save', style: TextStyle(color: AppTheme.accent))),
      ],
    );
  }
}
