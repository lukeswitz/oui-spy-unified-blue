// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/db/detection_mapper.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_kits.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/radio_classifier.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';

Future<KitRole?> pickKitRole(BuildContext context, {KitRole? guess}) {
  return showDialog<KitRole>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('What is it?'),
      children: [
        for (final r in KitRole.values)
          SimpleDialogOption(
            key: Key('kit-role-${r.name}'),
            onPressed: () => Navigator.pop(ctx, r),
            child: Text(r == guess ? '${r.label} (suggested)' : r.label),
          ),
      ],
    ),
  );
}

List<KitDevice> kitDevicesFromDetections(Iterable<Detection> rows) {
  final byMac = <String, List<Detection>>{};
  for (final d in rows) {
    if (d.engine == Engine.skySpy) continue;
    byMac.putIfAbsent(kitMacKey(d.macAddress), () => []).add(d);
  }
  return [
    for (final e in byMac.entries)
      KitDevice(
        mac: e.key,
        bleName: _firstText(e.value.where((d) => d.isBleDetection).map((d) => d.deviceName)),
        wifiName: _firstText(e.value.where((d) => d.isWifiDetection).map((d) => d.ssid)),
        sightings: [
          for (final d in e.value)
            KitSighting(
              ts: d.appTimestamp,
              point: validCoord(d.latitude, d.longitude)
                  ? LatLng(d.latitude!, d.longitude!)
                  : null,
              node: d.sourceNodeId,
            ),
        ],
      ),
  ];
}

String _firstText(Iterable<String> values) {
  for (final v in values) {
    if (v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

class DroneKitSection extends ConsumerStatefulWidget {
  const DroneKitSection({super.key, required this.droneId, required this.flights});

  final String droneId;
  final List<DroneFlight> flights;

  @override
  ConsumerState<DroneKitSection> createState() => _DroneKitSectionState();
}

class _DroneKitSectionState extends ConsumerState<DroneKitSection> {
  List<KitSuggestion> _suggestions = const [];
  int _suggestedFor = -1;

  Future<void> _refreshSuggestions() async {
    final flights = widget.flights;
    if (flights.isEmpty) return;
    final from = flights.first.start.subtract(kitFlightPad);
    final to = flights.last.end.add(kitFlightPad);
    final maps = await ref.read(databaseProvider).getNonDroneDetectionMapsBetween(from, to);
    final devices = kitDevicesFromDetections(maps.map(detectionFromDbRow));
    final members = ref.read(droneKitsProvider);
    final taken = {
      for (final l in members.values) for (final m in l) kitMacKey(m.mac),
    };
    if (!mounted) return;
    setState(() {
      _suggestions = kitSuggest(flights: flights, devices: devices, skip: taken);
      _suggestedFor = flights.length;
    });
  }

  Future<void> _add(String mac, String label, KitRole? guess) async {
    final role = await pickKitRole(context, guess: guess);
    if (role == null) return;
    await ref.read(droneKitsProvider.notifier).add(
          widget.droneId,
          KitMember(mac: mac, role: role, label: label),
        );
    if (!mounted) return;
    setState(() => _suggestions = [
          for (final s in _suggestions)
            if (kitMacKey(s.device.mac) != kitMacKey(mac)) s,
        ]);
  }

  Future<void> _addManual() async {
    final seen = <String>{};
    final taken = {
      for (final l in ref.read(droneKitsProvider).values) for (final m in l) kitMacKey(m.mac),
    };
    final devices = [
      for (final d in ref.read(appStateProvider).recentDetections)
        if (d.engine != Engine.skySpy &&
            !taken.contains(kitMacKey(d.macAddress)) &&
            seen.add(kitMacKey(d.macAddress)))
          d,
    ];
    final picked = await showModalBottomSheet<Detection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: devices.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No other device has been heard recently.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Add a heard device to this drone')),
                  for (final d in devices.take(40))
                    ListTile(
                      title: Text(_labelOf(d)),
                      subtitle: Text(d.macAddress.toUpperCase()),
                      onTap: () => Navigator.pop(ctx, d),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    final sign = kitSignature(bleName: picked.deviceName, wifiName: picked.ssid);
    await _add(picked.macAddress, _labelOf(picked), sign?.rule.role);
  }

  static String _labelOf(Detection d) {
    final name = d.deviceName.trim().isNotEmpty ? d.deviceName.trim() : d.ssid.trim();
    return name.isNotEmpty ? name : d.macAddress.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final members = ref.watch(droneKitsProvider)[widget.droneId] ?? const <KitMember>[];
    if (_suggestedFor != widget.flights.length && widget.flights.isNotEmpty) {
      _suggestedFor = widget.flights.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSuggestions());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DSectionHeader(label: 'Drone kit'),
        if (members.isEmpty && _suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'A controller, goggles or a dock can be added to the drone it flies with.',
              style: TextStyle(color: t.textDim, fontSize: 13),
            ),
          ),
        for (final m in members)
          ListTile(
            key: Key('kit-member-${kitMacKey(m.mac)}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_other),
            title: Text(m.label.isEmpty ? m.mac.toUpperCase() : m.label),
            subtitle: Text('${m.role.label} · ${m.mac.toUpperCase()}'),
            trailing: IconButton(
              tooltip: 'Take out of the kit',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(droneKitsProvider.notifier).remove(widget.droneId, m.mac),
            ),
          ),
        for (final s in _suggestions)
          ListTile(
            key: Key('kit-suggestion-${kitMacKey(s.device.mac)}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lightbulb_outline, color: AppTheme.warning),
            title: Text(s.device.label),
            subtitle: Text('Suggested${s.role == null ? '' : ' ${s.role!.label}'}: ${s.reasons.join('; ')}'),
            trailing: TextButton(
              onPressed: () => _add(s.device.mac, s.device.label, s.role),
              child: const Text('ADD'),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('kit-add-device'),
            onPressed: _addManual,
            icon: const Icon(Icons.add),
            label: const Text('ADD A DEVICE'),
          ),
        ),
      ],
    );
  }
}
