import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/watch_alert_log.dart';
import 'package:oui_spy/features/alerts/alerts_view.dart';
import 'package:oui_spy/features/config/config_menu_state.dart';
import 'package:oui_spy/features/config/device_config.dart' show DetectionHistoryView;
import 'package:oui_spy/features/devices/devices_screen.dart';
import 'package:oui_spy/features/feed/feed_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/d/d_tabs.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

enum DetectionsView { live, devices, history, alerts }

const _infoLines = [
  'Live: hits as they come in. Each network name gets one row, and its details list every MAC.',
  'Devices: each radio, sorted into sections by device class.',
  'History: every stored hit, with saved sessions and CSV export.',
  'Alerts: every alert, newest first.',
  'Funnel: filter by engine, radio, node or class.',
  'Arrow: choose the sort order. Time sort lists Wi-Fi first, then Bluetooth, newest first. Tap the arrow again to reverse it.',
  'Layers: indent each Wi-Fi client under the network it uses.',
  'Shapes (Devices): switch between class sections and one flat list.',
  'Clock (Live): open History. Antenna (History): back to Live. Folder (History): saved sessions.',
  'Three dots: more actions for the tab, such as search, export and clear.',
  'Wi-Fi or Bluetooth icon on a row: the radio that heard it.',
  'Crossed arrows: the device uses a random MAC.',
  'Crossed-out eye: the network hides its name.',
  'Lock: the network security, such as WPA2.',
  'Walking person: a loud Bluetooth device that keeps moving with you.',
];

final detectionsViewProvider = StateProvider<DetectionsView>((ref) => DetectionsView.live);

DetectionsView? viewForAlertKind(String kind) => switch (kind) {
      'foxhunt' => null,
      'detector' || 'flock' || 'drone' => DetectionsView.history,
      _ => DetectionsView.alerts,
    };

class DetectionsScreen extends ConsumerWidget {
  const DetectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final view = ref.watch(detectionsViewProvider);
    final liveCount = ref.watch(appStateProvider.select((s) => s.totalDetections));
    final deviceCount = ref.watch(deviceRegistryProvider.select((r) => r.count));
    final alertCount = ref.watch(alertsFeedProvider.select((f) => f.rows.length));
    ref.listen<String?>(historyFilterRequestProvider, (_, req) {
      if (req != null) ref.read(detectionsViewProvider.notifier).state = DetectionsView.history;
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
                        (DetectionsView.history, 'History'),
                        (DetectionsView.alerts, 'Alerts'),
                      ],
                      selected: view,
                      counts: {
                        DetectionsView.live: liveCount,
                        DetectionsView.devices: deviceCount,
                        if (alertCount > 0) DetectionsView.alerts: alertCount,
                      },
                      onSelect: (v) => ref.read(detectionsViewProvider.notifier).state = v,
                    ),
                  ),
                  IconButton(
                    tooltip: 'About tabs and icons',
                    icon: Icon(Icons.info_outline, color: t.textSecondary),
                    onPressed: () => showInfoSheet(context, t, 'Tabs and icons', _infoLines),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (view) {
                DetectionsView.history => DetectionHistoryView(
                    onShowLive: () => ref.read(detectionsViewProvider.notifier).state = DetectionsView.live,
                  ),
                DetectionsView.devices => const DevicesScreen(embedded: true),
                DetectionsView.alerts => const AlertsView(),
                DetectionsView.live => FeedScreen(
                    onShowHistory: () => ref.read(detectionsViewProvider.notifier).state = DetectionsView.history,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
