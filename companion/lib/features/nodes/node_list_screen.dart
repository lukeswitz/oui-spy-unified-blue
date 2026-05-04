import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/theme/app_theme.dart';

class NodeListScreen extends ConsumerStatefulWidget {
  const NodeListScreen({super.key});

  @override
  ConsumerState<NodeListScreen> createState() => _NodeListScreenState();
}

class _NodeListScreenState extends ConsumerState<NodeListScreen> {
  List<Node> _nodes = [];
  final Map<String, ScanResult> _scanResults = {};
  bool _scanning = false;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<Node>>? _nodesSub;

  @override
  void initState() {
    super.initState();
    final db = ref.read(databaseProvider);
    _nodesSub = db.watchAllNodes().listen((nodes) {
      if (mounted) setState(() => _nodes = nodes);
    });
  }

  @override
  void dispose() {
    _nodesSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _loadNodes() async {
    final db = ref.read(databaseProvider);
    final nodes = await db.getAllNodes();
    if (mounted) setState(() => _nodes = nodes);
  }

  void _startScan() {
    _scanResults.clear();
    setState(() => _scanning = true);

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!mounted) return;
      final connectedId = ref.read(bleManagerProvider).connectedDeviceId;
      setState(() {
        for (final r in results) {
          final name = r.device.platformName.toUpperCase();
          if (name.contains('OUI') || name.contains('SPY')) {
            final id = r.device.remoteId.toString();
            if (id != connectedId && !_nodes.any((n) => n.id == id)) {
              _scanResults[id] = r;
            }
          }
        }
      });
    });

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: true,
    ).whenComplete(() {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _addNode(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    final db = ref.read(databaseProvider);
    final device = result.device;
    final name = device.platformName.isNotEmpty ? device.platformName : 'OUI-SPY Node';

    await db.upsertNode(NodesCompanion(
      id: drift.Value(device.remoteId.toString()),
      name: drift.Value(name),
      macAddress: drift.Value(device.remoteId.toString()),
      lastSeen: drift.Value(DateTime.now().millisecondsSinceEpoch),
      createdAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
    ));

    DebugLog.log('NODE: added $name');
    _scanResults.remove(device.remoteId.toString());
    _loadNodes();
  }

  Future<void> _toggleNodeMesh(bool enabled) async {
    final appState = ref.read(appStateProvider);
    try {
      if (enabled) {
        final db = ref.read(databaseProvider);
        final nodes = await db.getAllNodes();
        final ble = ref.read(bleManagerProvider);
        final connectedId = ble.connectedDeviceId;
        final peerNodes = nodes.where((n) => n.id != connectedId).toList();

        final peerMacs = peerNodes.map((n) {
          return BleProtocol.parseMacToBytes(n.macAddress);
        }).toList();

        await appState.enableMesh(
          encryption: appState.meshEncryption,
          peerMacs: peerMacs,
        );
      } else {
        await appState.disableMesh();
      }
    } catch (e) {
      DebugLog.log('Mesh toggle error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mesh error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _renameNode(Node node) async {
    final t = AppTheme.of(context);
    final controller = TextEditingController(text: node.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Rename Node', style: TextStyle(color: t.textPrimary)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: t.textPrimary),
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final db = ref.read(databaseProvider);
      await db.updateNodeName(node.id, result);
      _loadNodes();
    }
  }

  Future<void> _deleteNode(Node node) async {
    final t = AppTheme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Remove Node', style: TextStyle(color: t.textPrimary)),
        content: Text('Remove ${node.name}?', style: TextStyle(color: t.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(databaseProvider);
      await db.deleteNode(node.id);
      _loadNodes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final ble = ref.read(bleManagerProvider);
    final connectedId = ble.connectedDeviceId;
    final appState = ref.watch(appStateProvider);

    final visibleNodes = _nodes.where((n) => n.id != connectedId).toList();

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('NODES')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mesh toggle — always visible when connected
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _Label('MESH NETWORK'),
              Row(
                children: [
                  Text(
                    appState.meshEnabled ? 'ACTIVE' : 'OFF',
                    style: TextStyle(
                      color: appState.meshEnabled ? AppTheme.accent : t.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: appState.meshEnabled,
                      onChanged: _toggleNodeMesh,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (appState.meshEnabled) ...[
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub, color: AppTheme.accent, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${appState.meshPeerCount} peers \u2022 '
                      'RX:${appState.meshRxCount} TX:${appState.meshTxCount}',
                      style: const TextStyle(
                        color: AppTheme.accent, fontSize: 11, fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (visibleNodes.isNotEmpty) ...[
            const _Label('SAVED NODES'),
            const SizedBox(height: 8),
            ...visibleNodes.map((n) => _NodeTile(
              node: n,
              isActive: appState.meshEnabled,
              onRename: () => _renameNode(n),
              onDelete: () => _deleteNode(n),
            )),
            const SizedBox(height: 24),
          ],

          const _Label('ADD NODE'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _scanning ? null : _startScan,
              child: Text(_scanning ? 'SCANNING...' : 'SCAN FOR NEW NODES'),
            ),
          ),
          if (_scanning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(color: AppTheme.accent, backgroundColor: t.border),
          ],
          if (_scanResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._scanResults.values.map((r) => _DiscoveredTile(
              result: r,
              onAdd: () => _addNode(r),
            )),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Text(text, style: TextStyle(
      color: t.textDim, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2,
    ));
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({required this.node, required this.isActive, required this.onRename, required this.onDelete});
  final Node node;
  final bool isActive;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.accent.withValues(alpha: 0.08) : t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? AppTheme.accent.withValues(alpha: 0.5) : t.border,
          width: isActive ? 1 : 0.5,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          isActive ? Icons.hub : Icons.bluetooth,
          color: isActive ? AppTheme.accent : t.textDim,
          size: 20,
        ),
        title: Text(node.name, style: TextStyle(
          color: isActive ? AppTheme.accent : t.textPrimary, fontSize: 14,
        )),
        subtitle: Text(
          isActive ? 'Mesh peer' : 'Last seen: ${_timeAgo(node.lastSeen)}',
          style: TextStyle(
            color: isActive ? AppTheme.success : t.textDim, fontSize: 11,
          ),
        ),
        trailing: PopupMenuButton<String>(
          color: t.surface,
          onSelected: (v) {
            if (v == 'rename') onRename();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: t.textPrimary))),
            const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      ),
    );
  }

  String _timeAgo(int? ms) {
    if (ms == null) return 'never';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.result, required this.onAdd});
  final ScanResult result;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, color: AppTheme.success, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.device.platformName, style: const TextStyle(color: AppTheme.success, fontSize: 14, fontWeight: FontWeight.w600)),
              Text(result.device.remoteId.toString(), style: TextStyle(color: t.textDim, fontSize: 11, fontFamily: 'monospace')),
            ],
          )),
          Text('${result.rssi} dBm', style: TextStyle(color: t.textDim, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('ADD', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
