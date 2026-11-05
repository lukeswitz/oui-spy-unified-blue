import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/features/onboarding/permissions_screen.dart';
import 'package:oui_spy/theme/app_theme.dart';

bool targetEngineRunning(AppState app, WardriveTarget m) {
  bool on(Engine e) => app.getEngineState(e) != EngineState.disabled;
  return switch (m) {
    WardriveTarget.flock => on(Engine.flockBle) || on(Engine.flockWifi),
    WardriveTarget.drone => on(Engine.skySpy),
    WardriveTarget.detector => on(Engine.detector),
    WardriveTarget.wigle => on(Engine.wardrive),
    WardriveTarget.wigleFlock => on(Engine.wardrive) || on(Engine.flockBle) || on(Engine.flockWifi),
  };
}

class _SessionSourcesChip extends ConsumerWidget {
  const _SessionSourcesChip();

  static List<Widget> _source(IconData icon, int mask, Color color) => [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        if (mask & 0x01 != 0) Icon(Icons.wifi, size: 11, color: color),
        if (mask & 0x02 != 0) Icon(Icons.bluetooth, size: 11, color: color),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final app = ref.watch(appStateProvider);
    final wd = ref.watch(wardriveProvider);
    final phone = ref.watch(phoneBleSourceProvider);
    final parts = <List<Widget>>[];
    if (app.isManagerConnected) {
      final self = AppState.canonicalNodeId(app.nodeId);
      final n = app.liveKnownNodes.where((id) => id != self && !app.isManagerNode(id)).length;
      parts.add([
        Icon(Icons.hub_outlined, size: 13, color: t.textSecondary),
        const SizedBox(width: 3),
        Text('$n', style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
      ]);
    } else if (app.isConnected) {
      parts.add(_source(Icons.memory, wd.radioBitmask, t.textSecondary));
    }
    if (phone.scanning) {
      parts.add(_source(Icons.smartphone, PhoneBleSource.canScanWifi ? phone.radioMask : 0x02, t.textSecondary));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text('·', style: TextStyle(color: t.textDim, fontSize: 11)),
              ),
            ...parts[i],
          ],
        ],
      ),
    );
  }
}

class SessionTargets extends ConsumerWidget {
  const SessionTargets({super.key, this.wigleLabel});
  final String? wigleLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTheme.of(context);
    final wd = ref.watch(wardriveProvider);
    final app = ref.watch(appStateProvider);
    final live = {
      for (final x in WardriveController.selectableTargets)
        if (targetEngineRunning(app, x)) x,
    };
    final busy = wd.radioTransition != null;

