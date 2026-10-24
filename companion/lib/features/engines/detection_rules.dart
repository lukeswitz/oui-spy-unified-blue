import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:oui_spy/core/detector_signatures.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

class WatchlistPanel extends ConsumerStatefulWidget {
  const WatchlistPanel({super.key});

  @override
  ConsumerState<WatchlistPanel> createState() => _WatchlistPanelState();
}

class _WatchlistPanelState extends ConsumerState<WatchlistPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final watchlist = ref.watch(watchlistProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'WATCHLIST',
                style: TextStyle(color: AppTheme.detector, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.add), tooltip: 'Add target', onPressed: _showEditDialog),
              IconButton(icon: const Icon(Icons.playlist_add), tooltip: 'Import list (JSON/CSV)', onPressed: _import),
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Export (JSON)',
                onPressed: watchlist.entries.isEmpty ? null : _export,
              ),
            ],
          ),
          if (watchlist.entries.isEmpty)
            Text('No targets. Add one or import a list.', style: TextStyle(color: t.textDim, fontSize: 12))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in watchlist.entries)
                  _WatchlistChip(
                    entry: e,
                    onTap: () => _showEditDialog(e),
                    onDelete: () => ref.read(watchlistProvider).remove(e),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(
      label: 'Watchlist',
      extensions: ['json', 'csv', 'txt'],
      uniformTypeIdentifiers: ['public.json', 'public.comma-separated-values-text', 'public.plain-text'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    try {
      if (await file.length() > 2 * 1024 * 1024) {
        messenger.showSnackBar(const SnackBar(content: Text('File too large (max 2 MB)')));
        return;
      }
      final wl = ref.read(watchlistProvider);
      final r = await wl.importText(await file.readAsString());
      final total = wl.enabledEntries.where((e) => !e.isName).length;
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Imported ${r.added}, skipped ${r.skipped} (invalid/duplicate)'
          '${total > 50 ? ' · device holds 50 MAC/OUI + 50 UUID targets' : ''}',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _export() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : const Rect.fromLTWH(0, 0, 100, 100);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/ouispy-watchlist.json');
    await f.writeAsString(ref.read(watchlistProvider).exportJson());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/json')],
      subject: 'OUI-SPY Watchlist',
      sharePositionOrigin: origin,
    ));
  }

  void _showEditDialog([WatchlistEntry? existing]) {
    final t = AppTheme.of(context);
    final idController = TextEditingController(text: existing?.identifier ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    var type = existing?.matchType ?? WatchlistMatchType.oui;
    var enabled = existing?.enabled ?? true;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: t.surface,
          title: Text(existing == null ? 'Add Target' : 'Edit Target', style: TextStyle(color: t.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<WatchlistMatchType>(
                segments: [
                  for (final m in WatchlistMatchType.values)
                    if (m != WatchlistMatchType.name)
                      ButtonSegment(value: m, label: Text(m.label, style: const TextStyle(fontSize: 11))),
                ],
                selected: {type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setDialogState(() {
                  type = s.first;
                  error = null;
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: idController,
                style: TextStyle(color: t.textPrimary, fontFamily: AppTheme.mono),
                decoration: InputDecoration(
                  hintText: switch (type) {
                    WatchlistMatchType.oui => 'AA:BB:CC',
                    WatchlistMatchType.fullMac => 'AA:BB:CC:DD:EE:FF',
                    WatchlistMatchType.serviceUuid => 'FD5F',
                    WatchlistMatchType.name => 'Device name',
                  },
                  labelText: switch (type) {
                    WatchlistMatchType.oui => 'OUI prefix (first 3 bytes)',
                    WatchlistMatchType.fullMac => 'Full MAC address',
                    WatchlistMatchType.serviceUuid => '16-bit BLE service UUID',
                    WatchlistMatchType.name => 'Name contains',
                  },
                  errorText: error,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                style: TextStyle(color: t.textPrimary),
                decoration: const InputDecoration(hintText: 'e.g. Flock Safety, My tracker', labelText: 'Description'),
              ),
              if (existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Enabled', style: TextStyle(color: t.textSecondary, fontSize: 12)),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                final parsed = parseWatchlistImport(
                  '${idController.text.trim()},${descController.text.trim()},${type.name}',
                );
                if (parsed.entries.isEmpty) {
                  setDialogState(() => error = 'Invalid ${type.label}');
                  return;
                }
                final wl = ref.read(watchlistProvider);
                final e = parsed.entries.first..enabled = enabled;
                if (wl.entries.any((x) => !identical(x, existing) && watchlistKey(x) == watchlistKey(e))) {
                  setDialogState(() => error = 'Already on watchlist');
                  return;
                }
                if (existing == null) {
                  wl.add(e);
                } else {
                  wl.update(existing, e);
                }
                Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'ADD' : 'SAVE'),
            ),
          ],
        ),
      ),
    ).then((_) {
      idController.dispose();
      descController.dispose();
    });
  }
}

class SignaturesPanel extends ConsumerWidget {
  const SignaturesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final sigMask = ref.watch(detectorSigMaskProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SIGNATURES',
            style: TextStyle(color: AppTheme.detector, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in detectorSignatures)
                Expanded(
                  child: Builder(builder: (context) {
                    final on = (sigMask & s.bit) != 0;
                    final c = on ? AppTheme.detector : t.textDim;
                    return Tooltip(
                      message: s.desc,
                      child: InkWell(
                        onTap: () => ref.read(detectorSigMaskProvider.notifier).setBit(s.bit, !on),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: on ? AppTheme.detector.withValues(alpha: 0.18) : t.background,
                                  border: Border.all(color: on ? AppTheme.detector.withValues(alpha: 0.5) : t.border),
                                ),
                                child: Icon(s.icon, size: 20, color: c),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.short,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 9, height: 1.1, color: c, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WatchlistChip extends StatelessWidget {
  const _WatchlistChip({required this.entry, required this.onTap, required this.onDelete});
  final WatchlistEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: entry.enabled ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.detector.withValues(alpha: 0.1),
            border: Border.all(color: AppTheme.detector.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.isFullMac ? Icons.fingerprint : Icons.radar, color: AppTheme.detector, size: 12),
              const SizedBox(width: 4),
              Text(
                entry.identifier.toUpperCase(),
                style: TextStyle(color: AppTheme.detector, fontSize: 11, fontFamily: AppTheme.mono),
              ),
              if (entry.description.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(entry.description, style: TextStyle(color: t.textDim, fontSize: 9)),
              ],
              const SizedBox(width: 4),
              GestureDetector(onTap: onDelete, child: Icon(Icons.close, size: 12, color: t.textDim)),
            ],
          ),
        ),
      ),
    );
  }
}
