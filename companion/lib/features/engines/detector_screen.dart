import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/detector_signatures.dart';
import 'package:oui_spy/core/watchlist_state.dart';
import 'package:oui_spy/features/feed/detection_row.dart';
import 'package:oui_spy/core/engine_control.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/config/config_menu_state.dart';
import 'package:oui_spy/features/detections/detections_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/info_sheet.dart';

class DetectorScreen extends ConsumerWidget {
  const DetectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final detections = state.detectionsForEngine(Engine.detector);
    final sigMask = ref.watch(detectorSigMaskProvider);
    final targets = ref.watch(watchlistProvider).entries.length;
    final watching = [
      for (final s in detectorSignatures)
        if (sigMask & s.bit != 0) s.short.replaceAll('-\n', ''),
      if (targets > 0) '$targets watchlist target${targets == 1 ? '' : 's'}',
    ];

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Detector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showInfoSheet(context, t, 'Detector', const [
              'Watches for the devices and threats you turn on, all off by default.',
              'Add a MAC, OUI prefix, name, or 16-bit BLE service UUID to your watchlist.',
              'Built-in signatures: Find My / AirTag following you, Flipper Zero, Wi-Fi deauth floods, directed probes, Pwnagotchi, smart glasses, law-enforcement gear, cameras by vendor OUI, Amazon Sidewalk.',
              'Hits save to History.',
            ]),
          ),
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: state.isEngineActive(Engine.detector),
              onChanged: (on) => setEngineEnabled(ref, Engine.detector, on),
              activeTrackColor: AppTheme.detector.withValues(alpha: 0.3),
              activeThumbColor: AppTheme.detector,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear detections',
            onPressed: () => ref.read(appStateProvider).clearDetectionsForEngine(Engine.detector),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.track_changes, color: AppTheme.detector),
            title: Text('Watching for',
                style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: Text(
              watching.isEmpty ? 'Nothing selected · tap to choose' : watching.join(', '),
              style: TextStyle(color: t.textDim, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: t.textDim),
            onTap: () {
              ref.read(configSectionRequestProvider.notifier).state = 'DETECTION';
              context.go('/config');
            },
          ),
          const Divider(height: 1),
          if (detections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Text(
                state.isEngineActive(Engine.detector)
                    ? 'No hits yet. Hits show up here as the board finds them.'
                    : 'Turn the detector on to start watching.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textDim, fontSize: 13),
              ),
            )
          else
            for (final d in detections.take(50)) DetectionRow(detection: d),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.history, color: AppTheme.detector),
            title: Text('History',
                style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${detections.length} this session · filters, map, export',
              style: TextStyle(color: t.textDim, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: t.textDim),
            onTap: () {
              ref.read(historyFilterRequestProvider.notifier).state = 'detector';
              ref.read(detectionsViewProvider.notifier).state = DetectionsView.history;
              context.go('/detections');
            },
          ),
        ],
      ),
    );
  }
}
