import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_permissions.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    final ble = ref.read(bleManagerProvider);
    if (ble.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
    } else {
      _connSub = ble.connectionState.listen((state) {
        if (state == NodeConnectionState.ready && mounted) {
          context.go('/home');
        }
      });
    }
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
              advName.contains('OUI') || advName.contains('SPY')) {
            _results[r.device.remoteId.toString()] = r;
          }
        }
      });
    }, onError: (e) {
      if (mounted) setState(() { _error = e.toString(); _scanning = false; });
    });

    try {
      await FlutterBluePlus.startScan(
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
                  style: const TextStyle(color: AppTheme.accent)),
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
      final n = r.device.platformName;
      if (n.isNotEmpty) return n.toUpperCase();
      return r.advertisementData.advName.toUpperCase();
    }
    bool isMgr(ScanResult r) {
      final n = displayName(r);
      return n.contains('-MGR') || n.contains('OUI-SPY-MGR');
    }
    final hasManager = all.any(isMgr);
    final filtered = hasManager ? all.where(isMgr).toList() : all;
    final sorted = filtered
      ..sort((a, b) => displayName(a).compareTo(displayName(b)));

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('CONNECT'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 11, fontFamily: 'monospace')),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _scanning ? null : _startScan,
                child: Text(_scanning ? 'SCANNING...' : 'SCAN FOR OUI-SPY'),
              ),
            ),
            const SizedBox(height: 8),

            if (_scanning)
              LinearProgressIndicator(color: AppTheme.accent, backgroundColor: t.border),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${sorted.length} device${sorted.length == 1 ? '' : 's'} found',
                  style: TextStyle(color: t.textDim, fontSize: 11)),
            ),

            Expanded(
              child: sorted.isEmpty
                  ? Center(child: Text(
                      _scanning ? 'SEARCHING...' : 'TAP SCAN TO FIND DEVICES',
                      style: TextStyle(color: t.textDim, letterSpacing: 1, fontSize: 11),
                    ))
                  : ListView.builder(
                      itemCount: sorted.length,
                      itemBuilder: (context, index) {
                        final r = sorted[index];
                        final id = r.device.remoteId.toString();
                        final isThisConnecting = _connecting && _connectingId == id;
                        final isOtherConnecting = _connecting && _connectingId != id;
                        return GestureDetector(
                          onTap: _connecting ? null : () => _connectDevice(r),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isOtherConnecting
                                  ? t.surface.withValues(alpha: 0.4)
                                  : AppTheme.accent.withValues(alpha: isThisConnecting ? 0.2 : 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                isThisConnecting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: AppTheme.accent,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.bluetooth, color: AppTheme.accent, size: 20),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.device.platformName.isNotEmpty
                                          ? r.device.platformName
                                          : (r.advertisementData.advName.isNotEmpty
                                              ? r.advertisementData.advName
                                              : '(unnamed)'),
                                        style: const TextStyle(color: AppTheme.accent, fontSize: 14, fontWeight: FontWeight.w600)),
                                    Text(
                                      isThisConnecting
                                          ? 'CONNECTING...'
                                          : r.device.remoteId.toString(),
                                      style: TextStyle(
                                        color: isThisConnecting
                                            ? AppTheme.accent
                                            : t.textDim,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        letterSpacing: isThisConnecting ? 1.5 : 0,
                                        fontWeight: isThisConnecting
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                )),
                                if (!isThisConnecting)
                                  Text('${r.rssi} dBm', style: TextStyle(
                                    color: r.rssi > -60 ? AppTheme.success : r.rssi > -80 ? AppTheme.warning : AppTheme.error,
                                    fontSize: 12, fontFamily: 'monospace',
                                  )),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
