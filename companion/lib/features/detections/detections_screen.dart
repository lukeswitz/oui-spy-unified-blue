// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/features/config/config_menu_state.dart';
import 'package:oui_spy/features/config/device_config.dart' show DetectionHistoryView;
import 'package:oui_spy/features/devices/devices_screen.dart';
import 'package:oui_spy/features/feed/feed_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_tabs.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

enum DetectionsView { live, devices, alerts }

const _infoLines = [
  'Live shows new hits, Devices each radio, Alerts every alert and every Flock, Detector, drone and SDR hit.',
  'Funnel filters, arrow sorts. Layers indents Wi-Fi clients under their network.',
  'Crossed arrows mark a random MAC. A walking person marks a device moving with you.',
  'Three dots: search, export and clear.',
];

final detectionsViewProvider = StateProvider<DetectionsView>((ref) => DetectionsView.live);

DetectionsView? viewForAlertKind(String kind) => kind == 'foxhunt' ? null : DetectionsView.alerts;

class DetectionsScreen extends ConsumerWidget {
  const DetectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final view = ref.watch(detectionsViewProvider);
    final liveCount = ref.watch(appStateProvider.select((s) => s.totalDetections));
    final deviceCount = ref.watch(deviceRegistryProvider.select((r) => r.count));
    final unread = ref.watch(alertsFeedProvider.select((f) => f.unread));
    ref.listen<String?>(historyFilterRequestProvider, (_, req) {
      if (req != null) ref.read(detectionsViewProvider.notifier).state = DetectionsView.alerts;
    });
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: DPageTitle('Detections')),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DUnderlineTabs<DetectionsView>(
                      items: const [
                        (DetectionsView.live, 'Live'),
                        (DetectionsView.devices, 'Devices'),
                        (DetectionsView.alerts, 'Alerts'),
                      ],
                      selected: view,
                      counts: {
                        DetectionsView.live: liveCount,
                        DetectionsView.devices: deviceCount,
                        if (unread > 0) DetectionsView.alerts: unread,
                      },
                      onSelect: (v) => ref.read(detectionsViewProvider.notifier).state = v,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Detections guide',
                    icon: Icon(Icons.info_outline, color: t.textSecondary),
                    onPressed: () => showInfoSheet(context, t, 'Detections guide', _infoLines),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (view) {
                DetectionsView.alerts => DetectionHistoryView(
                    onShowLive: () => ref.read(detectionsViewProvider.notifier).state = DetectionsView.live,
                  ),
                DetectionsView.devices => const DevicesScreen(embedded: true),
                DetectionsView.live => FeedScreen(
                    onShowHistory: () => ref.read(detectionsViewProvider.notifier).state = DetectionsView.alerts,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
