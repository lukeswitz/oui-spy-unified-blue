import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/drone_grouping.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/features/engines/drone_map_view.dart';
import 'package:oui_spy/theme/app_theme.dart';

class SkySpyScreen extends ConsumerWidget {
  const SkySpyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final state = ref.watch(appStateProvider);
    final isActive = state.isEngineActive(Engine.skySpy);
    final groups = groupDronesByUavId(state.recentDetections);
    final droneList = groups.map((g) => g.representative).toList();

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
                  ble.enableEngine(Engine.skySpy,
                      radio: ref.read(appStateProvider).engineRadio[Engine.skySpy]);
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
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: DroneMapView(drones: droneList),
          ),
          Expanded(
            child: droneList.isEmpty
                ? Center(
                    child: Text(
                        isActive
                            ? 'SCANNING FOR DRONES...'
                            : 'ENABLE TO START SCANNING',
                        style: TextStyle(
                            color: t.textDim, letterSpacing: 2, fontSize: 12)))
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) =>
                        _DroneRow(group: groups[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DroneRow extends StatelessWidget {
  const _DroneRow({required this.group});
  final DroneGroup group;

  static String _transport(String method) {
    switch (method) {
      case 'odid_nan':
        return 'WiFi NAN';
      case 'odid_beacon':
        return 'WiFi Beacon';
      case 'odid_ble':
        return 'BLE';
      default:
        return method.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final detection = group.representative;
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
                group.uavId,
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
                _Chip('POS', '${odid.droneLat!.toStringAsFixed(4)}, ${odid.droneLon!.toStringAsFixed(4)}')
              else
                _Chip('RANGE',
                    '${rssiRangeLabel(detection.rssi, isBle: isBleMethod(detection.method))} RSSI'),
              if (odid.operatorId != null && odid.operatorId!.isNotEmpty)
                _Chip('OP', odid.operatorId!),
            ]),
            if (odid.selfId != null && odid.selfId!.isNotEmpty) ...[
              const SizedBox(height: 4),
              _Chip('DESC', odid.selfId!),
            ],
            if (odid.pilotLat != null && odid.pilotLat != 0) ...[
              const SizedBox(height: 4),
              _Chip('PILOT', '${odid.pilotLat!.toStringAsFixed(4)}, ${odid.pilotLon!.toStringAsFixed(4)}'),
            ],
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (var i = 0; i < group.macs.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.skySpy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${group.macs[i].toUpperCase()} · ${_transport(group.methods[i])}',
                    style: TextStyle(color: t.textDim, fontSize: 9, fontFamily: 'monospace'),
                  ),
                ),
            ],
          ),
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
