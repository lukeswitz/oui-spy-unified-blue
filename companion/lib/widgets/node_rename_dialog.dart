// Copyright (c) 2026 Luke Switzer
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/features/config/widgets/config_widgets.dart';
import 'package:oui_spy/theme/app_theme.dart';

/// Sends a node-control command; null hides the identify, locate and reboot buttons.
typedef NodeControlSender = Future<bool> Function(Uint8List cmd);

Future<void> showNodeRenameDialog(BuildContext context, AppState appState, String nodeId,
    {bool allowForget = false, NodeControlSender? control, bool targeted = true}) async {
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
