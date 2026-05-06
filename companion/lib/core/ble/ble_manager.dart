import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
/// BLE connection state.
enum NodeConnectionState {
  disconnected,
  scanning,
  connecting,
  negotiating,
  syncing,
  ready,
  reconnecting,
}

/// Central BLE manager. Handles scanning, connection, GATT operations,
/// and detection stream from the OUI-SPY device.
class BleManager {
  BleManager();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _engineControl;
  BluetoothCharacteristic? _detectionEvents;
  BluetoothCharacteristic? _deviceStatus;
  BluetoothCharacteristic? _gpsReceive;
  BluetoothCharacteristic? _hardwareConfig;
  BluetoothCharacteristic? _alertConfig;
  BluetoothCharacteristic? _foxhunterRssi;
  BluetoothCharacteristic? _skySpyTelemetry;
  BluetoothCharacteristic? _unipwnDevices;
  BluetoothCharacteristic? _unipwnCommand;
  BluetoothCharacteristic? _foxhunterConfig;
  BluetoothCharacteristic? _meshConfig;
  BluetoothCharacteristic? _meshStatus;
  BluetoothCharacteristic? _orchestration;

  final _connectionState = StreamController<NodeConnectionState>.broadcast();
  final _detections = StreamController<Detection>.broadcast();
  final _foxhunterRssiStream = StreamController<({int rssi, int intervalMs})>.broadcast();
  final _engineStates = StreamController<({int available, int active, List<EngineState> states})>.broadcast();
  final _meshStatusStream = StreamController<({bool enabled, int peerCount, int connectedPeers, int rxCount, int txCount})>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  int _mtu = 23;
  String _sessionId = '';
  String _nodeId = '';
  String? _lastDeviceId;
  String? _primaryDeviceId;

  // -- Public streams --

  Stream<NodeConnectionState> get connectionState => _connectionState.stream;
  Stream<Detection> get detections => _detections.stream;
  Stream<({int rssi, int intervalMs})> get foxhunterRssi => _foxhunterRssiStream.stream;
  Stream<({int available, int active, List<EngineState> states})> get engineStates =>
      _engineStates.stream;
  Stream<({bool enabled, int peerCount, int connectedPeers, int rxCount, int txCount})> get meshStatusUpdates =>
      _meshStatusStream.stream;

  NodeConnectionState _currentState = NodeConnectionState.disconnected;

  bool get isConnected =>
      _currentState == NodeConnectionState.ready ||
      (_device?.isConnected ?? false);

  NodeConnectionState get currentConnectionState => _currentState;
  String get nodeId => _nodeId;
  String? get connectedDeviceId => _primaryDeviceId;

  void markAsPrimary() {
    _primaryDeviceId = _lastDeviceId;
  }

  /// Get a discovered characteristic by UUID (for direct read/write).
  BluetoothCharacteristic? getCharacteristic(Guid uuid) {
    if (uuid == GattUuids.engineControl) return _engineControl;
    if (uuid == GattUuids.detectionEvents) return _detectionEvents;
    if (uuid == GattUuids.deviceStatus) return _deviceStatus;
    if (uuid == GattUuids.gpsReceive) return _gpsReceive;
    if (uuid == GattUuids.hardwareConfig) return _hardwareConfig;
    if (uuid == GattUuids.alertConfig) return _alertConfig;
    if (uuid == GattUuids.foxhunterRssi) return _foxhunterRssi;
    if (uuid == GattUuids.foxhunterConfig) return _foxhunterConfig;
    if (uuid == GattUuids.meshConfig) return _meshConfig;
    if (uuid == GattUuids.meshStatus) return _meshStatus;
    if (uuid == GattUuids.deviceInfo) return _deviceInfoChar;
    return null;
  }

  BluetoothCharacteristic? _deviceInfoChar;

  // -- GPS state for stamping detections --

  double? _lastLat;
  double? _lastLon;
  double? _lastAccuracy;
  int? _lastSatCount;

  void updateGps({
    required double latitude,
    required double longitude,
    double? accuracy,
    int? satelliteCount,
  }) {
    _lastLat = latitude;
    _lastLon = longitude;
    _lastAccuracy = accuracy;
    _lastSatCount = satelliteCount;
  }

