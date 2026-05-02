import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/theme/app_theme.dart';

class DetectorScreen extends ConsumerStatefulWidget {
  const DetectorScreen({super.key});

  @override
  ConsumerState<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends ConsumerState<DetectorScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final watchlist = ref.watch(watchlistProvider);
    final detections = state.detectionsForEngine(Engine.detector);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('DETECTOR'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddDialog, tooltip: 'Add target'),
        ],
      ),
      body: Column(
        children: [
          // Watchlist section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('WATCHLIST', style: TextStyle(
                  color: AppTheme.detector, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2,
                )),
                const SizedBox(height: 8),
                if (watchlist.entries.isEmpty)
                  const Text('No targets. Tap + to add.', style: TextStyle(color: AppTheme.textDim, fontSize: 12))
                else
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: watchlist.entries.map((e) => _WatchlistChip(
                      entry: e,
                      onDelete: () => ref.read(watchlistProvider).remove(e),
                    )).toList(),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Detections
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('DETECTIONS', style: TextStyle(
                  color: AppTheme.textDim, fontSize: 10, letterSpacing: 2,
                )),
                const Spacer(),
                Text('${detections.length}', style: const TextStyle(
                  color: AppTheme.detector, fontSize: 11, fontFamily: 'monospace',
                )),
              ],
            ),
          ),
          Expanded(
            child: detections.isEmpty
                ? const Center(child: Text('No detections yet',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 12)))
                : ListView.builder(
                    itemCount: detections.length,
                    itemBuilder: (context, index) {
                      final d = detections[index];
                      return _DetectionTile(detection: d);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    final idController = TextEditingController();
    final descController = TextEditingController();
    bool isFullMAC = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Add Target', style: TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: isFullMAC ? 'AA:BB:CC:DD:EE:FF' : 'AA:BB:CC',
                  labelText: isFullMAC ? 'Full MAC address' : 'OUI prefix (first 3 bytes)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'e.g. Flock Safety, My tracker',
                  labelText: 'Description',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Match full MAC address', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const Spacer(),
                  Switch(value: isFullMAC, onChanged: (v) => setDialogState(() => isFullMAC = v)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                final id = idController.text.trim();
                if (id.isEmpty) return;
                ref.read(watchlistProvider).add(WatchlistEntry(
                  identifier: id,
                  isFullMac: isFullMAC,
                  description: descController.text.trim(),
                ));
                Navigator.pop(ctx);
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistChip extends StatelessWidget {
  const _WatchlistChip({required this.entry, required this.onDelete});
  final WatchlistEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.detector.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.detector.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(entry.isFullMac ? Icons.fingerprint : Icons.radar,
              color: AppTheme.detector, size: 12),
          const SizedBox(width: 4),
          Text(
            entry.identifier.toUpperCase(),
            style: const TextStyle(color: AppTheme.detector, fontSize: 11, fontFamily: 'monospace'),
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(entry.description,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 9)),
          ],
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close, size: 12, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }
}

class _DetectionTile extends StatelessWidget {
  const _DetectionTile({required this.detection});
  final Detection detection;

  @override
  Widget build(BuildContext context) {
    final desc = detection.detector?.filterDescription ?? '';
    final isMAC = detection.detector?.isFullMac ?? false;
    final timeDiff = DateTime.now().difference(detection.appTimestamp);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(isMAC ? Icons.fingerprint : Icons.radar,
            color: AppTheme.detector, size: 18),
        title: Text(detection.macAddress.toUpperCase(),
            style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 13)),
        subtitle: Text(desc.isNotEmpty ? desc : (isMAC ? 'Full MAC match' : 'OUI prefix match'),
            style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${detection.rssi} dBm',
                style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'monospace', fontSize: 11)),
            Text('${timeDiff.inSeconds}s', style: const TextStyle(color: AppTheme.textDim, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}
