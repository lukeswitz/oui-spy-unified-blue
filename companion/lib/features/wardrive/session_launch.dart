import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
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

class SessionBar extends ConsumerWidget {
  const SessionBar({super.key});

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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: wd.isActive ? Engine.wardrive.color : t.border, width: wd.isActive ? 1 : 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final m in WardriveController.selectableTargets)
                Expanded(
                  child: Builder(builder: (context) {
                    final sel = live.contains(m) || (live.isEmpty && wd.isTargetSelected(m));
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => wd.onChipTap(m, live),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: sel ? m.color.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? m.color.withValues(alpha: 0.5) : t.border, width: 0.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(m.icon, size: 16, color: sel ? m.color : t.textDim),
                            FittedBox(
                              child: Text(
                                m.label,
                                style: TextStyle(color: sel ? m.color : t.textDim, fontSize: 9, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
          if (!wd.isActive)
            Row(
              children: [
                for (final r in WardriveRadio.values)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setWardriveRadio(ref, switch (r) {
                        WardriveRadio.wifi => 0x01,
                        WardriveRadio.ble => 0x02,
                        WardriveRadio.both => 0x03,
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              switch (r) {
                                WardriveRadio.wifi => Icons.wifi,
                                WardriveRadio.ble => Icons.bluetooth,
                                WardriveRadio.both => Icons.sensors,
                              },
                              size: 12,
                              color: r == wd.radio ? Engine.wardrive.color : t.textDim,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              r.label,
                              style: TextStyle(
                                color: r == wd.radio ? Engine.wardrive.color : t.textDim,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  busy
                      ? '${wd.radioTransition!.toUpperCase()}…'
                      : switch (wd.state) {
                          WardriveState.idle => 'SESSION IDLE',
                          WardriveState.running => 'RUNNING',
                          WardriveState.paused => 'PAUSED',
                        },
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: wd.isActive ? Engine.wardrive.color : t.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (!wd.isActive)
                FilledButton.icon(
                  key: const ValueKey('session-start'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Engine.wardrive.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                  onPressed: busy ? null : () => startWardriveSession(context, ref),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('START'),
                )
              else ...[
                IconButton(
                  tooltip: wd.state == WardriveState.paused ? 'Resume' : 'Pause',
                  onPressed: busy
                      ? null
                      : () => wd.state == WardriveState.paused ? wd.resumeSession() : wd.pauseSession(),
                  icon: Icon(wd.state == WardriveState.paused ? Icons.play_arrow : Icons.pause),
                ),
                FilledButton.icon(
                  key: const ValueKey('session-stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                  onPressed: wd.radioTransition == 'stopping' ? null : wd.stopSession,
                  icon: const Icon(Icons.stop),
                  label: const Text('STOP'),
                ),
              ],
            ],
          ),
        ],
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
  if (!await confirmRadioRoles(context, ref)) {
    DebugLog.log('WARDRIVE: start aborted — radio roles canceled');
    return false;
  }
  await ref.read(wardriveProvider).startSession();
  return true;
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
            'OUI-SPY needs location access to tag wardrive detections.\n\n'
            'Open Settings → OUI-SPY → Location and choose "While Using" or "Always".',
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
    if (Platform.isIOS && status == LocationPermission.whileInUse) {
      await _alwaysUpgradeDialog(
        context,
        prefKey: 'ios_always_upgrade_dismissed',
        body:
            'iOS only shows "While Using" in the first prompt. For wardriving with screen off, set:\n\n'
            'Settings → OUI-SPY → Location → Always',
        action: 'OPEN SETTINGS',
        onAction: Geolocator.openAppSettings,
      );
    } else if (Platform.isAndroid) {
      final always = await ph.Permission.locationAlways.status;
      if (!always.isGranted && context.mounted) {
        await _alwaysUpgradeDialog(
          context,
          prefKey: 'android_always_upgrade_dismissed',
          body:
              'For background tracking, Android requires "Allow all the time".\n\n'
              'Settings → Apps → OUI-SPY → Permissions → Location → Allow all the time',
          action: 'ALLOW ALL THE TIME',
          onAction: () async {
            if (!(await ph.Permission.locationAlways.request()).isGranted) {
              await ph.openAppSettings();
            }
          },
        );
      }
    }
    return true;
  }
}

Future<bool> confirmRadioRoles(BuildContext context, WidgetRef ref) async {
  final app = ref.read(appStateProvider);
  final phone = ref.read(phoneBleSourceProvider);
  final phoneChoice = phone.active && PhoneBleSource.canScanWifi;
  final mgrId = AppState.canonicalNodeId(app.nodeId);
  final nodes = app.isManagerConnected
      ? (app.liveKnownNodes.where((id) => id != mgrId).toList()..sort())
      : <String>[];
  if (phoneChoice) nodes.add(BleManager.phoneNodeId);
  if (nodes.isEmpty) return true;
  final result = await showDialog<Map<String, int>>(
    context: context,
    builder: (_) => RadioRolePopup(
      nodes: nodes,
      labelFor: app.labelForNode,
      initial: {
        for (final n in nodes)
          n: n == BleManager.phoneNodeId ? phone.radioMask : app.wardriveRadioForNode(n),
      },
    ),
  );
  if (result == null) return false;
  final phoneMask = result.remove(BleManager.phoneNodeId);
  if (phoneMask != null) phone.setRadioMask(phoneMask);
  if (result.isNotEmpty) await app.applyNodeRadioRoles(result);
  if (!app.isManagerConnected && result.length == 1) {
    setWardriveRadio(ref, result.values.first);
  }
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

Future<void> _alwaysUpgradeDialog(
  BuildContext context, {
  required String prefKey,
  required String body,
  required String action,
  required Future<void> Function() onAction,
}) async {
  final p = await SharedPreferences.getInstance();
  if (p.getBool(prefKey) == true || !context.mounted) return;
  final t = AppTheme.of(context);
  await _settingsDialog(
    context,
    title: 'Enable "Always" Location',
    body: body,
    action: action,
    onAction: onAction,
    leading: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            await p.setBool(prefKey, true);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: Text("DON'T ASK AGAIN", style: TextStyle(color: t.textDim)),
        ),
      ),
    ],
  );
}

class RadioRolePopup extends StatefulWidget {
  const RadioRolePopup({
    super.key,
    required this.nodes,
    required this.labelFor,
    required this.initial,
  });

  final List<String> nodes;
  final String Function(String) labelFor;
  final Map<String, int> initial;

  @override
  State<RadioRolePopup> createState() => _RadioRolePopupState();
}

class _RadioRolePopupState extends State<RadioRolePopup> {
  late final Map<String, int> _roles = {
    for (final n in widget.nodes) n: widget.initial[n] ?? 0x03,
  };

  static const _wifiColor = Color(0xFF6B8AFF);
  static const _bleColor = Color(0xFF9B6BFF);
  static const _bothColor = Color(0xFF5AE6D6);

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
              final mask = _roles[id] ?? 0x03;
              final selColor = _radioColor(mask);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(10),
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
                            boxShadow: [
                              BoxShadow(
                                color: selColor.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
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
                          side: WidgetStateProperty.all(
                            BorderSide(color: selColor.withValues(alpha: 0.45)),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 0x01,
                            icon: Icon(Icons.wifi, size: 15, color: _wifiColor),
                            label: Text('WiFi'),
                          ),
                          ButtonSegment(
                            value: 0x02,
                            icon: Icon(
                              Icons.bluetooth,
                              size: 15,
                              color: _bleColor,
                            ),
                            label: Text('BLE'),
                          ),
                          ButtonSegment(
                            value: 0x03,
                            icon: Icon(
                              Icons.sensors,
                              size: 15,
                              color: _bothColor,
                            ),
                            label: Text('Both'),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: TextStyle(color: t.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.background,
          ),
          onPressed: () => Navigator.pop(context, _roles),
          child: const Text('START'),
        ),
      ],
    );
  }
}
