import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_permissions.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final Map<String, ScanResult> _results = {};
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingId;
  String? _error;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<NodeConnectionState>? _connSub;
  String? _rememberedMgrId;

  Future<void> _loadRememberedManager() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (p.getBool('lastPrimaryIsManager') ?? false) {
      setState(() => _rememberedMgrId = p.getString('lastPrimaryDeviceId'));
    }
  }

  @override
  void initState() {
    super.initState();
    final ble = ref.read(bleManagerProvider);
    if (ble.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
      return;
    }
    _loadRememberedManager();
    _connSub = ble.connectionState.listen((state) {
      if (state == NodeConnectionState.ready && mounted) {
        context.go('/home');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startScan();
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final perm = await BlePermissions.ensureForScan();
    if (!mounted) return;
    if (perm != BlePermResult.ready) {
      _showPermDialog(perm);
      return;
    }

    _results.clear();
    _error = null;
    setState(() => _scanning = true);

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } on Exception catch (e) {
      DebugLog.log('SCAN: stopScan pre-clean: $e');
    }

    var adapter = FlutterBluePlus.adapterStateNow;
    if (adapter == BluetoothAdapterState.unknown) {
      try {
        adapter = await FlutterBluePlus.adapterState
            .firstWhere((s) => s != BluetoothAdapterState.unknown)
            .timeout(const Duration(seconds: 2),
                onTimeout: () => FlutterBluePlus.adapterStateNow);
      } on Exception catch (e) {
        DebugLog.log('SCAN: adapter check: $e');
      }
    }
    if (adapter != BluetoothAdapterState.on &&
        adapter != BluetoothAdapterState.unknown) {
      if (mounted) {
        setState(() {
          _error = 'Bluetooth not on ($adapter)';
          _scanning = false;
        });
      }
      return;
    }

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          final name = r.device.platformName.toUpperCase();
          final advName = r.advertisementData.advName.toUpperCase();
          if (name.contains('OUI') || name.contains('SPY') ||
              advName.contains('OUI') || advName.contains('SPY') ||
              r.advertisementData.serviceUuids.contains(GattUuids.service)) {
            _results[r.device.remoteId.toString()] = r;
          }
        }
      });
    }, onError: (e) {
      if (mounted) setState(() { _error = e.toString(); _scanning = false; });
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [GattUuids.service],
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('SCAN: startScan failed: ${e.description}');
      if (mounted) {
        setState(() {
          _error = 'Scan failed: ${e.description}';
          _scanning = false;
        });
      }
      return;
    }

    await FlutterBluePlus.isScanning.where((s) => !s).first;
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connectDevice(ScanResult result) async {
    if (_connecting) {
      DebugLog.log('SCAN: tap ignored — connect in flight to $_connectingId');
      return;
    }
    final id = result.device.remoteId.toString();
    setState(() {
      _connecting = true;
      _connectingId = id;
    });

    try {
      await FlutterBluePlus.stopScan();
    } on Exception catch (e) {
      DebugLog.log('SCAN: stopScan: $e');
    }
    _scanSub?.cancel();
    if (mounted) setState(() => _scanning = false);

    final ble = ref.read(bleManagerProvider);

    try {
      await ble.connect(result.device, sessionId: const Uuid().v4());
      DebugLog.log('SCAN: connected to ${result.device.platformName}');
      if (mounted) context.go('/home');
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('SCAN: connect failed: ${e.description}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: ${e.description}'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connectingId = null;
        });
      }
    }
  }

  void _showPermDialog(BlePermResult result) {
    final t = AppTheme.of(context);
    final bool servicesOff = result == BlePermResult.locationServicesOff;
    final bool permanently =
        result == BlePermResult.permissionPermanentlyDenied;

    final String title = servicesOff
        ? 'Location Services Off'
        : 'Bluetooth Permission Required';
    final String body = servicesOff
        ? 'Android requires Location Services to be ON to scan for Bluetooth '
            'devices. Enable it, then tap SCAN again.'
        : permanently
            ? 'Bluetooth scanning permission was denied. Open Settings and '
                'allow Nearby devices / Location for OUI-SPY, then tap SCAN again.'
            : 'OUI-SPY needs Bluetooth scanning permission to find your node. '
                'Tap SCAN again and allow it.';
    final String actionLabel =
        servicesOff ? 'ENABLE LOCATION' : 'OPEN SETTINGS';
    final bool showAction = servicesOff || permanently;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title,
            style: TextStyle(
                color: t.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: Text(body,
            style: TextStyle(color: t.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('LATER', style: TextStyle(color: t.textDim)),
          ),
          if (showAction)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (servicesOff) {
                  await BlePermissions.openLocationSettings();
                } else {
                  await BlePermissions.openAppSettings();
                }
              },
              child: Text(actionLabel,
                  style: TextStyle(color: AppTheme.accent)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final all = _results.values.toList();
    String displayName(ScanResult r) {
      final adv = r.advertisementData.advName;
      if (adv.isNotEmpty) return adv.toUpperCase();
      return r.device.platformName.toUpperCase();
    }
    bool isMgr(ScanResult r) {
      final adv = r.advertisementData.advName.toUpperCase();
      final plat = r.device.platformName.toUpperCase();
      if (adv.contains('-MGR') || plat.contains('-MGR')) return true;
      final rem = _rememberedMgrId;
      return rem != null && rem == r.device.remoteId.toString();
    }
    final hasManager =
        all.any(isMgr) || ref.read(bleManagerProvider).isManagerConnected;
    final filtered = hasManager ? all.where(isMgr).toList() : all;
    final sorted = filtered
      ..sort((a, b) => displayName(a).compareTo(displayName(b)));

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('CONNECT'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
      ),
      body: SizedBox(
        width: double.infinity,
        child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 11, fontFamily: 'monospace')),
              ),
            ),

          if (sorted.isEmpty) ...[
            const Spacer(),
            _ScanRadar(active: _scanning),
            const SizedBox(height: 24),
            Text(
              'OUI-SPY',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _scanning ? 'Searching for nodes...' : 'Scan for nearby nodes to connect',
              style: TextStyle(color: t.textDim, fontSize: 13),
            ),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: _scanning ? null : _startScan,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: BorderSide(color: AppTheme.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              ),
              child: Text(
                _scanning ? 'SCANNING...' : 'Scan for devices',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
            ),
            const Spacer(flex: 2),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    '${sorted.length} FOUND',
                    style: TextStyle(color: t.textDim, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: 'monospace'),
                  ),
                  const Spacer(),
                  if (!_scanning)
                    GestureDetector(
                      onTap: _startScan,
                      child: Text('RESCAN', style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: 'monospace')),
                    ),
                  if (_scanning)
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final r = sorted[index];
                  final id = r.device.remoteId.toString();
                  final isThisConnecting = _connecting && _connectingId == id;
                  final isOtherConnecting = _connecting && _connectingId != id;
                  final name = r.advertisementData.advName.isNotEmpty
                      ? r.advertisementData.advName
                      : (r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : (r.advertisementData.serviceUuids.contains(GattUuids.service)
                              ? 'OUI-SPY node'
                              : '(unnamed)'));
                  return GestureDetector(
                    onTap: _connecting ? null : () => _connectDevice(r),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isThisConnecting
                            ? AppTheme.accent.withValues(alpha: 0.12)
                            : t.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isThisConnecting
                              ? AppTheme.accent.withValues(alpha: 0.5)
                              : isOtherConnecting
                                  ? t.border.withValues(alpha: 0.3)
                                  : t.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: isOtherConnecting ? 0.04 : 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: isThisConnecting
                                ? Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)))
                                : Icon(Icons.bluetooth, color: isOtherConnecting ? t.textDim : AppTheme.accent, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: isOtherConnecting ? t.textDim : t.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (isMgr(r))
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text('MGR', style: TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                                    ),
                                  Text(
                                    isThisConnecting ? 'CONNECTING...' : id,
                                    style: TextStyle(
                                      color: isThisConnecting ? AppTheme.accent : t.textDim,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )),
                          if (!isThisConnecting)
                            _SignalBars(rssi: r.rssi),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _ScanRadar extends StatefulWidget {
  const _ScanRadar({required this.active});
  final bool active;
  @override
  State<_ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<_ScanRadar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = widget.active ? (0.5 + 0.5 * (1.0 - (2.0 * (_ctrl.value - 0.5)).abs())) : 0.5;
        return SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15 + v * 0.15), width: 1.5),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1 + v * 0.1), width: 1),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent,
                  boxShadow: [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.4), blurRadius: 12)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi});
  final int rssi;
  @override
  Widget build(BuildContext context) {
    final bars = rssi > -50 ? 4 : rssi > -65 ? 3 : rssi > -80 ? 2 : 1;
    final color = rssi > -60 ? AppTheme.success : rssi > -75 ? AppTheme.warning : AppTheme.error;
    final t = AppTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final h = 4.0 + i * 3.5;
        return Container(
          width: 3,
          height: h,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < bars ? color : t.border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
