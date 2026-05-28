import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
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
          if (name.contains('OUI') || name.contains('SPY')) {
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
        androidUsesFineLocation: true,
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

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final all = _results.values.toList();
    final hasManager = all.any((r) =>
        r.device.platformName.toUpperCase().contains('OUI-SPY-MGR'));
    final filtered = hasManager
        ? all
            .where((r) => r.device.platformName.toUpperCase().contains('OUI-SPY-MGR'))
            .toList()
        : all;
    final sorted = filtered
      ..sort((a, b) => a.device.platformName
          .toUpperCase()
          .compareTo(b.device.platformName.toUpperCase()));

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
                                    Text(r.device.platformName,
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
