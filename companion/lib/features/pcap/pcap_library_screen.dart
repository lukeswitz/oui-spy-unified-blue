import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/app_time.dart';
import 'package:oui_spy/theme/app_theme.dart';

class PcapLibraryScreen extends ConsumerStatefulWidget {
  const PcapLibraryScreen({super.key});

  @override
  ConsumerState<PcapLibraryScreen> createState() => _PcapLibraryScreenState();
}

class _PcapLibraryScreenState extends ConsumerState<PcapLibraryScreen> {
  late Future<List<_PcapEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = _load();
  }

  Future<Directory> _pcapDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/pcaps');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<_PcapEntry>> _load() async {
    final d = await _pcapDir();
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith('.pcap'))
        .cast<File>()
        .toList();
    final out = <_PcapEntry>[];
    for (final f in files) {
      final st = await f.stat();
      out.add(_PcapEntry(file: f, size: st.size, modified: st.modified));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  void _refresh() {
    setState(() => _entries = _load());
  }

  Future<void> _share(File f) async {
    if (!await f.exists()) return;
    final size = await f.length();
    if (!mounted) return;
    final s = MediaQuery.of(context).size;
    final origin = Rect.fromLTWH(s.width / 2 - 1, s.height / 2 - 1, 2, 2);
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/vnd.tcpdump.pcap')],
      subject: 'OUI-SPY PCAP ($size bytes)',
      sharePositionOrigin: origin,
    );
  }

  bool _isActiveCapture(File f) {
    final ble = ref.read(bleManagerProvider);
    final active = ble.currentPcapFile;
    if (active == null) return false;
    return active.path == f.path;
  }

  Future<bool> _tryDelete(File f) async {
    if (_isActiveCapture(f)) {
      await ref.read(bleManagerProvider).abortActivePcap();
    }
    try {
      if (await f.exists()) await f.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _confirmDelete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete capture?'),
        content: Text(f.path.split('/').last),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success = await _tryDelete(f);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete failed')),
      );
    }
    _refresh();
  }

  Future<void> _confirmDeleteAll() async {
    final list = await _entries;
    if (list.isEmpty) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all captures?'),
        content: Text('${list.length} file(s) will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    int failed = 0;
    for (final e in list) {
      final ok = await _tryDelete(e.file);
      if (!ok) failed++;
    }
    if (!mounted) return;
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failed file(s) could not be deleted')),
      );
    }
    _refresh();
  }

  String _humanBytes(int n) {
    if (n < 1024) return '${n}B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
    if (n < 1024 * 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(2)}MB';
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        title: const Text('SAVED PCAPS'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: AppTheme.error),
            tooltip: 'Delete all',
            onPressed: _confirmDeleteAll,
          ),
        ],
      ),
      body: Container(
        color: t.background,
        child: FutureBuilder<List<_PcapEntry>>(
          future: _entries,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return Center(
                child: Text('No captures yet',
                    style: TextStyle(color: t.textDim, fontSize: 13)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: t.surface),
              itemBuilder: (context, i) {
                final e = list[i];
                final name = e.file.path.split('/').last;
                final isBle = name.contains('_ble_');
                final active = _isActiveCapture(e.file);
                return ListTile(
                  leading: Icon(
                    isBle ? Icons.bluetooth : Icons.wifi,
                    color: isBle ? const Color(0xFFB44AFF) : const Color(0xFF4AB4FF),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                      ),
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                                color: AppTheme.success,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${_humanBytes(e.size)}  ·  ${AppTime.dateTimeSeconds(e.modified)}',
                    style: TextStyle(color: t.textDim, fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.ios_share, size: 18, color: t.textPrimary),
                        onPressed: () => _share(e.file),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                        onPressed: () => _confirmDelete(e.file),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PcapEntry {
  _PcapEntry({required this.file, required this.size, required this.modified});
  final File file;
  final int size;
  final DateTime modified;
}
