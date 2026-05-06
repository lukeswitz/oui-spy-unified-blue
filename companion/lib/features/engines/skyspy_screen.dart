import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

class SkySpyScreen extends ConsumerWidget {
  const SkySpyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final isActive = state.isEngineActive(Engine.skySpy);
    final drones = <String, Detection>{};
    for (final d in state.recentDetections) {
      if (d.engine == Engine.skySpy) drones[d.macAddress] = d;
    }
    final droneList = drones.values.toList()
      ..sort((a, b) => b.appTimestamp.compareTo(a.appTimestamp));

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('SKY SPY'),
        actions: [
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: isActive,
              onChanged: (enable) {
                final ble = ref.read(bleManagerProvider);
                if (enable) {
                  ble.enableEngine(Engine.skySpy);
                } else {
                  ble.disableEngine(Engine.skySpy);
                }
              },
              activeTrackColor: AppTheme.skySpy.withValues(alpha: 0.3),
              activeColor: AppTheme.skySpy,
            ),
          ),
        ],
      ),
      body: droneList.isEmpty
          ? Center(child: Text(
              isActive ? 'SCANNING FOR DRONES...' : 'ENABLE TO START SCANNING',
              style: TextStyle(color: t.textDim, letterSpacing: 2, fontSize: 12)))
          : ListView.builder(
              itemCount: droneList.length,
              itemBuilder: (context, index) => _DroneRow(detection: droneList[index]),
            ),
    );
  }
}

class _DroneRow extends StatelessWidget {
  const _DroneRow({required this.detection});
  final Detection detection;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final odid = detection.odid;
    final timeDiff = DateTime.now().difference(detection.appTimestamp);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.skySpy.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight, color: AppTheme.skySpy, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                odid?.uavId ?? detection.macAddress.toUpperCase(),
                style: const TextStyle(color: AppTheme.skySpy, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
              )),
              Text('${detection.rssi} dBm',
                  style: TextStyle(color: t.textDim, fontSize: 11, fontFamily: 'monospace')),
              const SizedBox(width: 8),
              Text('${timeDiff.inSeconds}s ago',
                  style: TextStyle(color: t.textDim, fontSize: 10)),
            ],
          ),
          if (odid != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              _Chip('ALT', '${odid.altitudeMsl ?? 0}m'),
              _Chip('HGT', '${odid.heightAgl ?? 0}m'),
              _Chip('SPD', '${odid.droneSpeed ?? 0}m/s'),
              _Chip('HDG', '${odid.droneHeading ?? 0}°'),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (odid.droneLat != null && odid.droneLat != 0)
                _Chip('POS', '${odid.droneLat!.toStringAsFixed(4)}, ${odid.droneLon!.toStringAsFixed(4)}'),
              if (odid.operatorId != null && odid.operatorId!.isNotEmpty)
                _Chip('OP', odid.operatorId!),
            ]),
            if (odid.pilotLat != null && odid.pilotLat != 0) ...[
              const SizedBox(height: 4),
              _Chip('PILOT', '${odid.pilotLat!.toStringAsFixed(4)}, ${odid.pilotLon!.toStringAsFixed(4)}'),
            ],
          ],
          const SizedBox(height: 4),
          Text(detection.macAddress.toUpperCase(),
              style: TextStyle(color: t.textDim, fontSize: 10, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: TextStyle(color: t.textDim, fontSize: 9, letterSpacing: 0.5)),
        Text(value, style: TextStyle(color: t.textPrimary, fontSize: 11, fontFamily: 'monospace')),
      ]),
    );
  }
}
