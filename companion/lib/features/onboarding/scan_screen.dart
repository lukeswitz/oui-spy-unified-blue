import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_permissions.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/link/link_net.dart';
import 'package:oui_spy/core/link/usb_autoconnect.dart';
import 'package:oui_spy/core/link/usb_serial.dart';
import 'package:oui_spy/features/config/device_config.dart' show boardDisplayName;
import 'package:oui_spy/theme/app_theme.dart';
import 'package:oui_spy/widgets/d/d_header.dart';
import 'package:oui_spy/widgets/info_sheet.dart';
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
  StreamSubscription<List<UsbSerialDevice>>? _usbSub;
  StreamSubscription<NetLinkTarget?>? _netSub;
  List<UsbSerialDevice> _usb = const [];
  NetLinkTarget? _net;
  String? _rememberedMgrId;
  List<({String id, String name})> _paired = const [];
  Map<String, String> _pairedNodes = const {};

  Future<void> _loadPaired() async {
    try {
      final paired = await BleManager.pairedBoards();
      final nodes = await BleManager.pairedNodeIds();
      if (mounted) {
        setState(() {
          _paired = paired;
          _pairedNodes = nodes;
        });
      }
    } on Exception catch (e) {
      DebugLog.log('SCAN: paired boards: $e');
    }
  }

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
    _loadRememberedManager();
    _loadPaired();
    final usb = ref.read(usbAutoConnectProvider);
    _usb = usb.attached;
    _usbSub = usb.devices.listen((d) {
      if (mounted) setState(() => _usb = d);
    });
    _net = usb.netTarget;
    _netSub = usb.netTargets.listen((n) {
      if (mounted) setState(() => _net = n);
    });
    usb.refresh();
    _connSub = ble.connectionState.listen((state) {
      if (!mounted) return;
      if (state == NodeConnectionState.ready) {
        context.go('/home');
      } else {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startScan();
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _usbSub?.cancel();
    _netSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan({bool user = false}) async {
    if (_scanning) return;
    final ble = ref.read(bleManagerProvider);
    final pending = ble.isLinkSetup ||
        ble.currentConnectionState == NodeConnectionState.reconnecting;
    if (pending) {
      if (!user) return;
      DebugLog.log('SCAN: user scan stops the pending connection to ${ble.targetDeviceId}');
      await ble.disconnect();
      if (!mounted) return;
    }

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
      if (!ble.isConnected) return;
      DebugLog.log('SCAN: connected to ${result.device.platformName}');
      if (mounted) context.go('/home');
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('SCAN: connect failed: ${e.description}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: ${e.description}'), backgroundColor: AppTheme.error),
        );
        unawaited(_startScan());
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

  Future<void> _connectUsb(UsbSerialDevice device) => _connectLink(device.id, device.vidPid,
      () => ref.read(usbAutoConnectProvider).connect(device, replaceBle: true));

  Future<void> _connectNet(NetLinkTarget target) => _connectLink(target.label, target.label,
      () => ref.read(usbAutoConnectProvider).connectNet(target, replaceBle: true));

  Future<void> _confirmForget(({String id, String name}) b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Forget ${b.name}?'),
        content: const Text('This phone must pair again. Restart the board first, because it only accepts a new pairing for 2 minutes after power-on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget')),
        ],
      ),
    );
    if (ok != true) return;
    final ble = ref.read(bleManagerProvider);
    if (ble.targetDeviceId == b.id) {
      DebugLog.log('SCAN: forgetting ${b.id} stops its pending connection');
      await ble.disconnect();
    }
    try {
      await BleManager.forgetPaired(b.id);
    } on Exception catch (e) {
      DebugLog.log('SCAN: forget paired: $e');
    }
    await _loadPaired();
  }

  Future<void> _connectPaired(({String id, String name}) b) => _connectLink(
      b.id,
      b.name,
      () => ref.read(bleManagerProvider).connectByIdAndReady(b.id, autoConnect: true),
      failure: '${b.name} did not connect. Restart the board and try again.');

  Future<void> _connectLink(String id, String what, Future<bool> Function() connect, {String? failure}) async {
    if (_connecting) return;
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
    final ble = ref.read(bleManagerProvider);
    if (ble.isConnected && ble.targetDeviceId != id) await ble.disconnect();
    final ok = await connect();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connectingId = null;
      _scanning = false;
    });
    if (ok) {
      context.go('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failure ?? 'USB connection to $what failed. Check the board runs OUI-SPY firmware with USB support.'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  Widget _usbTile(UsbSerialDevice d, ResolvedTheme t) => _linkTile(t,
      id: d.id,
      title: d.name.isNotEmpty ? d.name : 'USB serial device',
      subtitle: 'USB  ${d.vidPid}',
      onTap: () => _connectUsb(d));

  Widget _netTile(NetLinkTarget n, ResolvedTheme t) => _linkTile(t,
      id: n.label,
      title: 'OUI-SPY over USB',
      subtitle: 'USB ETHERNET  ${n.label}',
      onTap: () => _connectNet(n));

  Widget _linkTile(ResolvedTheme t,
      {required String id,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
      IconData icon = Icons.usb,
      bool active = false,
      String busyLabel = 'CONNECTING OVER USB...'}) {
    final busy = _connecting && _connectingId == id;
    return GestureDetector(
      onTap: _connecting ? null : onTap,
      onLongPress: _connecting ? null : onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: busy || active ? AppTheme.accent : t.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.surfaceLight,
              ),
              child: busy
                  ? Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)))
                  : Icon(icon, color: AppTheme.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppTheme.mono),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    busy ? busyLabel : subtitle,
                    style: TextStyle(color: busy ? AppTheme.accent : t.textDim, fontSize: 10, fontFamily: AppTheme.mono),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                'allow Nearby devices / Location for OUI-APEX, then tap SCAN again.'
            : 'OUI-APEX needs Bluetooth scanning permission to find your node. '
                'Tap SCAN again and allow it.';
    final String actionLabel =
        servicesOff ? 'ENABLE LOCATION' : 'OPEN SETTINGS';
    final bool showAction = servicesOff || permanently;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
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
    final pairedIds = {for (final b in _paired) b.id};
    final sorted = filtered.where((r) => !pairedIds.contains(r.device.remoteId.toString())).toList()
      ..sort((a, b) => displayName(a).compareTo(displayName(b)));
    final ble = ref.read(bleManagerProvider);
    final liveId = ble.currentConnectionState == NodeConnectionState.ready ? ble.targetDeviceId : null;
    final otherPaired = _paired.where((b) => b.id != liveId).toList();

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('CONNECT'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showInfoSheet(context, t, 'Pairing', const [
              'A new board is listed under Found until a phone pairs with it. Tap it and accept the pairing prompt from your phone.',
              'A paired board is listed under Paired. It then advertises no name or service, only a private address that keeps changing, and refuses phones it does not know.',
              'To pair another phone, restart the board. It accepts a new phone for 2 minutes after power-on, or until a phone connects.',
              'Press and hold a paired board to forget it.',
            ]),
          ),
        ],
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
                  border: Border.all(color: AppTheme.error),
                ),
                child: Text(_error!, style: TextStyle(color: AppTheme.error, fontSize: 11, fontFamily: AppTheme.mono)),
              ),
            ),

          if (liveId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CONNECTED', style: TextStyle(color: t.textDim, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: AppTheme.mono)),
                  const SizedBox(height: 8),
                  _linkTile(t,
                      id: liveId,
                      title: ref.watch(appStateProvider).labelForNode(ble.nodeId),
                      subtitle: '${boardDisplayName(ble.board)} · $liveId',
                      icon: Icons.bluetooth_connected,
                      active: true,
                      onTap: () => context.go('/home'),
                      onLongPress: () => _confirmForget((id: liveId, name: ref.read(appStateProvider).labelForNode(ble.nodeId)))),
                ],
              ),
            ),

          if (_usb.isNotEmpty || _net != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('USB', style: TextStyle(color: t.textDim, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: AppTheme.mono)),
                  const SizedBox(height: 8),
                  for (final d in _usb) _usbTile(d, t),
                  if (_net != null) _netTile(_net!, t),
                ],
              ),
            ),

          if (otherPaired.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PAIRED', style: TextStyle(color: t.textDim, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: AppTheme.mono)),
                  const SizedBox(height: 8),
                  for (final b in otherPaired)
                    _linkTile(t,
                        id: b.id,
                        title: switch (_pairedNodes[b.id]) {
                          final n? => ref.watch(appStateProvider).labelForNode(n),
                          null => b.name,
                        },
                        subtitle: _pairedNodes.containsKey(b.id) ? b.id : 'Not identified yet · ${b.id}',
                        icon: Icons.bluetooth_connected,
                        busyLabel: 'CONNECTING...',
                        onTap: () => _connectPaired(b),
                        onLongPress: () => _confirmForget(b)),
                ],
              ),
            ),

          if (sorted.isEmpty) ...[
            const Spacer(),
            _ScanRadar(active: _scanning),
            const SizedBox(height: 24),
            const DPageTitle('OUI-APEX'),
            const SizedBox(height: 8),
            DEyebrow(_scanning ? 'Searching for nodes...' : 'Scan for nearby nodes to connect'),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _scanning ? null : () => _startScan(user: true),
              child: Text(_scanning ? 'SCANNING...' : 'Scan for devices'),
            ),
            const Spacer(flex: 2),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    '${sorted.length} FOUND',
                    style: TextStyle(color: t.textDim, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: AppTheme.mono),
                  ),
                  const Spacer(),
                  if (!_scanning)
                    GestureDetector(
                      onTap: () => _startScan(user: true),
                      child: Text('RESCAN', style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8, fontFamily: AppTheme.mono)),
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
                        color: t.surface,
                        border: Border.all(
                          color: isThisConnecting
                              ? AppTheme.accent
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
                              color: t.surfaceLight,
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
                                  fontFamily: AppTheme.mono,
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
                                        border: Border.all(color: AppTheme.accent),
                                      ),
                                      child: Text('MGR', style: TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                                    ),
                                  Text(
                                    isThisConnecting ? 'CONNECTING...' : id,
                                    style: TextStyle(
                                      color: isThisConnecting ? AppTheme.accent : t.textDim,
                                      fontSize: 10,
                                      fontFamily: AppTheme.mono,
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
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15 + v * 0.15)),
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1 + v * 0.1)),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                color: AppTheme.accent,
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
          color: i < bars ? color : t.border,
        );
      }),
    );
  }
}
