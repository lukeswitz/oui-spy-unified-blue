import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/ble/gatt_uuids.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/core/watchlist_state.dart';

class SpoolImportProgress {
  final int seen;
  final int total;
  final int dropped;
  final bool done;
  final bool aborted;
  const SpoolImportProgress({
    required this.seen,
    required this.total,
    required this.dropped,
    required this.done,
    required this.aborted,
  });
}

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
  BluetoothDevice? _lastDevice;
  BluetoothCharacteristic? _engineControl;
  BluetoothCharacteristic? _detectionEvents;
  BluetoothCharacteristic? _deviceStatus;
  BluetoothCharacteristic? _gpsReceive;
  BluetoothCharacteristic? _hardwareConfig;
  BluetoothCharacteristic? _alertConfig;
  BluetoothCharacteristic? _ignoreList;
  BluetoothCharacteristic? _nodeRadio;
  BluetoothCharacteristic? _foxhunterRssi;
  BluetoothCharacteristic? _skySpyTelemetry;
  BluetoothCharacteristic? _unipwnDevices;
  BluetoothCharacteristic? _unipwnCommand;
  BluetoothCharacteristic? _foxhunterConfig;
  BluetoothCharacteristic? _meshConfig;
  BluetoothCharacteristic? _meshStatus;
  BluetoothCharacteristic? _orchestration;
  BluetoothCharacteristic? _dfuControl;
  BluetoothCharacteristic? _dfuData;
  BluetoothCharacteristic? _systemControl;
  BluetoothCharacteristic? _wifiConfig;
  BluetoothCharacteristic? _pcapControl;
  BluetoothCharacteristic? _pcapStats;
  BluetoothCharacteristic? _pcapData;
  BluetoothCharacteristic? _detectorConfig;
  List<WatchlistEntry> Function()? _watchlistGetter;

  void setWatchlistGetter(List<WatchlistEntry> Function() getter) {
    _watchlistGetter = getter;
  }

  final _connectionState = StreamController<NodeConnectionState>.broadcast();
  final _detections = StreamController<Detection>.broadcast();
  final _foxhunterRssiStream = StreamController<({int rssi, int intervalMs})>.broadcast();
  final _engineStates = StreamController<({int available, int active, List<EngineState> states})>.broadcast();
  final _meshStatusStream = StreamController<({bool enabled, int peerCount, int connectedPeers, int rxCount, int txCount, List<({String id, int role, int activeEngines, int fwVersion})> liveNodes})>.broadcast();
  final _pcapStatsStream = StreamController<PcapStats>.broadcast();
  final _pcapDataStream = StreamController<Uint8List>.broadcast();
  PcapStats _latestPcapStats = PcapStats.empty;

  final _importedDetections = StreamController<Detection>.broadcast();
  Stream<Detection> get importedDetections => _importedDetections.stream;

  final _awayLiveDetections = StreamController<Detection>.broadcast();
  Stream<Detection> get awayLiveDetections => _awayLiveDetections.stream;

  final _spoolImport = StreamController<SpoolImportProgress>.broadcast();
  Stream<SpoolImportProgress> get spoolImport => _spoolImport.stream;

  final _awayImport = StreamController<SpoolImportProgress>.broadcast();
  Stream<SpoolImportProgress> get awayImport => _awayImport.stream;

  bool _offlineScanEnabled = false;
  bool get offlineScanEnabled => _offlineScanEnabled;

  bool _importing = false;
  int _awaySeen = 0;
  Timer? _awaySettle;
  int _importTotal = 0;
  int _importSeen = 0;
  int _importDropped = 0;
  int _importDeviceNow = 0;
  int get importDeviceNowMs => _importDeviceNow;
  Timer? _importTimer;

  // WiFi OTA progress notifications: opcode 0x06, status[1], bytes[4 LE]
  final _wifiOtaStream = StreamController<({int status, int bytesRead})>.broadcast();
  Stream<({int status, int bytesRead})> get wifiOtaUpdates => _wifiOtaStream.stream;

  // Fleet (mesh byte-relay) OTA progress: opcode 0x08, phase[1], pct[1], done[1], seen[1]
  final _fleetOtaStream =
      StreamController<({int phase, int pct, int done, int seen})>.broadcast();
  Stream<({int phase, int pct, int done, int seen})> get fleetOtaUpdates =>
      _fleetOtaStream.stream;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  int _mtu = 23;
  String _sessionId = '';
  String _nodeId = '';
  String _board = '';
  String _role = '';
  String? _lastDeviceId;
  String? _primaryDeviceId;
  bool _userInitiatedDisconnect = false;

  // -- Public streams --

  Stream<NodeConnectionState> get connectionState => _connectionState.stream;
  Stream<Detection> get detections => _detections.stream;
  Stream<({int rssi, int intervalMs})> get foxhunterRssi => _foxhunterRssiStream.stream;
  Stream<({int available, int active, List<EngineState> states})> get engineStates =>
      _engineStates.stream;
  Stream<({bool enabled, int peerCount, int connectedPeers, int rxCount, int txCount, List<({String id, int role, int activeEngines, int fwVersion})> liveNodes})> get meshStatusUpdates =>
      _meshStatusStream.stream;
  Stream<PcapStats> get pcapStats => _pcapStatsStream.stream;
  Stream<Uint8List> get pcapData => _pcapDataStream.stream;
  PcapStats get latestPcapStats => _latestPcapStats;

  File? _pcapFile;
  IOSink? _pcapSink;
  int _pcapFileMode = 0;
  int _pcapBytesWritten = 0;
  Uint8List _pcapRx = Uint8List(0);
  int _pcapRxStart = 0;
  bool _pcapPrevActive = false;

  final _pcapBytesStream = StreamController<int>.broadcast();
  final _pcapSavedStream = StreamController<File>.broadcast();
  Stream<int> get pcapBytesWritten => _pcapBytesStream.stream;
  Stream<File> get pcapCaptureSaved => _pcapSavedStream.stream;
  File? get currentPcapFile => _pcapFile;
  int get pcapBytesWrittenLatest => _pcapBytesWritten;

  Future<void> abortActivePcap() async {
    try {
      await stopPcap();
    } on Exception {
      // proceed to close locally regardless
    }
    await _closePcapFile(silent: true);
  }

  static const int _kPcapLtWifi = 127;
  static const int _kPcapLtBle = 256;
  static const int _kPcapSnap = 2500;
  static const int _kPcapMagic = 0xCAFEBABE;
  static const int _kPcapEnd = 0xDEADBEEF;

  Future<Directory> _pcapDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/pcaps');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Uint8List _buildPcapHeader(int linkType) {
    final bd = ByteData(24);
    bd.setUint32(0, 0xa1b2c3d4, Endian.little);
    bd.setUint16(4, 2, Endian.little);
    bd.setUint16(6, 4, Endian.little);
    bd.setInt32(8, 0, Endian.little);
    bd.setUint32(12, 0, Endian.little);
    bd.setUint32(16, _kPcapSnap, Endian.little);
    bd.setUint32(20, linkType, Endian.little);
    return bd.buffer.asUint8List();
  }

  Future<void> _openPcapFile(int mode, {PcapStats? stats}) async {
    await _closePcapFile(silent: true);
    final dir = await _pcapDir();
    final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now().toLocal());
    final suffix = mode == 1 ? 'ble' : 'wifi';
    String name;
    if (stats != null && stats.isAutoTriggered) {
      final macFlat = stats.autoTriggerMac
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      name = 'ouispy_${ts}_${macFlat}_${stats.autoTriggerEngineName}_$suffix.pcap';
    } else {
      name = 'oui_spy_${suffix}_$ts.pcap';
    }
    _pcapFile = File('${dir.path}/$name');
    _pcapSink = _pcapFile!.openWrite(mode: FileMode.writeOnly);
    final lt = mode == 1 ? _kPcapLtBle : _kPcapLtWifi;
    _pcapSink!.add(_buildPcapHeader(lt));
    _pcapFileMode = mode;
    _pcapBytesWritten = 24;
    _pcapRx = Uint8List(0);
    _pcapRxStart = 0;
    _pcapBytesStream.add(_pcapBytesWritten);
  }

  Future<void> _closePcapFile({bool silent = false}) async {
    if (_pcapSink == null) {
      _pcapFile = null;
      return;
    }
    final f = _pcapFile;
    final bytes = _pcapBytesWritten;
    try {
      await _pcapSink!.flush();
      await _pcapSink!.close();
    } on Exception catch (e) {
      DebugLog.log('pcap close error: $e');
    }
    _pcapSink = null;
    _pcapRx = Uint8List(0);
    _pcapRxStart = 0;
    if (!silent && f != null && bytes > 24) {
      _pcapSavedStream.add(f);
    }
    _pcapFile = null;
  }

  void _handlePcapStatsTransition(PcapStats stats) {
    final active = stats.state == 1;
    if (active && !_pcapPrevActive) {
      _openPcapFile(stats.mode, stats: stats);
    } else if (!active && _pcapPrevActive) {
      _closePcapFile();
    }
    _pcapPrevActive = active;
  }

  void _ingestPcapBytes(Uint8List bytes) {
    if (_pcapSink == null || bytes.isEmpty) return;
    final avail = _pcapRx.length - _pcapRxStart;
    final needed = avail + bytes.length;
    if (_pcapRxStart > 0 && _pcapRx.length - avail >= 4096) {
      final compact = Uint8List(needed);
      compact.setRange(0, avail, _pcapRx, _pcapRxStart);
      compact.setRange(avail, needed, bytes);
      _pcapRx = compact;
      _pcapRxStart = 0;
    } else if (_pcapRx.length < _pcapRxStart + needed) {
      int cap = _pcapRx.length == 0 ? 4096 : _pcapRx.length * 2;
      while (cap < _pcapRxStart + needed) {
        cap *= 2;
      }
      final grown = Uint8List(cap);
      grown.setRange(0, _pcapRx.length, _pcapRx);
      _pcapRx = grown;
    }
    _pcapRx.setRange(_pcapRxStart + avail, _pcapRxStart + needed, bytes);
    final end = _pcapRxStart + needed;

    int i = _pcapRxStart;
    int totalWritten = 0;
    while (true) {
      while (end - i >= 4) {
        final m = _pcapRx[i] |
            (_pcapRx[i + 1] << 8) |
            (_pcapRx[i + 2] << 16) |
            (_pcapRx[i + 3] << 24);
        if (m == _kPcapMagic) break;
        i++;
      }
      if (end - i < 8) break;
      final recLen = _pcapRx[i + 4] |
          (_pcapRx[i + 5] << 8) |
          (_pcapRx[i + 6] << 16) |
          (_pcapRx[i + 7] << 24);
      if (recLen < 16 || recLen > _kPcapSnap + 16) {
        i++;
        continue;
      }
      if (end - i < 8 + recLen + 4) break;
      final endOff = i + 8 + recLen;
      final endMark = _pcapRx[endOff] |
          (_pcapRx[endOff + 1] << 8) |
          (_pcapRx[endOff + 2] << 16) |
          (_pcapRx[endOff + 3] << 24);
      if (endMark != _kPcapEnd) {
        i++;
        continue;
      }
      final rec = Uint8List.sublistView(_pcapRx, i + 8, i + 8 + recLen);
      _pcapSink!.add(rec);
      totalWritten += recLen;
      i += 8 + recLen + 4;
    }
    _pcapRxStart = i;
    if (_pcapRxStart >= end) {
      _pcapRxStart = 0;
      _pcapRx = Uint8List(0);
    }
    if (totalWritten > 0) {
      _pcapBytesWritten += totalWritten;
      _pcapBytesStream.add(_pcapBytesWritten);
    }
  }

  NodeConnectionState _currentState = NodeConnectionState.disconnected;

  bool get isConnected =>
      _currentState == NodeConnectionState.ready ||
      (_device?.isConnected ?? false);

  NodeConnectionState get currentConnectionState => _currentState;
  String get nodeId => _nodeId;
  String get board => _board;
  String get role => _role;
  String? get connectedDeviceId => _primaryDeviceId ?? _lastDeviceId;
  bool get isManagerConnected =>
      (_device?.platformName ?? '').toUpperCase().contains('OUI-SPY-MGR');

  void markAsPrimary() {
    _primaryDeviceId = _lastDeviceId;
    final id = _primaryDeviceId;
    if (id != null && id.isNotEmpty) {
      SharedPreferences.getInstance()
          .then((p) => p.setString('lastPrimaryDeviceId', id));
    }
  }

  /// Get a discovered characteristic by UUID (for direct read/write).
  BluetoothCharacteristic? getCharacteristic(Guid uuid) {
    if (uuid == GattUuids.engineControl) return _engineControl;
    if (uuid == GattUuids.detectionEvents) return _detectionEvents;
    if (uuid == GattUuids.deviceStatus) return _deviceStatus;
    if (uuid == GattUuids.gpsReceive) return _gpsReceive;
    if (uuid == GattUuids.hardwareConfig) return _hardwareConfig;
    if (uuid == GattUuids.alertConfig) return _alertConfig;
    if (uuid == GattUuids.ignoreList) return _ignoreList;
    if (uuid == GattUuids.nodeRadio) return _nodeRadio;
    if (uuid == GattUuids.foxhunterRssi) return _foxhunterRssi;
    if (uuid == GattUuids.foxhunterConfig) return _foxhunterConfig;
    if (uuid == GattUuids.meshConfig) return _meshConfig;
    if (uuid == GattUuids.meshStatus) return _meshStatus;
    if (uuid == GattUuids.deviceInfo) return _deviceInfoChar;
    if (uuid == GattUuids.dfuControl) return _dfuControl;
    if (uuid == GattUuids.dfuData) return _dfuData;
    if (uuid == GattUuids.systemControl) return _systemControl;
    if (uuid == GattUuids.wifiConfig) return _wifiConfig;
    return null;
  }

  int get mtu => _mtu;
  BluetoothCharacteristic? get dfuControl => _dfuControl;
  BluetoothCharacteristic? get dfuData => _dfuData;
  BluetoothCharacteristic? get systemControl => _systemControl;
  BluetoothCharacteristic? get wifiConfig => _wifiConfig;

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

    await FlutterBluePlus.startScan(timeout: timeout);
  }

  /// Stream of scan results (list updated each scan cycle).
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.onScanResults;

  Future<void> stopScan() async => FlutterBluePlus.stopScan();

  /// Scan and return the first device whose advertised/platform name matches
  /// [exactName] (case-insensitive). Null if not seen within [timeout].
  Future<BluetoothDevice?> scanForDeviceNamed(String exactName,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final target = exactName.toUpperCase();
    final completer = Completer<BluetoothDevice?>();
    final sub = scanResults.listen((results) {
      for (final r in results) {
        final n = r.device.platformName.toUpperCase();
        final a = r.advertisementData.advName.toUpperCase();
        if ((n == target || a == target) && !completer.isCompleted) {
          completer.complete(r.device);
        }
      }
    });
    try {
      await startScan(timeout: timeout);
    } on Exception catch (e) {
      DebugLog.log('BLE: scanForDeviceNamed scan error $e');
    }
    final found = await completer.future
        .timeout(timeout + const Duration(seconds: 2), onTimeout: () => null);
    await sub.cancel();
    await stopScan();
    return found;
  }

  /// Connect to [device], mark it primary, and resolve true once the link
  /// reaches `ready` (or false on disconnect / timeout).
  Future<bool> connectAndReady(BluetoothDevice device,
      {Duration timeout = const Duration(seconds: 25)}) async {
    final completer = Completer<bool>();
    final sub = connectionState.listen((s) {
      if (s == NodeConnectionState.ready && !completer.isCompleted) {
        completer.complete(true);
      } else if (s == NodeConnectionState.disconnected &&
          !completer.isCompleted) {
        completer.complete(false);
      }
    });
    try {
      await connect(device,
          sessionId: 'ota-${DateTime.now().microsecondsSinceEpoch}');
      markAsPrimary();
    } on Exception catch (e) {
      DebugLog.log('BLE: connectAndReady connect error $e');
      if (!completer.isCompleted) completer.complete(false);
    }
    final ok =
        await completer.future.timeout(timeout, onTimeout: () => isConnected);
    await sub.cancel();
    return ok;
  }

  /// Reconnect to a previously-seen device by its remoteId (no scan needed).
  Future<bool> connectByIdAndReady(String remoteId,
      {Duration timeout = const Duration(seconds: 25)}) async {
    try {
      return await connectAndReady(BluetoothDevice.fromId(remoteId),
          timeout: timeout);
    } on Exception catch (e) {
      DebugLog.log('BLE: connectByIdAndReady error $e');
      return false;
    }
  }

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

    _subscriptions.add(
      device.connectionState.listen((state) {
        DebugLog.log('BLE: connectionState=$state');
        if (state == BluetoothConnectionState.disconnected) {
          _currentState = NodeConnectionState.disconnected; _connectionState.add(NodeConnectionState.disconnected);
          if (_importing) {
            _abortImport();
          }
          if (_userInitiatedDisconnect) {
            DebugLog.log('BLE: skipping reconnect (user-initiated)');
            _userInitiatedDisconnect = false;
          } else {
            _startReconnect();
          }
        }
      }),
    );

    _currentState = NodeConnectionState.negotiating; _connectionState.add(NodeConnectionState.negotiating);

    // Negotiate MTU. Android: requestMtu works. iOS/macOS: automatic — read
    // the stream value instead. Falling back to 23 on iOS would cap OTA
    // payload at 17 bytes/chunk and make firmware uploads take hours.
    try {
      _mtu = await device.requestMtu(512);
      DebugLog.log('BLE: MTU negotiated=$_mtu');
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('BLE: requestMtu unsupported (${e.description}) — reading actual');
      // iOS auto-negotiates; mtuNow is populated after connect.
      _mtu = device.mtuNow;
      DebugLog.log('BLE: MTU (auto)=$_mtu');
    }
    if (_mtu < 23) {
      DebugLog.log('BLE: MTU $_mtu too low, defaulting to 23');
      _mtu = 23;
    }

    // Request high connection priority — drops conn interval to ~15ms on
    // Android, big win for OTA throughput. No-op on iOS (Apple chooses).
    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      DebugLog.log('BLE: requested high conn priority');
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('BLE: conn priority unsupported: ${e.description}');
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
      if (c.uuid == GattUuids.ignoreList) _ignoreList = c;
      if (c.uuid == GattUuids.nodeRadio) _nodeRadio = c;
      if (c.uuid == GattUuids.foxhunterRssi) _foxhunterRssi = c;
      if (c.uuid == GattUuids.skySpyTelemetry) _skySpyTelemetry = c;
      if (c.uuid == GattUuids.unipwnDevices) _unipwnDevices = c;
      if (c.uuid == GattUuids.unipwnCommand) _unipwnCommand = c;
      if (c.uuid == GattUuids.foxhunterConfig) _foxhunterConfig = c;
      if (c.uuid == GattUuids.meshConfig) _meshConfig = c;
      if (c.uuid == GattUuids.meshStatus) _meshStatus = c;
      if (c.uuid == GattUuids.orchestration) _orchestration = c;
      if (c.uuid == GattUuids.dfuControl) _dfuControl = c;
      if (c.uuid == GattUuids.dfuData) _dfuData = c;
      if (c.uuid == GattUuids.systemControl) _systemControl = c;
      if (c.uuid == GattUuids.wifiConfig) _wifiConfig = c;
      if (c.uuid == GattUuids.pcapControl) _pcapControl = c;
      if (c.uuid == GattUuids.pcapStats) _pcapStats = c;
      if (c.uuid == GattUuids.pcapData) _pcapData = c;
      if (c.uuid == GattUuids.detectorConfig) _detectorConfig = c;
    }

    // Read device info to get node ID
    _deviceInfoChar = ouiService.characteristics.firstWhere(
      (c) => c.uuid == GattUuids.deviceInfo,
    );
    final infoData = await _deviceInfoChar!.read();
    final parts = _parseDeviceInfo(infoData);
    _nodeId = parts.length > 1 ? parts[1] : '';
    _board = parts.length > 2 ? parts[2] : '';
    _role = parts.length > 3 ? parts[3] : '';
    DebugLog.log('BLE: nodeId=$_nodeId board=$_board role=$_role');
    await _readDeviceConfig();

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
      final isMgr = (device.platformName.toUpperCase()).contains('OUI-SPY-MGR');
      if (!isMgr && !_offlineScanEnabled) {
        await _engineControl!.write(BleProtocol.encodeDisableAll());
        DebugLog.log('BLE: sent DISABLE_ALL on connect (node)');
        await Future.delayed(const Duration(milliseconds: 300));
      } else if (!isMgr) {
        DebugLog.log('BLE: offline-scan on — adopting running scan, no DISABLE_ALL');
      } else {
        DebugLog.log('BLE: skipped DISABLE_ALL on connect (manager)');
      }
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


    if (_pcapStats != null) {
      await _pcapStats!.setNotifyValue(true);
      _subscriptions.add(
        _pcapStats!.onValueReceived.listen((data) {
          final stats = PcapStats.decode(data);
          if (stats != null) {
            _latestPcapStats = stats;
            _pcapStatsStream.add(stats);
            _handlePcapStatsTransition(stats);
          }
        }),
      );
    }

    if (_pcapData != null) {
      await _pcapData!.setNotifyValue(true);
      _subscriptions.add(
        _pcapData!.onValueReceived.listen((data) {
          final bytes = Uint8List.fromList(data);
          _pcapDataStream.add(bytes);
          _ingestPcapBytes(bytes);
        }),
      );
    }

    _currentState = NodeConnectionState.ready; _connectionState.add(NodeConnectionState.ready);

    final getter = _watchlistGetter;
    if (getter != null && _detectorConfig != null) {
      try {
        await syncDetectorWatchlist(getter());
      } catch (e) {
        DebugLog.log('BLE: watchlist sync failed: $e');
      }
    }

    // Subscribe to systemControl notifications: OTA confirm ACKs +
    // WiFi OTA progress (opcode 0x06).
    if (_systemControl != null) {
      await _systemControl!.setNotifyValue(true);
      _subscriptions.add(
        _systemControl!.onValueReceived.listen((data) {
          if (data.isEmpty) return;
          if (data[0] == 0x06 && data.length >= 6) {
            final status = data[1];
            final bytes = data[2]
                | (data[3] << 8)
                | (data[4] << 16)
                | (data[5] << 24);
            _wifiOtaStream.add((status: status, bytesRead: bytes));
          } else if (data[0] == 0x08 && data.length >= 5) {
            _fleetOtaStream.add((
              phase: data[1],
              pct: data[2],
              done: data[3],
              seen: data[4],
            ));
          }
        }),
      );
    }

    // Confirm previously-flashed OTA image (idempotent — no-op unless image is
    // PENDING_VERIFY on the firmware side). Successful GATT handshake means
    // the new image works; cancel rollback.
    if (_systemControl != null) {
      try {
        await _systemControl!.write(
          Uint8List.fromList([0x03]),
          withoutResponse: false,
        );
        DebugLog.log('BLE: sent OTA confirm');
      } on FlutterBluePlusException catch (e) {
        DebugLog.log('BLE: OTA confirm write failed: ${e.description}');
      }
    }

    _awaySettle?.cancel();
    _awaySeen = 0;
    if (_offlineScanEnabled) {
      await requestSpoolFlush();
    }
  }

  // -- System control --

  /// Reboot device. Magic bytes prevent accidental triggers.
  Future<void> rebootDevice() async {
    if (_systemControl == null) return;
    await _systemControl!.write(
      Uint8List.fromList([0x01, 0xC0, 0xDE]),
      withoutResponse: false,
    );
  }

  /// Factory reset: erase NVS and reboot. Magic bytes required.
  Future<void> factoryReset() async {
    if (_systemControl == null) return;
    await _systemControl!.write(
      Uint8List.fromList([0x02, 0xC0, 0xDE]),
      withoutResponse: false,
    );
  }

  Future<void> requestSpoolFlush() async {
    if (_systemControl == null || !_offlineScanEnabled) return;
    _importing = true;
    _importSeen = 0;
    _importTotal = 0;
    _importDropped = 0;
    _importDeviceNow = 0;
    _importTimer?.cancel();
    _importTimer = Timer(const Duration(seconds: 12), _abortImport);
    await _systemControl!.write(BleProtocol.flushSpoolCmd, withoutResponse: false);
    DebugLog.log('BLE: spool flush requested');
  }

  Future<void> confirmSpoolImported() async {
    if (_systemControl == null) return;
    await _systemControl!.write(BleProtocol.spoolClearCmd, withoutResponse: false);
    DebugLog.log('BLE: spool clear sent after DB commit');
  }

  /// Push WiFi STA credentials to device. Format:
  /// [ssid_len][ssid bytes][pass_len][pass bytes]
  Future<void> writeWifiConfig(String ssid, String pass) async {
    if (_wifiConfig == null) {
      throw StateError('WiFi config characteristic not found — firmware too old');
    }
    final ssidBytes = ssid.codeUnits;
    final passBytes = pass.codeUnits;
    if (ssidBytes.length > 32) {
      throw ArgumentError('SSID too long (max 32 bytes)');
    }
    if (passBytes.length > 64) {
      throw ArgumentError('Password too long (max 64 bytes)');
    }
    final payload = Uint8List(2 + ssidBytes.length + passBytes.length);
    payload[0] = ssidBytes.length;
    payload.setRange(1, 1 + ssidBytes.length, ssidBytes);
    payload[1 + ssidBytes.length] = passBytes.length;
    payload.setRange(2 + ssidBytes.length,
                     2 + ssidBytes.length + passBytes.length, passBytes);
    await _wifiConfig!.write(payload, withoutResponse: false);
  }

  Future<({bool hasCreds, bool connected, bool enabled, String ssid, String ip, int rssi})> readWifiConfig() async {
    const empty = (hasCreds: false, connected: false, enabled: false, ssid: '', ip: '', rssi: 0);
    if (_wifiConfig == null) return empty;
    final data = await _wifiConfig!.read();
    if (data.length < 8) return empty;
    final has = data[0] == 1;
    final connected = data[1] == 1;
    final ip = '${data[2]}.${data[3]}.${data[4]}.${data[5]}';
    final rssi = data[6] >= 128 ? data[6] - 256 : data[6];
    final ssidLen = data[7];
    if (data.length < 8 + ssidLen) {
      return (hasCreds: has, connected: connected, enabled: false, ssid: '', ip: ip, rssi: rssi);
    }
    final ssid = String.fromCharCodes(data.sublist(8, 8 + ssidLen));
    final enabled = (data.length >= 8 + ssidLen + 1) ? data[8 + ssidLen] == 1 : false;
    return (
      hasCreds: has,
      connected: connected,
      enabled: enabled,
      ssid: ssid,
      ip: connected ? ip : '',
      rssi: connected ? rssi : 0,
    );
  }

  Future<void> setWifiStaEnabled(bool enabled) async {
    if (_wifiConfig == null) return;
    await _wifiConfig!.write(
      Uint8List.fromList([0xF1, enabled ? 1 : 0]),
      withoutResponse: false,
    );
  }

  Future<void> wipeWifiCreds() async {
    if (_wifiConfig == null) return;
    await _wifiConfig!.write(
      Uint8List.fromList([0xF2]),
      withoutResponse: false,
    );
  }

  Future<void> setIgnoreList(List<int> bytes) async {
    if (_ignoreList == null) return;
    await _ignoreList!.write(bytes, withoutResponse: false);
  }

  /// Push per-node radio roles to the manager. Wire format:
  /// [count][id:4 ascii][radio:1] per entry (radio 0x01=WiFi,0x02=BLE,0x03=Both).
  Future<void> setNodeRadioRoles(Map<String, int> roles) async {
    if (_nodeRadio == null) return;
    final valid = roles.entries.where((e) => e.key.length == 4).toList();
    if (valid.length > 255) valid.removeRange(255, valid.length);
    final bytes = <int>[valid.length];
    for (final e in valid) {
      bytes.addAll(e.key.codeUnits);
      final m = e.value & 0x03;
      bytes.add(m == 0 ? 0x03 : m);
    }
    await _nodeRadio!.write(bytes, withoutResponse: false);
  }

  Future<void> setAutoPcap(bool enabled) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList([0x10, enabled ? 1 : 0]),
      ),
    );
  }

  Future<void> setAutoPcapDuration(int seconds) async {
    if (_engineControl == null) return;
    final s = seconds.clamp(1, 65535);
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList([0x11, s & 0xFF, (s >> 8) & 0xFF]),
      ),
    );
  }

  Future<void> setAutoPcapCooldown(int seconds) async {
    if (_engineControl == null) return;
    final s = seconds.clamp(0, 65535);
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList([0x12, s & 0xFF, (s >> 8) & 0xFF]),
      ),
    );
  }

  Future<void> wifiDisconnect() async {
    if (_systemControl == null) return;
    await _systemControl!.write(
      Uint8List.fromList([0x06, 0xC0, 0xDE]),
      withoutResponse: false,
    );
  }

  Future<void> wifiWipeCreds() async {
    if (_systemControl == null) return;
    await _systemControl!.write(
      Uint8List.fromList([0x07, 0xC0, 0xDE]),
      withoutResponse: false,
    );
  }

  Future<void> triggerWifiOta(String url) async {
    if (_systemControl == null) {
      throw StateError('System control characteristic not found');
    }
    final urlBytes = url.codeUnits;
    final payload = Uint8List(3 + urlBytes.length);
    payload[0] = 0x04; // SYS_CMD_OTA_VIA_WIFI
    payload[1] = 0xC0;
    payload[2] = 0xDE;
    payload.setRange(3, 3 + urlBytes.length, urlBytes);
    await _systemControl!.write(payload, withoutResponse: false);
  }

  /// Tell the manager to fleet-update all nodes: it downloads the node image
  /// once over WiFi, then byte-relays it to every node over ESP-NOW. The phone
  /// stays connected to the manager throughout; progress arrives via
  /// [fleetOtaUpdates].
  Future<void> triggerFleetOta(String nodeUrl) async {
    if (_systemControl == null) {
      throw StateError('System control characteristic not found');
    }
    final urlBytes = nodeUrl.codeUnits;
    final payload = Uint8List(3 + urlBytes.length);
    payload[0] = 0x05; // SYS_CMD_FLEET_OTA
    payload[1] = 0xC0;
    payload[2] = 0xDE;
    payload.setRange(3, 3 + urlBytes.length, urlBytes);
    await _systemControl!.write(payload, withoutResponse: false);
  }

  /// Fleet WiFi OTA: manager broadcasts its saved WiFi creds + the node firmware
  /// URL to every node over mesh. Each node saves the creds, reboots into its
  /// WiFi-OTA boot mode, joins the network, downloads + flashes itself, and
  /// rejoins the mesh. Phone stays on the manager (BLE). Status arrives on
  /// [fleetOtaUpdates] (phase 2 = pushed, 0x80 = manager has no WiFi creds,
  /// 0x81 = creds+url too large for one mesh packet).
  Future<void> triggerFleetWifiOta(String nodeUrl) async {
    if (_systemControl == null) {
      throw StateError('System control characteristic not found');
    }
    final urlBytes = nodeUrl.codeUnits;
    final payload = Uint8List(3 + urlBytes.length);
    payload[0] = 0x0A; // SYS_CMD_FLEET_WIFI_OTA
    payload[1] = 0xC0;
    payload[2] = 0xDE;
    payload.setRange(3, 3 + urlBytes.length, urlBytes);
    await _systemControl!.write(payload, withoutResponse: false);
  }

  // -- Engine control --

  Future<void> _engineWriteChain = Future.value();
  Future<T> _serializedEngineWrite<T>(Future<T> Function() op) {
    final next = _engineWriteChain.then((_) => op());
    _engineWriteChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> enableEngine(Engine engine, {int? radio, String? targetNodeId}) async {
    if (_engineControl == null) return;
    final mgr = isManagerConnected;
    if (engine.isWifi && !mgr) {
      bool sentAny = false;
      for (final conflict in Engine.values.where((e) => e.isWifi && e != engine)) {
        if ((engine == Engine.flockWifi && conflict == Engine.wardrive) ||
            (engine == Engine.wardrive && conflict == Engine.flockWifi)) {
          continue;
        }
        try {
          await _serializedEngineWrite(() => _engineControl!.write(
                BleProtocol.encodeEngineControl(engine: conflict, enable: false),
              ));
          sentAny = true;
        } catch (e) {
          DebugLog.log('BLE: conflict-disable ${conflict.name} failed: $e');
        }
      }
      if (sentAny) await Future.delayed(const Duration(milliseconds: 150));
    }
    if (radio != null) {
      try {
        await _serializedEngineWrite(() => _engineControl!.write(
              BleProtocol.encodeEngineConfig(
                engine: engine,
                payload: Uint8List.fromList([radio]),
              ),
            ));
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        DebugLog.log('BLE: enable-radio config ${engine.name} failed: $e');
      }
    }
    try {
      await _serializedEngineWrite(() => _engineControl!.write(
            BleProtocol.encodeEngineControl(
              engine: engine, enable: true, targetNodeId: targetNodeId,
            ),
          ));
    } catch (e) {
      DebugLog.log('BLE: enableEngine ${engine.name} failed: $e');
      rethrow;
    }
    unawaited(_refreshEngineState());
  }

  Future<void> disableEngine(Engine engine, {String? targetNodeId}) async {
    if (_engineControl == null) return;
    try {
      await _serializedEngineWrite(() => _engineControl!.write(
            BleProtocol.encodeEngineControl(
              engine: engine, enable: false, targetNodeId: targetNodeId,
            ),
          ));
    } catch (e) {
      DebugLog.log('BLE: disableEngine ${engine.name} failed: $e');
      rethrow;
    }
    unawaited(_refreshEngineState());
  }

  Future<void> sendEngineConfig(Engine engine, Uint8List payload) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(engine: engine, payload: payload),
    );
  }

  Future<void> syncDetectorWatchlist(List<WatchlistEntry> entries) async {
    if (_detectorConfig == null) {
      DebugLog.log('BLE: detectorConfig char missing; skip watchlist sync');
      return;
    }
    await _detectorConfig!.write(Uint8List.fromList([0x00]), withoutResponse: false);
    int pushed = 0;
    for (final e in entries) {
      if (e.isName) continue;
      if (e.isServiceUuid) {
        final uuid = _parseUuid16(e.identifier);
        if (uuid == null) continue;
        final descBytes = utf8.encode(e.description).take(28).toList();
        final pkt = <int>[0x02, uuid & 0xFF, (uuid >> 8) & 0xFF, ...descBytes];
        await _detectorConfig!.write(Uint8List.fromList(pkt), withoutResponse: false);
        pushed++;
        continue;
      }
      final mac = _parseMac(e.identifier);
      if (mac == null) continue;
      final prefixLen = e.isFullMac ? 6 : 3;
      final descBytes = utf8.encode(e.description).take(31).toList();
      final pkt = <int>[0x01, prefixLen, ...mac, ...descBytes];
      await _detectorConfig!.write(Uint8List.fromList(pkt), withoutResponse: false);
      pushed++;
    }
    DebugLog.log('BLE: synced $pushed/${entries.length} watchlist entries to detector');
  }

  static int? _parseUuid16(String s) {
    final clean = s.trim().replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
    if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(clean)) return null;
    final v = int.parse(clean, radix: 16);
    if (v < 0 || v > 0xFFFF) return null;
    return v;
  }

  static Uint8List? _parseMac(String s) {
    final clean = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length < 6 || clean.length > 12 || clean.length.isOdd) return null;
    final out = Uint8List(6);
    for (int i = 0; i < clean.length; i += 2) {
      out[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return out;
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

  Future<void> resyncOnResume() async {
    if (_currentState != NodeConnectionState.ready || _device == null) {
      DebugLog.log('BLE: resume — not connected, autoconnect handles it');
      return;
    }
    DebugLog.log('BLE: app resumed — reconcile to firmware state + flush node spool');
    try {
      await _readDeviceConfig();
      await _refreshEngineState();
      await requestSpoolFlush();
    } catch (e) {
      DebugLog.log('BLE: resync on resume failed: $e');
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
    bool suppressAlerts = false,
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
        suppressAlerts: suppressAlerts,
      ),
      withoutResponse: true,
    );
  }

  // -- Hardware config --

  Future<void> _readDeviceConfig() async {
    if (_hardwareConfig == null) return;
    try {
      final value = await _hardwareConfig!.read();
      _offlineScanEnabled = value.length > 5 && value[5] == 1;
      DebugLog.log('BLE: hardwareConfig read len=${value.length} offlineScan=$_offlineScanEnabled');
    } on Exception catch (e) {
      DebugLog.log('BLE: hardwareConfig read failed: $e');
      _offlineScanEnabled = false;
    }
  }

  Future<void> writeHardwareConfig({
    required bool buzzer,
    required bool led,
    required int neopixelBrightness,
    required int buzzerVolume,
    bool extendedOui = false,
    bool offlineScan = false,
  }) async {
    if (_hardwareConfig == null) return;
    await _hardwareConfig!.write(
      BleProtocol.encodeHardwareConfig(
        buzzer: buzzer,
        led: led,
        neopixelBrightness: neopixelBrightness,
        buzzerVolume: buzzerVolume,
        extendedOui: extendedOui,
        offlineScan: offlineScan,
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

  Future<void> setFoxhunterTarget(String mac, {int channel = 0, String? nodeId}) async {
    if (nodeId != null) {
      if (_engineControl == null) return;
      final macBytes = BleProtocol.encodeFoxhunterTarget(mac, channel: channel);
      final payload = <int>[
        ...BleProtocol.targetEnvelope(nodeId),
        ...macBytes,
      ];
      await _engineControl!.write(
        BleProtocol.encodeEngineConfig(
          engine: Engine.foxhunter,
          payload: Uint8List.fromList(payload),
        ),
      );
      return;
    }
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
    _userInitiatedDisconnect = true;
    final wasFullyConnected =
        _currentState == NodeConnectionState.ready;
    final isMgr = (_device?.platformName ?? '').toUpperCase().contains('OUI-SPY-MGR');
    _reconnectTimer?.cancel();
    if (wasFullyConnected && !isMgr) {
      try {
        await disableAllEngines();
      } on FlutterBluePlusException catch (e) {
        DebugLog.log('BLE: disableAllEngines on disconnect failed: ${e.description}');
      }
    } else if (isMgr) {
      DebugLog.log('BLE: skipped disableAllEngines on disconnect (manager)');
    } else {
      DebugLog.log('BLE: cancel mid-connect (state=$_currentState) — skipping engine writes');
    }
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    try {
      await _device?.disconnect();
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('BLE: device.disconnect failed: ${e.description}');
    }
    _device = null;
    _currentState = NodeConnectionState.disconnected; _connectionState.add(NodeConnectionState.disconnected);
  }

  Future<void> disconnectQuiet() async {
    if (_device != null) _lastDevice = _device;
    _userInitiatedDisconnect = true;
    _reconnectTimer?.cancel();
    final subs = List.of(_subscriptions);
    _subscriptions.clear();
    for (final sub in subs) {
      try {
        await sub.cancel();
      } on Exception catch (e) {
        DebugLog.log('BLE: sub cancel on quiet disconnect: $e');
      }
    }
    try {
      await _device?.disconnect();
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('BLE: quiet disconnect failed: ${e.description}');
    }
    _device = null;
    _currentState = NodeConnectionState.disconnected;
    _connectionState.add(NodeConnectionState.disconnected);
  }

  /// Launch-time auto-connect runs a scan before it can call connect(); this
  /// surfaces a "reconnecting" state during that window so the UI shows a
  /// searching animation instead of the manual CONNECT button.
  void signalAutoReconnect(bool active) {
    if (_currentState == NodeConnectionState.ready ||
        _currentState == NodeConnectionState.connecting ||
        _currentState == NodeConnectionState.negotiating ||
        _currentState == NodeConnectionState.syncing) {
      return;
    }
    final s = active
        ? NodeConnectionState.reconnecting
        : NodeConnectionState.disconnected;
    _currentState = s;
    _connectionState.add(s);
  }

  Future<void> reconnectPrimary() async {
    if (_currentState == NodeConnectionState.ready) return;
    final dev = _lastDevice;
    if (dev == null) return;
    _userInitiatedDisconnect = false;
    DebugLog.log('BLE: resume — reconnecting to ${dev.platformName}');
    try {
      await connect(dev,
          sessionId: DateTime.now().millisecondsSinceEpoch.toString());
    } on Exception catch (e) {
      DebugLog.log('BLE: reconnect on resume failed: $e');
    }
  }

  void dispose() {
    disconnect();
    _importTimer?.cancel();
    _awaySettle?.cancel();
    _connectionState.close();
    _detections.close();
    _importedDetections.close();
    _awayLiveDetections.close();
    _spoolImport.close();
    _awayImport.close();
    _foxhunterRssiStream.close();
    _engineStates.close();
    _meshStatusStream.close();
    _wifiOtaStream.close();
    _fleetOtaStream.close();
    _pcapStatsStream.close();
    _pcapDataStream.close();
  }

  // -- PCAP --

  /// Start PCAP capture. mode 0 = WiFi radiotap, 1 = BLE LL PHDR.
  /// channelStart/End used only in WiFi mode (1..14).
  /// In manager mode, MGR broadcasts to all nodes; PCAPNG returned by MGR
  /// contains one interface per node (IDB-per-source).
  Future<void> startPcap({
    int mode = 0,
    int channelStart = 1,
    int channelEnd = 11,
    String? targetNodeId,
  }) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList(
          [0x01, mode, channelStart, channelEnd],
        ),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 50));
    await _engineControl!.write(
      BleProtocol.encodeEngineControl(
        engine: Engine.pcap, enable: true, targetNodeId: targetNodeId,
      ),
    );
  }

  Future<void> setWardriveNodeRadio(String nodeId, int radioMask) async {
    if (_engineControl == null) return;
    if (nodeId.length != 4) {
      throw ArgumentError('nodeId must be canonical 4-hex form, got "$nodeId"');
    }
    final m = radioMask & 0x03;
    final payload = <int>[
      ...BleProtocol.targetEnvelope(nodeId),
      m == 0 ? 0x03 : m,
    ];
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.wardrive,
        payload: Uint8List.fromList(payload),
      ),
    );
  }

  Future<void> stopPcap({String? targetNodeId}) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineControl(
        engine: Engine.pcap, enable: false, targetNodeId: targetNodeId,
      ),
    );
  }

  Future<void> clearPcap() async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList([0x03]), // PCAP_CTRL_CLEAR
      ),
    );
  }


  // -- Private --

  void _onDetection(List<int> data) {
    if (_importing) {
      _importTimer?.cancel();
      _importTimer = Timer(const Duration(seconds: 12), _abortImport);
      if (BleProtocol.isSpoolHeader(data)) {
        final h = BleProtocol.decodeSpoolHeader(data);
        _importTotal = h.count;
        _importDropped = h.dropped;
        _importDeviceNow = h.deviceNowMs;
        _spoolImport.add(SpoolImportProgress(seen: 0, total: _importTotal, dropped: _importDropped, done: false, aborted: false));
        return;
      }
      if (BleProtocol.isSpoolDone(data)) {
        _importTimer?.cancel();
        _importTimer = null;
        _importing = false;
        _spoolImport.add(SpoolImportProgress(seen: _importSeen, total: _importTotal, dropped: _importDropped, done: true, aborted: false));
        return;
      }
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
      _importSeen++;
      _importedDetections.add(detection);
      _noteAway();
      return;
    }
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
    if (data.isNotEmpty && (data[0] & 0x80) != 0) {
      _noteAway();
      _awayLiveDetections.add(detection);
    }
  }

  /// One genuine while-away capture arrived (manager spool flush, or a
  /// node-relayed spool detection flagged DET_FLAG_AWAY). Accumulate and
  /// finalize the banner a few seconds after the last one — counts only
  /// real away captures, never live re-announcements of present devices.
  void _noteAway() {
    _awaySeen++;
    _awaySettle?.cancel();
    _awayImport.add(SpoolImportProgress(
        seen: _awaySeen, total: 0, dropped: _importDropped, done: false, aborted: false));
    _awaySettle = Timer(const Duration(seconds: 3), () {
      _awayImport.add(SpoolImportProgress(
          seen: _awaySeen, total: _awaySeen, dropped: _importDropped, done: true, aborted: false));
      _awaySeen = 0;
    });
  }

  void _abortImport() {
    if (!_importing) return;
    _importTimer?.cancel();
    _importTimer = null;
    _importing = false;
    _spoolImport.add(SpoolImportProgress(seen: _importSeen, total: _importTotal, dropped: _importDropped, done: true, aborted: true));
    DebugLog.log('BLE: spool import aborted (timeout)');
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

  List<String> _parseDeviceInfo(List<int> data) {
    final out = <String>[];
    int start = 0;
    for (int i = 0; i < data.length; i++) {
      if (data[i] == 0) {
        out.add(String.fromCharCodes(data.sublist(start, i)));
        start = i + 1;
      }
    }
    if (start < data.length) {
      out.add(String.fromCharCodes(data.sublist(start)));
    }
    return out;
  }
}

final bleManagerProvider = Provider<BleManager>((ref) {
  final manager = BleManager();
  manager.setWatchlistGetter(() => ref.read(watchlistProvider).enabledEntries);
  ref.listen(watchlistProvider, (prev, next) {
    if (manager.currentConnectionState == NodeConnectionState.ready) {
      manager.syncDetectorWatchlist(next.enabledEntries);
    }
  });
  ref.onDispose(manager.dispose);
  return manager;
});
