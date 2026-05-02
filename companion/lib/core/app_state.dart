import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/models/node.dart';

/// App-wide state that survives navigation. Single source of truth.
/// All screens read from here instead of creating their own subscriptions.
class AppState extends ChangeNotifier {
  AppState(this._ble, this._gps) {
    _init();
  }

  final BleManager _ble;
  final GpsProvider _gps;
  final List<StreamSubscription<dynamic>> _subs = [];

  // Connection
  NodeConnectionState connectionState = NodeConnectionState.disconnected;
  bool get isConnected => connectionState == NodeConnectionState.ready;
  String nodeId = '';

  // Engine states
  int availableEngines = 0;
  int activeEngines = 0;
  List<EngineState> engineStates = List.filled(Engine.values.length, EngineState.disabled);

  // Detection counts per engine — unique MACs, not raw event count
  final Map<Engine, Set<String>> _uniqueMacsPerEngine = {};
  int get totalDetections => _uniqueMacsPerEngine.values.fold(0, (a, b) => a + b.length);

  // Recent detections ring buffer (feed), deduped by MAC+engine
  final List<Detection> recentDetections = [];
  final Map<String, int> _dedupeIndex = {}; // "mac|engine" → index in list
  static const int maxRecentDetections = 500;

  // Foxhunter
  int foxhunterRssi = -100;
  int foxhunterIntervalMs = 3000;

  // Mesh
  bool meshEnabled = false;
  bool meshEncryption = true;
  int meshPeerCount = 0;
  int meshConnectedPeers = 0;
  int meshRxCount = 0;
  int meshTxCount = 0;
  Uint8List? _meshKey;

  Set<String> get meshSourceNodes {
    final nodes = <String>{};
    for (final d in recentDetections) {
      if (d.sourceNodeId.isNotEmpty) nodes.add(d.sourceNodeId);
    }
    return nodes;
  }

  void _init() {
    // Connection state
    connectionState = _ble.currentConnectionState;

    _subs.add(_ble.connectionState.listen((state) {
      connectionState = state;
      if (state == NodeConnectionState.ready) {
        nodeId = _ble.nodeId;
        _gps.start();
      }
      notifyListeners();
    }));

    // Engine states
    _subs.add(_ble.engineStates.listen((status) {
      availableEngines = status.available;
      activeEngines = status.active;
      engineStates = List.from(status.states);
      while (engineStates.length < Engine.values.length) {
        engineStates.add(EngineState.disabled);
      }
      notifyListeners();
    }));

    // Detections — track unique MACs per engine + deduplicated ring buffer
    _subs.add(_ble.detections.listen((det) {
      (_uniqueMacsPerEngine[det.engine] ??= {}).add(det.macAddress);
      _upsertDetection(det);
      notifyListeners();
    }));

    // Foxhunter RSSI
    _subs.add(_ble.foxhunterRssi.listen((data) {
      foxhunterRssi = data.rssi;
      foxhunterIntervalMs = data.intervalMs;
      notifyListeners();
    }));

    // Mesh status
    _subs.add(_ble.meshStatusUpdates.listen((data) {
      meshEnabled = data.enabled;
      meshPeerCount = data.peerCount;
      meshConnectedPeers = data.connectedPeers;
      meshRxCount = data.rxCount;
      meshTxCount = data.txCount;
      notifyListeners();
    }));

    DebugLog.log('AppState: initialized');
  }

  bool isEngineActive(Engine engine) {
    return (activeEngines & engine.bitmask) != 0;
  }

  EngineState getEngineState(Engine engine) {
    return engine.index < engineStates.length
        ? engineStates[engine.index]
        : EngineState.disabled;
  }

  int countForEngine(Engine engine) => _uniqueMacsPerEngine[engine]?.length ?? 0;

  List<Detection> detectionsForEngine(Engine engine) {
    return recentDetections.where((d) => d.engine == engine).toList();
  }


  void _upsertDetection(Detection det) {
    final key = '${det.macAddress}|${det.engine.name}';
    final existingIdx = _dedupeIndex[key];

    if (existingIdx != null && existingIdx < recentDetections.length) {
      final existing = recentDetections[existingIdx];
      // Merge: keep strongest RSSI, latest timestamp, accumulate count
      final merged = det.copyWith(
        count: existing.count + 1,
        rssi: det.rssi > existing.rssi ? det.rssi : existing.rssi,
      );
      recentDetections.removeAt(existingIdx);
      for (final entry in _dedupeIndex.entries) {
        if (entry.value > existingIdx) {
          _dedupeIndex[entry.key] = entry.value - 1;
        }
      }
      // Insert at front
      recentDetections.insert(0, merged);
      // Update all indices (shifted right by 1)
      for (final entry in _dedupeIndex.entries) {
        if (entry.key != key) {
          _dedupeIndex[entry.key] = entry.value + 1;
        }
      }
      _dedupeIndex[key] = 0;
    } else {
      // New entry
      recentDetections.insert(0, det);
      // Shift all existing indices
      for (final entry in _dedupeIndex.entries) {
        _dedupeIndex[entry.key] = entry.value + 1;
      }
      _dedupeIndex[key] = 0;

      // Evict oldest if over capacity
      if (recentDetections.length > maxRecentDetections) {
        final removed = recentDetections.removeLast();
        final removedKey = '${removed.macAddress}|${removed.engine.name}';
        _dedupeIndex.remove(removedKey);
      }
    }
  }

  Future<void> enableMesh({
    required bool encryption,
    required List<Uint8List> peerMacs,
  }) async {
    if (_meshKey == null || _meshKey!.length != 32) {
      await generateMeshKey();
    }
    meshEncryption = encryption;
    meshEnabled = true;
    await _ble.writeMeshConfig(
      enabled: true,
      encryption: encryption,
      key: _meshKey!,
      peerMacs: peerMacs,
    );
    notifyListeners();
    DebugLog.log('AppState: mesh enabled, peers=${peerMacs.length}');
  }

  Future<void> disableMesh() async {
    meshEnabled = false;
    await _ble.writeMeshConfig(
      enabled: false,
      encryption: false,
      key: Uint8List(32),
      peerMacs: [],
    );
    notifyListeners();
    DebugLog.log('AppState: mesh disabled');
  }

  Future<void> generateMeshKey() async {
    final rng = Random.secure();
    _meshKey = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'mesh_encryption_key',
      value: _meshKey!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    DebugLog.log('AppState: new mesh key generated');
  }

  Future<void> loadMeshKey() async {
    const storage = FlutterSecureStorage();
    final hex = await storage.read(key: 'mesh_encryption_key');
    if (hex != null && hex.length == 64) {
      _meshKey = Uint8List.fromList(
        List.generate(32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
      );
    }
  }

  Uint8List? get meshKey => _meshKey;

  List<Detection> detectionsForNode(String sourceNodeId) {
    return recentDetections.where((d) => d.sourceNodeId == sourceNodeId).toList();
  }

  void resetCounts() {
    _uniqueMacsPerEngine.clear();
    recentDetections.clear();
    _dedupeIndex.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}

final appStateProvider = ChangeNotifierProvider<AppState>((ref) {
  final ble = ref.watch(bleManagerProvider);
  final gps = ref.watch(gpsProvider);
  return AppState(ble, gps);
});