    Widget chip(WardriveTarget m) {
      final sel = wd.isTargetSelected(m);
      final fg = sel ? t.background : t.textPrimary;
      final iconColor = sel ? t.background : t.textSecondary;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: () => wd.onChipTap(m, live),
          child: Container(
            key: ValueKey('target-chip-${m.name}'),
            height: 60,
            decoration: BoxDecoration(
              color: sel ? t.textPrimary : t.surfaceLight,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(m.icon, size: 18, color: iconColor),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    m == WardriveTarget.wigle && wigleLabel != null ? wigleLabel! : m.label,
                    style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget segment(WardriveRadio r) {
      final sel = r == wd.radio;
      return Expanded(
        child: Material(
          color: sel ? t.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setWardriveRadio(ref, switch (r) {
              WardriveRadio.wifi => 0x01,
              WardriveRadio.ble => 0x02,
              WardriveRadio.both => 0x03,
            }),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  switch (r) {
                    WardriveRadio.wifi => Icons.wifi,
                    WardriveRadio.ble => Icons.bluetooth,
                    WardriveRadio.both => Icons.sensors,
                  },
                  size: 14,
                  color: sel ? t.background : t.textSecondary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      r.label,
                      style: TextStyle(
                        color: sel ? t.background : t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final targets = WardriveController.selectableTargets;
    final radios = WardriveRadio.values;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wd.isActive) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _SessionSourcesChip(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Opacity(
            opacity: busy ? 0.5 : 1,
            child: Row(
              children: [
                for (var i = 0; i < targets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chip(targets[i]),
                ],
              ],
            ),
          ),
          if (!wd.isActive) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('radio-control'),
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: t.surfaceLight,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final r in radios) segment(r)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SessionStartButton extends ConsumerWidget {
  const SessionStartButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wd = ref.watch(wardriveProvider);
    final busy = wd.radioTransition != null;
    final busyText = '${wd.radioTransition?.toUpperCase()}…';
    final shape = ElevatedButton.styleFrom(
      minimumSize: const Size(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    );
    if (!wd.isActive) {
      final startFg = AppTheme.contrast(AppTheme.wardrive, Colors.black) >= 4.5 ? Colors.black : Colors.white;
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton(
          key: const ValueKey('session-start'),
          style: shape.copyWith(
            backgroundColor: WidgetStatePropertyAll(AppTheme.wardrive),
            foregroundColor: WidgetStatePropertyAll(startFg),
          ),
          onPressed: busy ? null : () => startWardriveSession(context, ref),
          child: Row(
            children: [
              Text(busy ? busyText : 'START'),
              const Spacer(),
              Icon(Icons.arrow_forward, size: 18, color: startFg),
            ],
          ),
        ),
      );
    }
    final fg = AppTheme.contrast(AppTheme.error, Colors.black) >= 4.5 ? Colors.black : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        key: const ValueKey('session-stop'),
        style: shape.copyWith(
          backgroundColor: WidgetStatePropertyAll(AppTheme.error),
          foregroundColor: WidgetStatePropertyAll(fg),
        ),
        onPressed: wd.radioTransition == 'stopping' ? null : () => stopWardriveSession(ref),
        child: Row(
          children: [
            Text(busy ? busyText : 'STOP'),
            const Spacer(),
            Icon(Icons.stop, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}

Future<bool> startWardriveSession(BuildContext context, WidgetRef ref, {bool requireLocation = true}) async {
  DebugLog.log('WARDRIVE: start requested');
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (ref.read(wardriveProvider).selectedTargets.isEmpty) {
    DebugLog.log('WARDRIVE: start aborted — no targets');
    messenger?.showSnackBar(const SnackBar(content: Text('Select at least one target to scan')));
    return false;
  }
  ref.read(gpsProvider).onMessage = (msg) => messenger?.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.accent, duration: const Duration(seconds: 4)),
      );
  if (requireLocation && !await primeLocationPermission(context)) {
    DebugLog.log('WARDRIVE: start aborted — location permission/services');
    return false;
  }
  if (!context.mounted) {
    DebugLog.log('WARDRIVE: start aborted — screen gone');
    return false;
  }
  if (requireLocation) await _askAlwaysLocation(context);
  if (!context.mounted) {
    DebugLog.log('WARDRIVE: start aborted — screen gone');
    return false;
  }
  await _askBackgroundRun(context);
  if (!context.mounted) {
    DebugLog.log('WARDRIVE: start aborted — screen gone');
    return false;
  }
  if (!await confirmRadioRoles(context, ref)) {
    DebugLog.log('WARDRIVE: start aborted — radio roles canceled');
    return false;
  }
  final wd = ref.read(wardriveProvider);
  final usb = ref.read(wifiAdapterControllerProvider);
  final usbScan = ref.read(usbAdapterScanProvider);
  await wd.startSession();
  if (usbScan &&
      usb.devices.isNotEmpty &&
      usb.state != WifiAdapterState.running &&
      usb.state != WifiAdapterState.starting) {
    final mask = switch (wd.radio) {
      WardriveRadio.wifi => 0x01,
      WardriveRadio.ble => 0x02,
      WardriveRadio.both => 0x03,
    };
    await usb.start(usb.devices.first, radioMask: mask);
  }
  return true;
}

Future<void> stopWardriveSession(WidgetRef ref) async {
  await ref.read(wardriveProvider).stopSession();
  final usb = ref.read(wifiAdapterControllerProvider);
  if (usb.state == WifiAdapterState.running ||
      usb.state == WifiAdapterState.starting) {
    await usb.stop();
  }
}

Future<bool>? _priming;

Future<bool> primeLocationPermission(BuildContext context) => _priming ??=
    _primeLocationPermission(context).whenComplete(() => _priming = null);

Future<bool> _primeLocationPermission(BuildContext context) async {
  if (!context.mounted) return false;
  {
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    if (!context.mounted) return false;
    if (status == LocationPermission.denied ||
        status == LocationPermission.deniedForever) {
      await _settingsDialog(
        context,
        title: 'Location Permission Required',
        body:
            'OUI-APEX needs location access to tag wardrive detections.\n\n'
            'Open Settings → OUI-APEX → Location and choose "While Using" or "Always".',
        action: 'OPEN SETTINGS',
        onAction: Geolocator.openAppSettings,
      );
      return false;
    }
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!context.mounted) return false;
    if (!servicesOn) {
      await _settingsDialog(
        context,
        title: 'Location Services Off',
        body:
            'Enable Settings → Privacy & Security → Location Services to wardrive.',
      );
      return false;
    }
    return true;
  }
}

Future<void> _askAlwaysLocation(BuildContext context) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  if (await Geolocator.checkPermission() == LocationPermission.always || !context.mounted) return;
  await _settingsDialog(
    context,
    title: 'Enable "Always" Location',
    body: 'Location stops reaching the app when the screen turns off, so the map and distance '
        'stop too.\n\n'
        '${Platform.isAndroid ? 'Location → Allow all the time' : 'Location → Always'}',
    action: 'TURN ON',
    onAction: openAlwaysLocationSettings,
  );
}

Future<void> _askBackgroundRun(BuildContext context) async {
  if (!Platform.isAndroid || await backgroundRunAllowed() || !context.mounted) return;
  await _settingsDialog(
    context,
    title: 'Allow background running',
    body: 'With battery optimization on, Android puts the phone to sleep about a minute after the '
        'screen turns off. Scanning, GPS and the board link freeze until you unlock it.',
    action: 'ALLOW',
    onAction: requestBackgroundRun,
  );
}

Future<bool> confirmRadioRoles(BuildContext context, WidgetRef ref) async {
  final app = ref.read(appStateProvider);
  final phone = ref.read(phoneBleSourceProvider);
  final phoneChoice = phone.active && PhoneBleSource.canScanWifi;
  final mgrId = AppState.canonicalNodeId(app.nodeId);
  final nodes = app.isManagerConnected
      ? (app.liveKnownNodes.where((id) => id != mgrId).toList()..sort())
      : <String>[];
  final selfId = app.isConnected && !app.isManagerConnected
      ? (mgrId.isNotEmpty ? mgrId : 'LOCAL')
      : null;
  final ble = ref.read(bleManagerProvider);
  if (selfId != null) await ble.enowHubRefresh();
  final hubId = selfId != null && ble.enowHubActive ? selfId : null;
  final hubNodes = hubId == null
      ? const <EnowHubNode>[]
      : [for (final n in ble.enowHubNodeMap.values) if (n.paired) n];
  if (selfId != null && (phoneChoice || hubId != null)) nodes.add(selfId);
  if (phoneChoice) nodes.add(BleManager.phoneNodeId);
  if (nodes.isEmpty) return true;
  if (!context.mounted) return false;
  final wd = ref.read(wardriveProvider);
  final result = await showDialog<({Map<String, int> roles, Set<String> skip})>(
    context: context,
    builder: (_) => RadioRolePopup(
      nodes: nodes,
      labelFor: app.labelForNode,
      hubId: hubId,
      hubNodes: hubNodes,
      initial: {
        for (final n in nodes)
          n: n == BleManager.phoneNodeId
              ? phone.radioMask
              : n == selfId
                  ? wd.radioBitmask
                  : app.wardriveRadioForNode(n),
      },
    ),
  );
  if (result == null) return false;
  final roles = result.roles;
  final phoneMask = roles.remove(BleManager.phoneNodeId);
  if (phoneMask != null) phone.setRadioMask(phoneMask);
  final selfMask = selfId == null ? null : roles.remove(selfId);
  if (selfMask != null && hubId == null) setWardriveRadio(ref, selfMask);
  if (roles.isNotEmpty) await app.applyNodeRadioRoles(roles);
  if (result.skip.isNotEmpty) await ble.enowHubSkipForSession(result.skip);
  return true;
}

void setWardriveRadio(WidgetRef ref, int mask) {
  final wd = ref.read(wardriveProvider);
  final app = ref.read(appStateProvider);
  wd.setRadio(WardriveController.radioFromMask(mask));
  app.setEngineRadio(Engine.wardrive, mask);
  for (final t in wd.selectedTargets) {
    final e = t.radioMaskEngine;
    if (e != null && e != Engine.wardrive) app.setEngineRadio(e, mask);
  }
}

Future<void> _settingsDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? action,
  Future<void> Function()? onAction,
  List<Widget> leading = const [],
}) {
  final t = AppTheme.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      title: Text(
        title,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        body,
        style: TextStyle(color: t.textSecondary, fontSize: 13),
      ),
      actions: [
        ...leading,
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(
            action == null ? 'OK' : 'LATER',
            style: TextStyle(
              color: action == null ? AppTheme.accent : t.textDim,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await onAction?.call();
            },
            child: Text(action, style: TextStyle(color: AppTheme.accent)),
          ),
      ],
    ),
  );
}

class RadioRolePopup extends StatefulWidget {
  const RadioRolePopup({
    super.key,
    required this.nodes,
    required this.labelFor,
    required this.initial,
    this.hubId,
    this.hubNodes = const [],
  });

  final List<String> nodes;
  final String Function(String) labelFor;
  final Map<String, int> initial;
  final String? hubId;
  final List<EnowHubNode> hubNodes;

  @override
  State<RadioRolePopup> createState() => _RadioRolePopupState();
}

class _RadioRolePopupState extends State<RadioRolePopup> {
  late final Map<String, int> _roles = {
    for (final n in widget.nodes) n: widget.initial[n] ?? 0x03,
  };
  late final Map<String, bool> _include = {
    for (final n in widget.hubNodes) n.mac: true,
  };

  Widget _hubCard(ResolvedTheme t, String id) {
    final count = widget.hubNodes.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: t.background,
        border: Border.all(color: AppTheme.wardrive.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.router, size: 16, color: AppTheme.wardrive),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.labelFor(id),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text(
                'HUB · $count node${count == 1 ? '' : 's'}',
                style: TextStyle(color: AppTheme.wardrive, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
            ],
          ),
          if (count == 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No paired nodes', style: TextStyle(color: t.textDim, fontSize: 12)),
            ),
          for (final n in widget.hubNodes)
            Row(
              children: [
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    n.name.isNotEmpty ? n.name.replaceFirst(':', ' ') : n.mac,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textSecondary, fontSize: 12.5, fontFamily: AppTheme.mono),
                  ),
                ),
                Text('WiFi', style: TextStyle(color: t.textDim, fontSize: 11)),
                Switch(
                  value: _include[n.mac] ?? true,
                  onChanged: (v) => setState(() => _include[n.mac] = v),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Color get _wifiColor => AppTheme.detector;
  static Color get _bleColor => AppTheme.flockBle;
  static Color get _bothColor => AppTheme.skySpy;

  static Color _radioColor(int mask) => switch (mask & 0x03) {
    0x01 => _wifiColor,
    0x02 => _bleColor,
    _ => _bothColor,
  };

  static String _maskLabel(int mask) => switch (mask & 0x03) {
    0x01 => 'WIFI',
    0x02 => 'BLE',
    _ => 'BOTH',
  };

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      title: Row(
        children: [
          Icon(
            Icons.settings_input_antenna,
            color: AppTheme.accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'NODE RADIOS',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Assign each node WiFi, BLE, or Both for this wardrive. '
                'WiFi nodes split channels; BLE nodes cover BLE.',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
            ),
            ...widget.nodes.map((id) {
              if (id == widget.hubId) return _hubCard(t, id);
              final mask = _roles[id] ?? 0x03;
              final selColor = _radioColor(mask);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: t.background,
                  border: Border.all(color: selColor.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: selColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.labelFor(id),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          _maskLabel(mask),
                          style: TextStyle(
                            color: selColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: WidgetStateProperty.all(
                            const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          textStyle: WidgetStateProperty.all(
                            const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? selColor.withValues(alpha: 0.22)
                                : Colors.transparent,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? t.textPrimary
                                : t.textSecondary,
                          ),
                          side: WidgetStateProperty.all(
                            BorderSide(color: selColor.withValues(alpha: 0.45)),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 0x01,
                            label: Text('WiFi', maxLines: 1, softWrap: false),
                          ),
                          ButtonSegment(
                            value: 0x02,
                            label: Text('BLE', maxLines: 1, softWrap: false),
                          ),
                          ButtonSegment(
                            value: 0x03,
                            label: Text('Both', maxLines: 1, softWrap: false),
                          ),
                        ],
                        selected: {mask},
                        onSelectionChanged: (s) =>
                            setState(() => _roles[id] = s.first),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(context, (
            roles: _roles,
            skip: {for (final e in _include.entries) if (!e.value) e.key},
          )),
          child: const Text('START'),
        ),
      ],
    );
  }
}
