// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/notifications/alert_gate.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';

class DeviceMuteButton extends ConsumerWidget {
  const DeviceMuteButton({super.key, required this.mac, this.rowStyle = false});

  final String mac;
  final bool rowStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AlertGate.keyOf(mac).length != 17) return const SizedBox.shrink();
    final notif = ref.watch(notificationServiceProvider);
    final muted = notif.isDeviceMuted(mac);
    final label = muted ? 'Unmute alerts for this device' : 'Mute alerts for this device';
    final icon = muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined;
    void toggle() {
      notif.setDeviceMuted(mac, !muted);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(muted ? 'Alerts on for this device' : 'Muted. It is still logged, and a watched device still alerts'),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: rowStyle
          ? OutlinedButton(
              onPressed: toggle,
              child: Row(children: [Expanded(child: Text(label)), Icon(icon, size: 18)]),
            )
          : OutlinedButton.icon(icon: Icon(icon, size: 18), label: Text(label), onPressed: toggle),
    );
  }
}
