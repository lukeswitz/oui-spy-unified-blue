// Copyright (c) 2026 Luke Switzer
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/node_positions.dart';
import 'package:oui_spy/core/mesh_node_info.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Sends a node-control command; null hides the identify, locate and reboot buttons.
typedef NodeControlSender = Future<bool> Function(Uint8List cmd);

const Duration kNodePlaceFixMaxAge = Duration(seconds: 60);

/// Pass [ref] to show the position controls that place the node for triangulation.
Future<void> showNodeRenameDialog(BuildContext context, AppState appState, String nodeId,
    {bool allowForget = false, NodeControlSender? control, bool targeted = true, WidgetRef? ref}) async {
  final id = AppState.canonicalNodeId(nodeId);
  if (id.isEmpty) return;
  final current = appState.nodeLabels[id] ?? '';
  final controller = TextEditingController(text: current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
  final target = targeted && id != 'LOCAL' ? id : null;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      Future<void> send(Uint8List cmd, String done) async {
        final ok = await control!(cmd);
        if (!ctx.mounted) return;
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(content: Text(ok ? done : 'Not connected to a board')),
        );
      }

      Future<void> placeHere() async {
        final pos = ref!.read(gpsProvider).recentPosition(kNodePlaceFixMaxAge);
        final messenger = ScaffoldMessenger.maybeOf(ctx);
        if (pos == null || !pos.latitude.isFinite || !pos.longitude.isFinite) {
          messenger?.showSnackBar(const SnackBar(
              content: Text('No recent GPS fix. Open the map, wait for a fix, then try again')));
          return;
        }
        await ref.read(nodePositionsProvider.notifier).place(id, LatLng(pos.latitude, pos.longitude));
        messenger?.showSnackBar(SnackBar(
            content: Text('${appState.labelForNode(id)} placed at your position (±${pos.accuracy.round()} m)')));
      }

      Future<void> confirmReboot() async {
        final yes = await showDialog<bool>(
          context: ctx,
          builder: (c2) => AlertDialog(
            title: Text('Reboot ${appState.labelForNode(id)}?'),
            content: const Text('It leaves the mesh for a few seconds, then rejoins.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('CANCEL')),
              TextButton(onPressed: () => Navigator.pop(c2, true), child: const Text('REBOOT')),
            ],
          ),
        );
        if (yes == true) await send(BleProtocol.encodeNodeReboot(target), 'Reboot sent');
      }

      return AlertDialog(
        scrollable: true,
        title: Text('Rename ${appState.labelForNode(id)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: control == null,
              maxLength: 32,
              decoration: InputDecoration(
                hintText: 'Custom label (blank = reset)',
                helperText: 'Node $id',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            if (ref != null && id != 'LOCAL')
              Consumer(builder: (c, r, _) {
                final at = r.watch(nodePositionsProvider)[id];
                final t = AppTheme.of(c);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      at == null
                          ? 'Position: not placed'
                          : 'Position: ${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}',
                      style: TextStyle(color: t.textDim, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ConfigCompactButton(
                      icon: Icons.add_location_alt_outlined,
                      label: 'Place at my position',
                      onTap: placeHere,
                    ),
                    if (at != null) ...[
                      const SizedBox(height: 8),
                      ConfigCompactButton(
                        icon: Icons.location_off_outlined,
                        label: 'Clear position',
                        onTap: () => r.read(nodePositionsProvider.notifier).clear(id),
                      ),
                    ],
                  ],
                );
              }),
            if (control != null && target != null)
              ListenableBuilder(
                listenable: appState,
                builder: (_, _) {
                  final d = appState.nodeDetail(id);
                  if (d == null) return const SizedBox.shrink();
                  final t = AppTheme.of(ctx);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(nodeDetailLines(d, d.ageS).join('\n'),
                        style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.4)),
                  );
                },
              ),
            if (control != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ConfigCompactButton(
                      icon: Icons.campaign_outlined,
                      label: 'Identify',
                      onTap: () => send(BleProtocol.encodeNodeIdentify(target),
                          'Identify sent: it beeps and blinks for 10 seconds'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ConfigCompactButton(
                      icon: Icons.volume_up_outlined,
                      label: 'Locate',
                      onTap: () => send(BleProtocol.encodeNodeLocate(target, on: true),
                          'Locate on: it beeps until you stop it, 30 minutes at most'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ConfigCompactButton(
                      icon: Icons.volume_off_outlined,
                      label: 'Stop locate',
                      onTap: () => send(BleProtocol.encodeNodeLocate(target, on: false), 'Locate off'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ConfigCompactButton(
                      icon: Icons.restart_alt,
                      label: 'Reboot',
                      destructive: true,
                      onTap: confirmReboot,
                    ),
                  ),
                ],
              ),
              if (target != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ConfigCompactButton(
                        icon: Icons.fact_check_outlined,
                        label: 'Read status',
                        onTap: () => send(BleProtocol.encodeNodeStatusRequest(target),
                            'Status requested: build, filters, uptime and peers appear here'),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ],
            ],
          ],
        ),
        actions: [
          if (allowForget && id != 'LOCAL' && id != appState.nodeId)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__forget__'),
              child: Text('FORGET', style: TextStyle(color: AppTheme.error)),
            ),
          if (appState.nodeLabels.containsKey(id))
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('CLEAR'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('SAVE'),
          ),
        ],
      );
    },
  );
  if (result == null) return;
  if (result == '__forget__') {
    appState.forgetNode(id);
    return;
  }
  appState.setNodeLabel(id, result.trim());
}
