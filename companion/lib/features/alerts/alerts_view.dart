import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:oui_spy/core/classify/class_style.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/privacy.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/oui/oui_lookup_service.dart';
import 'package:oui_spy/features/feed/detection_row.dart'
    show detectionHasBoard, detectionScanner, detectionZoomOnMap, showDetectionDetails;
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/command_bar.dart';

const _notRadio = {'cell_watch', 'gps_watch', 'beacon_flood', 'aircraft_circle', 'car_follow', 'drone_loiter'};

String _ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String _maskedTitle(Map<String, dynamic> r, bool masked) {
  final title = r['deviceName'] as String? ?? '';
  final name = r['ssid'] as String? ?? '';
  return masked && name.isNotEmpty ? title.replaceAll(name, maskName(name, true)) : title;
}

class AlertsView extends ConsumerWidget {
  const AlertsView({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all alerts?'),
        content: const Text('Detections stay in HISTORY.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CLEAR')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).clearClassAlerts();
    await ref.read(alertsFeedProvider).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(alertsFeedProvider);
    final masked = ref.watch(privacyScreenProvider);
    final rows = feed.rows;
    return Column(
      children: [
        CommandHeader(
          title: 'ALERTS',
          count: '${rows.length}',
          actions: [
            CommandBarAction(
              icon: Icons.delete_sweep,
              label: 'Clear',
              onTap: rows.isEmpty ? null : () => _clear(context, ref),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: feed.loading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const CommandEmptyState(
                      icon: Icons.notifications_none,
                      title: 'No alerts yet',
                      message: 'Every alert OUI-APEX raises shows here, newest first.',
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _AlertRow(row: rows[i], masked: masked),
                    ),
        ),
      ],
    );
  }
}

class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.row, required this.masked});
  final Map<String, dynamic> row;
  final bool masked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final kind = row['alertClass'] as String?;
    final count = row['count'] as int? ?? 1;
    final reason = row['detectionMethod'] as String? ?? '';
    return ListTile(
      leading: Icon(alertKindIcon(kind), color: alertKindColor(kind)),
      title: Text(_maskedTitle(row, masked), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (reason.isNotEmpty) reason, _ago(row['appTimestamp'] as int), if (count > 1) '$count times'].join(' · '),
        style: TextStyle(color: t.textDim, fontSize: 12),
      ),
      trailing: Text(alertKindLabel(kind), style: TextStyle(color: alertKindColor(kind), fontSize: 10)),
      onTap: () => showAlertSheet(context, ref, row, masked),
    );
  }
}

Future<void> showAlertSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> row, bool masked) =>
    _showAlert(context, ref, row, masked);

Future<void> _showAlert(BuildContext context, WidgetRef ref, Map<String, dynamic> row, bool masked) async {
  final kind = row['alertClass'] as String? ?? '';
  final subject = row['macAddress'] as String? ?? '';
  final stored = await ref
      .read(databaseProvider)
      .latestDetectionMapForMac(subject, sessionId: row['sessionId'] as String? ?? '');
  if (!context.mounted) return;
  final t = AppTheme.of(context);
  final device = stored == null ? null : detectionFromDbRow(stored);
  final lat = row['latitude'] as double? ?? device?.latitude;
  final lon = row['longitude'] as double? ?? device?.longitude;
  final at = DateTime.fromMillisecondsSinceEpoch(row['appTimestamp'] as int);
  final firstMs = row['firstAlertedAt'] as int?;
  final radio = stored != null || (!_notRadio.contains(kind) && subject.isNotEmpty);
  final sessionId = row['sessionId'] as String? ?? '';
  final session = sessionId.isEmpty ? null : await ref.read(databaseProvider).getSessionById(sessionId);
  if (!context.mounted) return;
  final vendor = radio && subject.isNotEmpty ? ref.read(ouiLookupProvider).lookup(subject) : null;
  final boardId = device == null
      ? ''
      : device.sourceNodeId.isNotEmpty
          ? device.sourceNodeId
          : detectionHasBoard(device)
              ? device.nodeId
              : '';
  final boardLabel = boardId.isEmpty ? '' : ref.read(appStateProvider).labelForNode(boardId);
  final rssi = device?.rssi ?? row['rssi'] as int? ?? 0;
  final channel = device?.channel ?? row['channel'] as int? ?? 0;
  final fmt = DateFormat('MMM d, HH:mm:ss');
  Widget line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 84, child: Text(label, style: TextStyle(color: t.textDim, fontSize: 12))),
            Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(alertKindIcon(kind), color: alertKindColor(kind)),
                const SizedBox(width: 10),
                Expanded(child: Text(_maskedTitle(row, masked), style: const TextStyle(fontSize: 16))),
              ],
            ),
            const SizedBox(height: 14),
            line('Type', alertKindLabel(kind)),
            if ((row['detectionMethod'] as String? ?? '').isNotEmpty) line('Why', row['detectionMethod'] as String),
            line('Last', fmt.format(at)),
            if (firstMs != null && firstMs != row['appTimestamp']) line('First', fmt.format(DateTime.fromMillisecondsSinceEpoch(firstMs))),
            if ((row['count'] as int? ?? 1) > 1) line('Times', '${row['count']}'),
            if (subject.isNotEmpty) line(radio ? 'Address' : 'Subject', radio ? maskMac(subject, masked) : subject),
            if (vendor != null && vendor.isNotEmpty) line('Vendor', vendor),
            if (device != null && device.deviceName.isNotEmpty) line('Name', maskName(device.deviceName, masked)),
            if (device != null && device.ssid.isNotEmpty && device.ssid != device.deviceName) line('SSID', maskName(device.ssid, masked)),
            if (device != null) line('Engine', detectionScanner(device)),
            if (boardId.isNotEmpty) line('Source', '$boardLabel  ($boardId)'),
            if (radio && rssi != 0) line('RSSI', '$rssi dBm'),
            if (radio && channel > 0) line('Channel', '$channel'),
            if (device != null && device.count > 1) line('Hits', '${device.count}'),
            if (lat != null && lon != null) line('Location', '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'),
            if (session != null) line('Session', fmt.format(DateTime.fromMillisecondsSinceEpoch(session.startedAt))),
            const SizedBox(height: 10),
            if (lat != null && lon != null)
              FilledButton.icon(
                key: const Key('alert-map'),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Map'),
                onPressed: () {
                  Navigator.pop(ctx);
                  final base = device ?? detectionFromDbRow(row);
                  detectionZoomOnMap(context, ref,
                      base.copyWith(sessionId: sessionId.isNotEmpty ? sessionId : base.sessionId, latitude: lat, longitude: lon));
                },
              ),
            if (lat != null && lon != null) const SizedBox(height: 8),
            if (radio)
              OutlinedButton.icon(
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Device details'),
                onPressed: () {
                  Navigator.pop(ctx);
                  showDetectionDetails(context, ref, device ?? detectionFromDbRow(row));
                },
              ),
            TextButton.icon(
              icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
              label: Text('Delete', style: TextStyle(color: AppTheme.error)),
              onPressed: () async {
                Navigator.pop(ctx);
                await ref.read(databaseProvider).deleteClassAlerts(subject, kind);
                await ref.read(alertsFeedProvider).reload();
              },
            ),
          ],
        ),
        ),
      ),
    ),
  );
}