  // -- Scanning --

  /// Scan for OUI-SPY devices. Results arrive on FlutterBluePlus.onScanResults.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    // Ensure BLE adapter is on
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }

    // Scan with no filters — macOS CoreBluetooth doesn't reliably
    // expose service UUIDs or names in advertisements.
    // UI filters results to show OUI-SPY devices.
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  /// Stream of scan results (list updated each scan cycle).
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.onScanResults;

  Future<void> stopScan() async => FlutterBluePlus.stopScan();

  // -- Connection --

  /// Connect to a specific device and set up GATT subscriptions.
  Future<void> connect(BluetoothDevice device, {required String sessionId}) async {
    // Clean up previous subscriptions to prevent reconnect storm
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _reconnectTimer?.cancel();

    _sessionId = sessionId;
    _device = device;
    _currentState = NodeConnectionState.connecting; _connectionState.add(NodeConnectionState.connecting);

    _lastDeviceId = device.remoteId.toString();
    DebugLog.log('BLE: connecting to ${device.remoteId}');
    await device.connect(
      autoConnect: false,
      timeout: const Duration(seconds: 15),
    );
    DebugLog.log('BLE: connected');

    // Listen for disconnection
    _subscriptions.add(
      device.connectionState.listen((state) {
        DebugLog.log('BLE: connectionState=$state');
        if (state == BluetoothConnectionState.disconnected) {
          _currentState = NodeConnectionState.disconnected; _connectionState.add(NodeConnectionState.disconnected);
          _startReconnect();
        }
      }),
    );

    _currentState = NodeConnectionState.negotiating; _connectionState.add(NodeConnectionState.negotiating);

    // Negotiate MTU (Android only — macOS/iOS handle automatically)
    try {
      _mtu = await device.requestMtu(512);
      DebugLog.log('BLE: MTU=$_mtu');
    } catch (e) {
      DebugLog.log('BLE: MTU request skipped (platform handles): $e');
      _mtu = 23;
    }

    // Discover services
    _currentState = NodeConnectionState.syncing; _connectionState.add(NodeConnectionState.syncing);
    DebugLog.log('BLE: discovering services...');
    final services = await device.discoverServices();

    for (final s in services) {
      DebugLog.log('BLE: service=${s.uuid} chars=${s.characteristics.length}');
      for (final c in s.characteristics) {
        DebugLog.log('  char=${c.uuid} props=${c.properties}');
      }
    }

    final ouiService = services.firstWhere(
      (s) => s.uuid == GattUuids.service,
      orElse: () {
        final msg = 'OUI-SPY service not found. Expected=${GattUuids.service} '
            'Found=${services.map((s) => s.uuid.toString()).join(", ")}';
        DebugLog.log('BLE: ERROR $msg');
        throw Exception(msg);
      },
    );
    DebugLog.log('BLE: OUI-SPY service found');

    // Map characteristics
    for (final c in ouiService.characteristics) {
      if (c.uuid == GattUuids.engineControl) _engineControl = c;
      if (c.uuid == GattUuids.detectionEvents) _detectionEvents = c;
      if (c.uuid == GattUuids.deviceStatus) _deviceStatus = c;
      if (c.uuid == GattUuids.gpsReceive) _gpsReceive = c;
      if (c.uuid == GattUuids.hardwareConfig) _hardwareConfig = c;
      if (c.uuid == GattUuids.alertConfig) _alertConfig = c;
      if (c.uuid == GattUuids.foxhunterRssi) _foxhunterRssi = c;
      if (c.uuid == GattUuids.skySpyTelemetry) _skySpyTelemetry = c;
      if (c.uuid == GattUuids.unipwnDevices) _unipwnDevices = c;
      if (c.uuid == GattUuids.unipwnCommand) _unipwnCommand = c;
      if (c.uuid == GattUuids.foxhunterConfig) _foxhunterConfig = c;
      if (c.uuid == GattUuids.meshConfig) _meshConfig = c;
      if (c.uuid == GattUuids.meshStatus) _meshStatus = c;
      if (c.uuid == GattUuids.orchestration) _orchestration = c;
    }

    // Read device info to get node ID
    _deviceInfoChar = ouiService.characteristics.firstWhere(
      (c) => c.uuid == GattUuids.deviceInfo,
    );
    final infoData = await _deviceInfoChar!.read();
    _nodeId = _extractNodeId(infoData);
    DebugLog.log('BLE: nodeId=$_nodeId');

    // Subscribe to detection notifications
    if (_detectionEvents != null) {
      await _detectionEvents!.setNotifyValue(true);
      _subscriptions.add(
        _detectionEvents!.onValueReceived.listen(_onDetection),
      );
    }

    // Subscribe to engine state notifications
    if (_engineControl != null) {
      await _engineControl!.setNotifyValue(true);
      _subscriptions.add(
        _engineControl!.onValueReceived.listen((data) {
          _engineStates.add(BleProtocol.decodeEngineStatus(data));
        }),
      );
      // Always force DISABLE_ALL on connect — no stale engines
      await _engineControl!.write(BleProtocol.encodeDisableAll());
      DebugLog.log('BLE: sent DISABLE_ALL on connect');
      await Future.delayed(const Duration(milliseconds: 300));
      final refreshed = await _engineControl!.read();
      _engineStates.add(BleProtocol.decodeEngineStatus(refreshed));
    }

    // Subscribe to foxhunter RSSI
    if (_foxhunterRssi != null) {
      await _foxhunterRssi!.setNotifyValue(true);
      _subscriptions.add(
        _foxhunterRssi!.onValueReceived.listen((data) {
          _foxhunterRssiStream.add(BleProtocol.decodeFoxhunterRssi(data));
        }),
      );
    }

    // Subscribe to mesh status
    if (_meshStatus != null) {
      await _meshStatus!.setNotifyValue(true);
      _subscriptions.add(
        _meshStatus!.onValueReceived.listen((data) {
          _meshStatusStream.add(BleProtocol.decodeMeshStatus(data));
        }),
      );
    }


    _currentState = NodeConnectionState.ready; _connectionState.add(NodeConnectionState.ready);
  }

  // -- Engine control --

  Future<void> enableEngine(Engine engine, {int? radio}) async {
    if (_engineControl == null) return;
    if (engine.isWifi) {
      for (final conflict in Engine.values.where((e) => e.isWifi && e != engine)) {
        await _engineControl!.write(
          BleProtocol.encodeEngineControl(engine: conflict, enable: false),
        );
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (radio != null) {
      await _engineControl!.write(
        BleProtocol.encodeEngineConfig(
          engine: engine,
          payload: Uint8List.fromList([radio]),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await _engineControl!.write(
      BleProtocol.encodeEngineControl(engine: engine, enable: true),
    );
    await _refreshEngineState();
  }

  Future<void> disableEngine(Engine engine) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineControl(engine: engine, enable: false),
    );
    await _refreshEngineState();
  }

  Future<void> sendEngineConfig(Engine engine, Uint8List payload) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(engine: engine, payload: payload),
    );
  }

  Future<void> disableAllEngines() async {
    if (_engineControl == null) return;
    await _engineControl!.write(BleProtocol.encodeDisableAll());
    DebugLog.log('BLE: sent DISABLE_ALL');
    await _refreshEngineState();
  }

  /// Read engine state directly — bypasses unreliable NOTIFY under load.
  Future<void> _refreshEngineState() async {
    if (_engineControl == null) return;
    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final data = await _engineControl!.read();
      _engineStates.add(BleProtocol.decodeEngineStatus(data));
    } catch (e) {
      DebugLog.log('BLE: engine state read failed: $e');
    }
  }

  // -- GPS push --

  Future<void> pushGps({
    required double latitude,
    required double longitude,
    double altitude = 0,
    double speed = 0,
    double heading = 0,
    double accuracy = 0,
    int satelliteCount = 0,
  }) async {
    if (_gpsReceive == null) return;
    updateGps(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      satelliteCount: satelliteCount,
    );
    await _gpsReceive!.write(
      BleProtocol.encodeGps(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        speed: speed,
        heading: heading,
        accuracy: accuracy,
        satelliteCount: satelliteCount,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
      withoutResponse: true,
    );
  }

  // -- Hardware config --

  Future<void> writeHardwareConfig({
    required bool buzzer,
    required bool led,
    required int neopixelBrightness,
    required int buzzerVolume,
  }) async {
    if (_hardwareConfig == null) return;
    await _hardwareConfig!.write(
      BleProtocol.encodeHardwareConfig(
        buzzer: buzzer,
        led: led,
        neopixelBrightness: neopixelBrightness,
        buzzerVolume: buzzerVolume,
      ),
    );
  }

  Future<void> writeAlertConfig({
    required int cooldownMs,
    required int heartbeatMs,
    required int rediscoverMs,
    required int hbActiveMs,
  }) async {
    if (_alertConfig == null) return;
    await _alertConfig!.write(
      BleProtocol.encodeAlertConfig(
        cooldownMs: cooldownMs,
        heartbeatMs: heartbeatMs,
        rediscoverMs: rediscoverMs,
        hbActiveMs: hbActiveMs,
      ),
    );
  }

  // -- Foxhunter --

  Future<void> setFoxhunterTarget(String mac, {int channel = 0}) async {
    if (_foxhunterConfig == null) return;
    await _foxhunterConfig!.write(
      BleProtocol.encodeFoxhunterTarget(mac, channel: channel),
    );
  }

  // -- UniPwn --

  Future<void> sendUnipwnCommand({
    required String targetMac,
    required int commandType,
    String payload = '',
  }) async {
    if (_unipwnCommand == null) return;
    await _unipwnCommand!.write(
      BleProtocol.encodeUnipwnCommand(
        targetMac: targetMac,
        commandType: commandType,
        payload: payload,
      ),
    );
  }

  // -- Mesh --

  Future<void> writeMeshConfig({
    required bool enabled,
    required bool encryption,
    required Uint8List key,
    required List<Uint8List> peerMacs,
  }) async {
    if (_meshConfig == null) return;
    await _meshConfig!.write(
      BleProtocol.encodeMeshConfig(
        enabled: enabled,
        encryption: encryption,
        key: key,
        peerMacs: peerMacs,
      ),
    );
  }

  // -- Disconnect --

  Future<void> disconnect() async {
    await disableAllEngines();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _device?.disconnect();
    _device = null;
    _currentState = NodeConnectionState.disconnected; _connectionState.add(NodeConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _connectionState.close();
    _detections.close();
    _foxhunterRssiStream.close();
    _engineStates.close();
    _meshStatusStream.close();
  }

  // -- Private --

  void _onDetection(List<int> data) {
    final detection = BleProtocol.decodeDetection(
      data,
      sessionId: _sessionId,
      nodeId: _nodeId,
      appTimestamp: DateTime.now(),
      latitude: _lastLat,
      longitude: _lastLon,
      accuracy: _lastAccuracy,
      satelliteCount: _lastSatCount,
    );
    _detections.add(detection);
  }

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  void _startReconnect() {
    if (_device == null) return;
    _currentState = NodeConnectionState.reconnecting; _connectionState.add(NodeConnectionState.reconnecting);
    _reconnectAttempt = 0;
    _attemptReconnect();
  }

  void _attemptReconnect() {
    final delay = Duration(
      seconds: [1, 2, 4, 8, 15, 30][_reconnectAttempt.clamp(0, 5)],
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_device == null) return;
      try {
        await connect(_device!, sessionId: _sessionId);
      } catch (_) {
        _reconnectAttempt++;
        _attemptReconnect();
      }
    });
  }

  String _extractNodeId(List<int> data) {
    // Format: version\0nodeId\0 — skip first string (firmware version)
    final firstNull = data.indexOf(0);
    if (firstNull < 0 || firstNull + 1 >= data.length) {
      return String.fromCharCodes(data.take(16).toList());
    }
    final rest = data.sublist(firstNull + 1);
    final secondNull = rest.indexOf(0);
    final nodeSlice = secondNull >= 0 ? rest.sublist(0, secondNull) : rest;
    return String.fromCharCodes(nodeSlice);
  }
}

/// Riverpod provider for BleManager singleton.
final bleManagerProvider = Provider<BleManager>((ref) {
  final manager = BleManager();
  ref.onDispose(manager.dispose);
  return manager;
});
