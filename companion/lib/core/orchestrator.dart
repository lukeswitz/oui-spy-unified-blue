import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/db/app_database.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/engine.dart';

/// Tracks live state of a mesh peer node.
class PeerNodeState {
  PeerNodeState({
    required this.nodeId,
    this.name,
    this.activeEngineMask = 0,
    this.engineStates = const [],
    this.detectionCount = 0,
    this.wifiCount = 0,
    this.bleCount = 0,
    this.uptimeSec = 0,
    this.freeHeapKb = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String nodeId;
  String? name;
  int activeEngineMask;
  List<EngineState> engineStates;
  int detectionCount;
  int wifiCount;
  int bleCount;
  int uptimeSec;
  int freeHeapKb;
  DateTime lastSeen;

  bool get isStale => DateTime.now().difference(lastSeen).inSeconds > 15;

  bool isEngineActive(Engine engine) =>
      (activeEngineMask & (1 << engine.index)) != 0;
}

/// Node orchestrator — coordinates scanning across mesh peers.
///
/// Responsibilities:
/// - Track peer node health/state from status heartbeats
/// - Sync engine enable/disable to all peers
/// - Apply channel splitting for wardrive coverage maximization
class Orchestrator extends ChangeNotifier {
  Orchestrator({required BleManager ble, required AppDatabase db})
      : _ble = ble,
        _db = db {
    _sub = _ble.peerStatusUpdates.listen(_onPeerStatus);
    _resolveNodeNames();
  }

  final BleManager _ble;
  final AppDatabase _db;
  StreamSubscription<PeerNodeStatus>? _sub;

  final Map<String, PeerNodeState> peers = {};

  // --- Public API ---

  /// Number of non-stale peers running a specific engine.
  int nodesRunningEngine(Engine engine) {
    int count = 0;
    for (final peer in peers.values) {
      if (!peer.isStale && peer.isEngineActive(engine)) count++;
    }
    return count;
  }

  /// All active (non-stale) peers.
  List<PeerNodeState> get activePeers =>
      peers.values.where((p) => !p.isStale).toList();

  /// Total active node count (peers only, not self).
  int get activeNodeCount => activePeers.length;

  /// Map of nodeId -> detection count for UI display.
  Map<String, int> get nodeDetectionCounts =>
      {for (final p in peers.entries) p.key: p.value.detectionCount};

  /// Record a detection from a peer node, incrementing WiFi/BLE counts.
  void recordPeerDetection(String sourceNodeId, {required bool isBle}) {
    final peer = peers[sourceNodeId];
    if (peer == null) return;
    if (isBle) {
      peer.bleCount++;
    } else {
      peer.wifiCount++;
    }
  }

  /// Sync engine enable to all peers via orchestration relay.
  Future<void> syncEngineEnable(Engine engine, {Uint8List? config}) async {
    await _ble.sendOrchestrationCommand(
      command: 0x01,
      engineId: engine.index,
      payload: config,
    );
    DebugLog.log('Orchestrator: sync enable ${engine.label} to peers');
  }

  /// Sync engine disable to all peers.
  Future<void> syncEngineDisable(Engine engine) async {
    await _ble.sendOrchestrationCommand(
      command: 0x00,
      engineId: engine.index,
    );
    DebugLog.log('Orchestrator: sync disable ${engine.label} to peers');
  }

  /// Sync disable-all to all peers.
  Future<void> syncDisableAll() async {
    await _ble.sendOrchestrationCommand(
      command: 0x0F,
      engineId: 0,
    );
    DebugLog.log('Orchestrator: sync disable-all to peers');
  }

  /// Apply channel split for wardrive across all active nodes.
  /// Sends config commands to peers with their assigned channel ranges.
  Future<void> applyChannelSplit() async {
    final nodeCount = activeNodeCount + 1; // +1 for self
    if (nodeCount <= 1) return; // No peers, no split needed

    const totalChannels = 14;
    final chPerNode = totalChannels ~/ nodeCount;
    final remainder = totalChannels % nodeCount;

    // Self gets first range (handled locally by app when starting wardrive)
    // Peers get subsequent ranges
    int chStart = 1 + chPerNode + (remainder > 0 ? 1 : 0);

    int peerIdx = 1;
    for (final peer in activePeers) {
      final extra = peerIdx < remainder ? 1 : 0;
      final rangeSize = chPerNode + extra;
      final chEnd = (chStart + rangeSize - 1).clamp(1, 14);

      // Send wardrive config with channel range (bytes 9-10 in wardrive config)
      // Full wardrive config: radio[1] wifi_interval[2] wifi_dwell[2] ble_dur[2] ble_interval[2] ch_start[1] ch_end[1]
      final payload = Uint8List(11);
      payload[0] = 0x03; // both radios
      payload[1] = 0xB0; payload[2] = 0x04; // 1200ms wifi interval
      payload[3] = 0xFA; payload[4] = 0x00; // 250ms dwell
      payload[5] = 0xDC; payload[6] = 0x05; // 1500ms BLE
      payload[7] = 0xD0; payload[8] = 0x07; // 2000ms BLE interval
      payload[9] = chStart;
      payload[10] = chEnd;

      await _ble.sendOrchestrationCommand(
        command: 0x10, // config
        engineId: Engine.wardrive.index,
        payload: payload,
      );

      DebugLog.log('Orchestrator: peer ${peer.nodeId} channels $chStart-$chEnd');
      chStart = chEnd + 1;
      peerIdx++;
    }
  }

  /// Get the local node's channel range when channel split is active.
  ({int start, int end}) getLocalChannelRange() {
    final nodeCount = activeNodeCount + 1;
    if (nodeCount <= 1) return (start: 1, end: 14);

    const totalChannels = 14;
    final chPerNode = totalChannels ~/ nodeCount;
    final remainder = totalChannels % nodeCount;
    final localEnd = chPerNode + (remainder > 0 ? 1 : 0);
    return (start: 1, end: localEnd);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // --- Private ---

  void _onPeerStatus(PeerNodeStatus status) {
    final existing = peers[status.nodeId];
    if (existing != null) {
      existing.activeEngineMask = status.activeEngineMask;
      existing.engineStates = status.engineStates;
      existing.detectionCount = status.detectionCount;
      existing.uptimeSec = status.uptimeSec;
      existing.freeHeapKb = status.freeHeapKb;
      existing.lastSeen = DateTime.now();
    } else {
      peers[status.nodeId] = PeerNodeState(
        nodeId: status.nodeId,
        activeEngineMask: status.activeEngineMask,
        engineStates: status.engineStates,
        detectionCount: status.detectionCount,
        uptimeSec: status.uptimeSec,
        freeHeapKb: status.freeHeapKb,
      );
      _resolveNodeNames();
    }
    notifyListeners();
  }

  Future<void> _resolveNodeNames() async {
    try {
      final nodes = await _db.getAllNodes();
      final connectedId = _ble.connectedDeviceId;
      for (final node in nodes) {
        if (node.id == connectedId) continue;
        // Match by last 4 hex chars of MAC (same as firmware node ID derivation)
        final macClean = node.macAddress.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        if (macClean.length >= 4) {
          final derivedId = macClean.substring(macClean.length - 4).toUpperCase();
          final peer = peers[derivedId];
          if (peer != null) {
            peer.name = node.name;
          }
        }
      }
    } catch (_) {
      // DB not ready yet, names will resolve on next status
    }
  }
}

/// Riverpod provider for the node orchestrator.
final orchestratorProvider = ChangeNotifierProvider<Orchestrator>((ref) {
  final ble = ref.read(bleManagerProvider);
  final db = ref.read(databaseProvider);
  return Orchestrator(ble: ble, db: db);
});
