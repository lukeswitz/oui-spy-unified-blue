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
import 'package:oui_spy/core/detector_signatures.dart';
import 'package:oui_spy/core/link/link_characteristic.dart';
import 'package:oui_spy/core/link/link_net.dart';
import 'package:oui_spy/core/link/link_session.dart';
import 'package:oui_spy/core/link/usb_serial.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:oui_spy/core/oui/flock_oui.dart';
import 'package:oui_spy/features/pcap/pcap_stats.dart';
import 'package:oui_spy/core/watchlist_state.dart';

class SpoolImportProgress {
  final int seen;
  final int total;
  final int dropped;
  final bool done;
  final bool aborted;
  final Map<String, int> byEngine;
  const SpoolImportProgress({
    required this.seen,
    required this.total,
    required this.dropped,
    required this.done,
    required this.aborted,
    this.byEngine = const {},
  });
}

class EnowHubNode {
  final String mac;
  final int rssi;
  final bool paired;
  final bool online;
  final bool encrypted;
  final int records;
  final String name;
  const EnowHubNode({
    required this.mac,
    required this.rssi,
    required this.paired,
    required this.online,
    required this.encrypted,
    required this.records,
    required this.name,
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

class BleManager {
  BleManager();

  BluetoothDevice? _device;
  BluetoothDevice? _lastDevice;
  LinkSession? _usbSession;
  UsbSerialDevice? _usbDevice;
  UsbSerialDevice? _lastUsbDevice;
  LinkCharacteristic? _engineControl;
  LinkCharacteristic? _detectionEvents;
  LinkCharacteristic? _deviceStatus;
  LinkCharacteristic? _gpsReceive;
  LinkCharacteristic? _hardwareConfig;
  LinkCharacteristic? _alertConfig;
  LinkCharacteristic? _ignoreList;
  LinkCharacteristic? _melody;
  LinkCharacteristic? _nodeRadio;
  LinkCharacteristic? _foxhunterRssi;
  LinkCharacteristic? _unipwnCommand;
  LinkCharacteristic? _foxhunterConfig;
  LinkCharacteristic? _meshConfig;
  LinkCharacteristic? _meshStatus;
  LinkCharacteristic? _dfuControl;
  LinkCharacteristic? _dfuData;
  LinkCharacteristic? _systemControl;
  LinkCharacteristic? _wifiConfig;
  LinkCharacteristic? _pcapStats;
  LinkCharacteristic? _pcapData;
  LinkCharacteristic? _detectorConfig;
  List<WatchlistEntry> Function()? _watchlistGetter;

  void setWatchlistGetter(List<WatchlistEntry> Function() getter) {
    _watchlistGetter = getter;
  }

  int Function()? _sigMaskGetter;

  void setDetectorSigMaskGetter(int Function() getter) {
    _sigMaskGetter = getter;
  }

  bool Function()? _flockOuiOnlyGetter;

  void setFlockOuiOnlyGetter(bool Function() getter) {
    _flockOuiOnlyGetter = getter;
  }

  final _connectionState = StreamController<NodeConnectionState>.broadcast();
  final _detections = StreamController<Detection>.broadcast();
  final _foxhunterRssiStream = StreamController<({int rssi, int intervalMs})>.broadcast();
  final _engineStates = StreamController<({int available, int active, List<EngineState> states})>.broadcast();
  final _meshStatusStream = StreamController<({bool enabled, int peerCount, int connectedPeers, int rxCount, int txCount, List<({String id, int role, int activeEngines, int fwVersion, String board, int? tempC})> liveNodes})>.broadcast();
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

  bool wardriveSessionActive = false;

  bool _importing = false;
  int _awaySeen = 0;
  final Map<String, int> _awayByEngine = {};
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
  final _wdLogFrames = StreamController<WdLogFrame>.broadcast();
  Stream<WdLogFrame> get wdLogFrames => _wdLogFrames.stream;

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
  bool _isReconnect = false;

  // -- Public streams --

  Stream<NodeConnectionState> get connectionState => _connectionState.stream;
  Stream<Detection> get detections => _detections.stream;
  Stream<({int rssi, int intervalMs})> get foxhunterRssi => _foxhunterRssiStream.stream;
  Stream<({int available, int active, List<EngineState> states})> get engineStates =>
      _engineStates.stream;
  Stream<({bool enabled, int peerCount, int connectedPeers, int rxCount, int txCount, List<({String id, int role, int activeEngines, int fwVersion, String board, int? tempC})> liveNodes})> get meshStatusUpdates =>
      _meshStatusStream.stream;
  Stream<PcapStats> get pcapStats => _pcapStatsStream.stream;
  Stream<Uint8List> get pcapData => _pcapDataStream.stream;
  PcapStats get latestPcapStats => _latestPcapStats;

  File? _pcapFile;
  IOSink? _pcapSink;
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
      int cap = _pcapRx.isEmpty ? 4096 : _pcapRx.length * 2;
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

  bool get isLinkSetup =>
      _currentState == NodeConnectionState.connecting ||
      _currentState == NodeConnectionState.negotiating ||
      _currentState == NodeConnectionState.syncing;
  String get nodeId => _nodeId;
  String get board => _board;

  static const supportedProtoVersion = 2;
  int? _protoVersion;
  int? _bootCount;
  bool _spoolStorageOk = true;
  bool _boardRestarted = true;
  final _lastEpochByNode = <String, String>{};
  int? get protoVersion => _protoVersion;
  int? get bootCount => _bootCount;
  bool get spoolStorageOk => _spoolStorageOk;
  bool get boardRestarted => _boardRestarted;

  static Map<String, String> deviceInfoKeyed(List<String> parts) => {
        for (final p in parts)
          if (p.indexOf('=') case final i when i > 0) p.substring(0, i): p.substring(i + 1),
      };
  bool get isC5 => _board.endsWith('c5');
  String get role => _role;
  String? get connectedDeviceId => _primaryDeviceId ?? _lastDeviceId;
  bool get isManagerConnected =>
      _role == 'mgr' ||
      (_role.isEmpty &&
          (_device?.platformName ?? '').toUpperCase().contains('OUI-SPY-MGR'));

  void markAsPrimary() {
    _primaryDeviceId = _lastDeviceId;
    final id = _primaryDeviceId;
    if (id != null && id.isNotEmpty) {
      final mgr = isManagerConnected;
      SharedPreferences.getInstance().then((p) {
        p.setString('lastPrimaryDeviceId', id);
        p.setBool('lastPrimaryIsManager', mgr);
      });
    }
  }

  /// Get a discovered characteristic by UUID (for direct read/write).
  LinkCharacteristic? getCharacteristic(Guid uuid) {
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
  LinkCharacteristic? get dfuControl => _dfuControl;
  LinkCharacteristic? get dfuData => _dfuData;
  LinkCharacteristic? get systemControl => _systemControl;
  LinkCharacteristic? get wifiConfig => _wifiConfig;

  LinkCharacteristic? _deviceInfoChar;

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

  static const phoneNodeId = 'PHONE';
  static const usbWifiNodeId = 'USBWIFI';
  static const usbBleNodeId = 'USBBLE';

  void addPhoneFoxRssi(int rssi, int intervalMs) =>
      _foxhunterRssiStream.add((rssi: rssi, intervalMs: intervalMs));

  void addPhoneDetection(String mac, String name, int rssi, List<int> adv,
      {String nodeId = phoneNodeId}) {
    final now = DateTime.now();
    final ext = WardriveExtension(deviceName: name);
    if (adv.isNotEmpty) wardriveAdvRaw[ext] = adv;
    _detections.add(Detection(
      id: '${mac}_${now.millisecondsSinceEpoch}',
      sessionId: _sessionId,
      nodeId: nodeId,
      macAddress: mac,
      engine: Engine.wardrive,
      method: 'ble_adv',
      rssi: rssi,
      channel: 0,
      deviceTimestampMs: 0,
      appTimestamp: now,
      deviceName: name,
      sourceNodeId: nodeId,
      latitude: _lastLat,
      longitude: _lastLon,
      accuracy: _lastAccuracy,
      satelliteCount: _lastSatCount,
      wardrive: ext,
    ));
  }

  void addPhoneWifiDetection(String bssid, String ssid, int rssi, int channel, int authMode,
      {String nodeId = phoneNodeId, bool client = false}) {
    final now = DateTime.now();
    _detections.add(Detection(
      id: '${bssid}_${now.millisecondsSinceEpoch}',
      sessionId: _sessionId,
      nodeId: nodeId,
      macAddress: bssid,
      engine: Engine.wardrive,
      method: client ? 'wifi_client' : 'wifi_ap',
      rssi: rssi,
      channel: channel,
      deviceTimestampMs: 0,
      appTimestamp: now,
      ssid: ssid,
      sourceNodeId: nodeId,
      latitude: _lastLat,
      longitude: _lastLon,
      accuracy: _lastAccuracy,
      satelliteCount: _lastSatCount,
      wardrive: WardriveExtension(ssid: ssid, authMode: authMode),
    ));
    if ((_flockOuiOnlyGetter?.call() ?? false) && FlockOui.match(bssid)) {
      _detections.add(Detection(
        id: '${bssid}_flock_${now.millisecondsSinceEpoch}',
        sessionId: _sessionId,
        nodeId: nodeId,
        macAddress: bssid,
        engine: Engine.flockWifi,
        method: client ? 'oui_addr2' : 'oui_addr3',
        rssi: rssi,
        channel: channel,
        deviceTimestampMs: 0,
        appTimestamp: now,
        ssid: ssid,
        sourceNodeId: nodeId,
        latitude: _lastLat,
        longitude: _lastLon,
        accuracy: _lastAccuracy,
        satelliteCount: _lastSatCount,
        flock: const FlockExtension(signals: FlockSignal.oui),
      ));
    }
  }

  // -- Scanning --

  /// Scan for OUI-SPY devices. Results arrive on FlutterBluePlus.onScanResults.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    // Ensure BLE adapter is on
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }

    await FlutterBluePlus.startScan(withServices: [GattUuids.service], timeout: timeout);
  }

  /// Stream of scan results (list updated each scan cycle).
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.onScanResults;

  Future<void> stopScan() async => FlutterBluePlus.stopScan();

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

  Future<BluetoothDevice?> _scanForRemoteId(String remoteId,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final completer = Completer<BluetoothDevice?>();
    final sub = scanResults.listen((results) {
      for (final r in results) {
        if (r.device.remoteId.toString() == remoteId && !completer.isCompleted) {
          completer.complete(r.device);
        }
      }
    });
    try {
      await startScan(timeout: timeout);
    } on Exception catch (e) {
      DebugLog.log('BLE: reconnect scan error $e');
    }
    final found = await completer.future
        .timeout(timeout + const Duration(seconds: 2), onTimeout: () => null);
    await sub.cancel();
    await stopScan();
    return found;
  }

  static const _pairedBoardsPref = 'pairedBoards';

  static List<String> pairedEntriesWith(List<String> entries, String id, String name) =>
      [...entries.where((e) => e.split('|').first != id), '$id|$name'];

  static List<String> pairedEntriesWithout(List<String> entries, String id) =>
      entries.where((e) => e.split('|').first != id).toList();

  static List<({String id, String name})> parsePairedEntries(List<String> entries) => [
        for (final e in entries)
          if (e.split('|') case [final id, final name]) (id: id, name: name),
      ];

  Future<void> _rememberPaired(String id, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_pairedBoardsPref,
        pairedEntriesWith(p.getStringList(_pairedBoardsPref) ?? const [], id, name));
  }

  static Future<void> forgetPaired(String id) async {
    if (Platform.isAndroid) {
      await BluetoothDevice.fromId(id).removeBond();
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_pairedBoardsPref,
        pairedEntriesWithout(p.getStringList(_pairedBoardsPref) ?? const [], id));
  }

  static Future<List<({String id, String name})>> pairedBoards() async {
    if (Platform.isAndroid) {
      final bonded = await FlutterBluePlus.bondedDevices;
      return [
        for (final d in bonded)
          if (d.platformName.startsWith('OUI-SPY')) (id: d.remoteId.toString(), name: d.platformName),
      ];
    }
    final p = await SharedPreferences.getInstance();
    return parsePairedEntries(p.getStringList(_pairedBoardsPref) ?? const []);
  }

  Future<bool> connectAndReady(BluetoothDevice device,
      {Duration timeout = const Duration(seconds: 25), bool autoConnect = false}) async {
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
          sessionId: 'ota-${DateTime.now().microsecondsSinceEpoch}', autoConnect: autoConnect);
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
      {Duration timeout = const Duration(seconds: 25), bool autoConnect = false}) async {
    try {
      final ok = await connectAndReady(BluetoothDevice.fromId(remoteId),
          timeout: timeout, autoConnect: autoConnect);
      if (!ok && autoConnect) await disconnectQuiet();
      return ok;
    } on Exception catch (e) {
      DebugLog.log('BLE: connectByIdAndReady error $e');
      return false;
    }
  }

  // -- Connection --

  /// Connect to a specific device and set up GATT subscriptions.
  Future<void> connect(BluetoothDevice device, {required String sessionId, bool autoConnect = false}) async {
    if (_connecting) {
      DebugLog.log('BLE: connect in flight — ignoring duplicate ${device.remoteId}');
      return;
    }
    _connecting = true;
    try {
      await _doConnect(device, sessionId: sessionId, autoConnect: autoConnect);
    } catch (e) {
      if (!_isReconnect && isLinkSetup) {
        _currentState = NodeConnectionState.disconnected;
        _connectionState.add(NodeConnectionState.disconnected);
      }
      rethrow;
    } finally {
      _connecting = false;
      _isReconnect = false;
    }
  }

  bool get isUsbLinked => _usbSession?.isOpen ?? false;
  UsbSerialDevice? get usbDevice => _usbDevice;
  UsbSerialDevice? get lastUsbDevice => _lastUsbDevice;

  Future<void> connectUsb(UsbSerialDevice device, {required String sessionId}) => _connectLink(
        () => UsbSerial.open(device),
        label: '${device.vidPid} ${device.name}',
        linkName: device.name,
        usb: device,
        sessionId: sessionId,
      );

  Future<void> connectNetLink(NetLinkTarget target, {required String sessionId}) => _connectLink(
        target.open,
        label: target.label,
        linkName: '',
        usb: null,
        sessionId: sessionId,
      );

  Future<void> _connectLink(
    Future<LinkTransport> Function() open, {
    required String label,
    required String linkName,
    required UsbSerialDevice? usb,
    required String sessionId,
  }) async {
    if (_connecting) {
      DebugLog.log('USB: connect in flight — ignoring $label');
      return;
    }
    _connecting = true;
    try {
      await _doConnectLink(open,
          label: label, linkName: linkName, usb: usb, sessionId: sessionId);
    } catch (e) {
      await _usbSession?.close();
      _usbSession = null;
      _usbDevice = null;
      _currentState = NodeConnectionState.disconnected;
      _connectionState.add(NodeConnectionState.disconnected);
      rethrow;
    } finally {
      _connecting = false;
      _isReconnect = false;
    }
  }

  Future<void> _doConnectLink(
    Future<LinkTransport> Function() open, {
    required String label,
    required String linkName,
    required UsbSerialDevice? usb,
    required String sessionId,
  }) async {
    if (_device != null || _usbSession != null) {
      DebugLog.log('USB: dropping current link before USB connect');
      await disconnectQuiet();
    }
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _reconnectTimer?.cancel();

    _sessionId = sessionId;
    _userInitiatedDisconnect = false;
    _currentState = NodeConnectionState.connecting;
    _connectionState.add(NodeConnectionState.connecting);
    DebugLog.log('USB: opening $label');
    final session = LinkSession(await open());
    _usbSession = session;
    _usbDevice = usb;
    if (usb != null) _lastUsbDevice = usb;

    _currentState = NodeConnectionState.negotiating;
    _connectionState.add(NodeConnectionState.negotiating);
    await session.open();
    _mtu = 247;
    DebugLog.log('USB: link up, ${session.ids.length} characteristics, max payload ${session.maxPayload}');

    session.done.then((_) {
      if (!identical(_usbSession, session)) return;
      DebugLog.log('USB: link closed (crcErrors=${session.crcErrors})');
      _usbSession = null;
      _usbDevice = null;
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      if (_importing) _abortImport();
      _currentState = NodeConnectionState.disconnected;
      _connectionState.add(NodeConnectionState.disconnected);
    });

    _currentState = NodeConnectionState.syncing;
    _connectionState.add(NodeConnectionState.syncing);
    _clearCharacteristics();
    for (final id in session.ids) {
      _assignCharacteristic(UsbLinkCharacteristic(session, linkGuidFor(id, GattUuids.service)));
    }
    await _finishConnect(linkName: linkName, dropLink: session.close);
  }

  static const autoConnectWait = Duration(seconds: 20);

  static bool _isStaticRandom(String mac) {
    final first = int.tryParse(mac.length >= 2 ? mac.substring(0, 2) : '', radix: 16);
    return first != null && (first & 0xC0) == 0xC0;
  }

  // Reconnect via the bonded identity, not the scanned RPA (Android keys the bond to the identity).
  Future<BluetoothDevice> _preferBondedIdentity(BluetoothDevice device) async {
    if (!Platform.isAndroid) return device;
    try {
      final want = device.platformName.isNotEmpty
          ? device.platformName
          : (_role == 'mgr' ? 'OUI-SPY-MGR' : 'OUI-SPY');
      // Swap only on a single unambiguous name match, never with multiple same-named bonds.
      final matches = (await FlutterBluePlus.bondedDevices)
          .where((b) =>
              b.platformName == want &&
              b.remoteId != device.remoteId &&
              _isStaticRandom(b.remoteId.str))
          .toList();
      if (matches.length == 1) {
        DebugLog.log('BLE: using bonded identity ${matches.first.remoteId} for RPA ${device.remoteId}');
        return matches.first;
      }
    } catch (e) {
      DebugLog.log('BLE: bonded-identity lookup failed: $e');
    }
    return device;
  }

  Future<void> _doConnect(BluetoothDevice device, {required String sessionId, bool autoConnect = false}) async {
    device = await _preferBondedIdentity(device);
    // Clean up previous subscriptions to prevent reconnect storm
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _reconnectTimer?.cancel();

    _sessionId = sessionId;
    _device = device;
    _userInitiatedDisconnect = false;
    _currentState = NodeConnectionState.connecting; _connectionState.add(NodeConnectionState.connecting);

    _lastDeviceId = device.remoteId.toString();
    DebugLog.log('BLE: connecting to ${device.remoteId}${autoConnect ? ' (OS autoConnect)' : ''}');
    if (autoConnect) {
      await device.connect(autoConnect: true, mtu: null);
      try {
        await device.connectionState
            .firstWhere((s) => s == BluetoothConnectionState.connected || _userInitiatedDisconnect)
            .timeout(autoConnectWait);
      } on TimeoutException {
        DebugLog.log('BLE: autoConnect did not complete in ${autoConnectWait.inSeconds}s — canceling');
        await device.disconnect();
        rethrow;
      }
    } else {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
    }
    if (_userInitiatedDisconnect || _device != device) {
      DebugLog.log('BLE: disconnect requested during connect — aborting');
      await device.disconnect();
      return;
    }
    DebugLog.log('BLE: connected');

    _subscriptions.add(
      device.connectionState.listen((state) {
        DebugLog.log('BLE: connectionState=$state');
        if (state == BluetoothConnectionState.disconnected) {
          _livenessTimer?.cancel();
          _livenessTimer = null;
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

    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      DebugLog.log('BLE: requested high conn priority');
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('BLE: conn priority unsupported: ${e.description}');
    }

    if (Platform.isAndroid) {
      try {
        final bond = await device.bondState.first;
        if (bond != BluetoothBondState.bonded) {
          DebugLog.log('BLE: not bonded ($bond) — requesting the OS pairing prompt');
          await device.createBond(timeout: 90);
          DebugLog.log('BLE: bonded');
        }
      } on FlutterBluePlusException catch (e) {
        DebugLog.log('BLE: createBond failed: ${e.description}');
        await disconnect();
        rethrow;
      }
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
    _clearCharacteristics();
    for (final c in ouiService.characteristics) {
      _assignCharacteristic(BleLinkCharacteristic(c));
    }

    await _finishConnect(linkName: device.platformName, dropLink: device.disconnect);
  }

  void _clearCharacteristics() {
    _engineControl = null;
    _detectionEvents = null;
    _deviceStatus = null;
    _gpsReceive = null;
    _hardwareConfig = null;
    _alertConfig = null;
    _ignoreList = null;
    _melody = null;
    _nodeRadio = null;
    _foxhunterRssi = null;
    _unipwnCommand = null;
    _foxhunterConfig = null;
    _meshConfig = null;
    _meshStatus = null;
    _dfuControl = null;
    _dfuData = null;
    _systemControl = null;
    _wifiConfig = null;
    _pcapStats = null;
    _pcapData = null;
    _detectorConfig = null;
    _deviceInfoChar = null;
  }

  void _assignCharacteristic(LinkCharacteristic c) {
    if (c.uuid == GattUuids.engineControl) _engineControl = c;
    if (c.uuid == GattUuids.detectionEvents) _detectionEvents = c;
    if (c.uuid == GattUuids.deviceStatus) _deviceStatus = c;
    if (c.uuid == GattUuids.gpsReceive) _gpsReceive = c;
    if (c.uuid == GattUuids.hardwareConfig) _hardwareConfig = c;
    if (c.uuid == GattUuids.alertConfig) _alertConfig = c;
    if (c.uuid == GattUuids.ignoreList) _ignoreList = c;
    if (c.uuid == GattUuids.melody) _melody = c;
    if (c.uuid == GattUuids.nodeRadio) _nodeRadio = c;
    if (c.uuid == GattUuids.foxhunterRssi) _foxhunterRssi = c;
    if (c.uuid == GattUuids.unipwnCommand) _unipwnCommand = c;
    if (c.uuid == GattUuids.foxhunterConfig) _foxhunterConfig = c;
    if (c.uuid == GattUuids.meshConfig) _meshConfig = c;
    if (c.uuid == GattUuids.meshStatus) _meshStatus = c;
    if (c.uuid == GattUuids.dfuControl) _dfuControl = c;
    if (c.uuid == GattUuids.dfuData) _dfuData = c;
    if (c.uuid == GattUuids.systemControl) _systemControl = c;
    if (c.uuid == GattUuids.wifiConfig) _wifiConfig = c;
    if (c.uuid == GattUuids.pcapStats) _pcapStats = c;
    if (c.uuid == GattUuids.pcapData) _pcapData = c;
    if (c.uuid == GattUuids.detectorConfig) _detectorConfig = c;
    if (c.uuid == GattUuids.deviceInfo) _deviceInfoChar ??= c;
  }

  Future<void> _finishConnect({
    required String linkName,
    required Future<void> Function() dropLink,
  }) async {
    // Read device info to get node ID
    final info = _deviceInfoChar;
    if (info == null) throw Exception('OUI-SPY device info characteristic not found');
    final infoData = await info.read();
    final parts = _parseDeviceInfo(infoData);
    _nodeId = parts.length > 1 ? parts[1] : '';
    _board = parts.length > 2 ? parts[2] : '';
    _role = parts.length > 3 ? parts[3] : '';
    final kv = deviceInfoKeyed(parts);
    _protoVersion = int.tryParse(kv['proto'] ?? '');
    _bootCount = int.tryParse(kv['boot'] ?? '');
    _spoolStorageOk = kv['spool'] != '0';
    final linked = _device;
    if (linked != null && !Platform.isAndroid) {
      unawaited(_rememberPaired(linked.remoteId.toString(), _role == 'mgr' ? 'OUI-SPY-MGR' : 'OUI-SPY'));
    }
    final epoch = kv['epoch'];
    final prevEpoch = _lastEpochByNode[_nodeId];
    _boardRestarted = epoch == null || prevEpoch == null || prevEpoch != epoch;
    if (epoch != null) _lastEpochByNode[_nodeId] = epoch;
    DebugLog.log('BLE: nodeId=$_nodeId board=$_board role=$_role proto=$_protoVersion boot=$_bootCount '
        'epoch=$epoch restarted=$_boardRestarted spoolOk=$_spoolStorageOk');
    if (_protoVersion != null && _protoVersion! > supportedProtoVersion) {
      DebugLog.log('BLE: firmware protocol $_protoVersion is newer than this app ($supportedProtoVersion) — update the app');
    }
    final expect = _reconnectExpectNodeId;
    if (expect != null && _nodeId != expect) {
      DebugLog.log('BLE: reconnect reached $_nodeId, expected $expect — dropping it untouched');
      for (final sub in _subscriptions) {
        await sub.cancel();
      }
      _subscriptions.clear();
      await dropLink();
      _currentState = NodeConnectionState.reconnecting;
      _connectionState.add(NodeConnectionState.reconnecting);
      throw Exception('reconnect: different board');
    }
    _reconnectRejected.clear();
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
          _lastRx = DateTime.now();
          _engineStates.add(BleProtocol.decodeEngineStatus(data));
        }),
      );
      final isMgr = _role == 'mgr' ||
          (_role.isEmpty &&
              linkName.toUpperCase().contains('OUI-SPY-MGR'));
      if (!isMgr && !_offlineScanEnabled && !wardriveSessionActive && !_isReconnect) {
        await _engineControl!.write(BleProtocol.encodeDisableAll());
        DebugLog.log('BLE: sent DISABLE_ALL on fresh connect (node)');
        await Future.delayed(const Duration(milliseconds: 300));
      } else if (!isMgr && (_isReconnect || wardriveSessionActive)) {
        DebugLog.log('BLE: reconnect/active session — adopting firmware engine state, no DISABLE_ALL');
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
    _lastRx = DateTime.now();
    _livenessTimer?.cancel();
    _livenessTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkLiveness());

    final getter = _watchlistGetter;
    if (getter != null && _detectorConfig != null) {
      try {
        await syncDetectorWatchlist(getter());
      } catch (e) {
        DebugLog.log('BLE: watchlist sync failed: $e');
      }
    }

    final sigGetter = _sigMaskGetter;
    if (sigGetter != null && _detectorConfig != null) {
      try {
        await setDetectorSigMask(sigGetter());
      } catch (e) {
        DebugLog.log('BLE: sigmask sync failed: $e');
      }
    }

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
          } else if (data[0] == 0x12) {
            final frame = BleProtocol.decodeWdLogFrame(data);
            if (frame != null) _wdLogFrames.add(frame);
          } else if (data[0] == 0x08 && data.length >= 5) {
            _fleetOtaStream.add((
              phase: data[1],
              pct: data[2],
              done: data[3],
              seen: data[4],
            ));
          } else if (data[0] == 0x0F && data.length >= 8) {
            enowHubActive = data[1] == 1;
            if (!enowHubActive) {
              enowHubNodeMap.clear();
              _enowUnique.clear();
            }
            _enowHubStream.add((
              active: data[1] == 1,
              nodes: data[2],
              refuse: data[3],
              records: data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24),
            ));
          } else if (data[0] == 0x10 && data.length >= 14) {
            final n = data[13];
            final node = EnowHubNode(
              mac: _macHex(data.sublist(1, 7)),
              rssi: data[7] >= 128 ? data[7] - 256 : data[7],
              paired: data[8] & 0x01 != 0,
              online: data[8] & 0x02 != 0,
              encrypted: data[8] & 0x04 != 0,
              records: data[9] | (data[10] << 8) | (data[11] << 16) | (data[12] << 24),
              name: data.length >= 14 + n ? utf8.decode(data.sublist(14, 14 + n), allowMalformed: true) : '',
            );
            enowHubNodeMap[node.mac] = node;
            _enowNodeStream.add(node);
          } else if (data[0] == 0x11 && data.length >= 15) {
            final body = data.sublist(15).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            DebugLog.log('ENOW-CAP ${_macHex(data.sublist(1, 7))}>${_macHex(data.sublist(7, 13))} '
                'len=${data[13] | (data[14] << 8)} $body');
          } else if (data[0] == 0x0E && data.length >= 3) {
            final mac = data.length >= 9
                ? data.sublist(3, 9).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase()
                : '';
            _ringResultStream.add((mac: mac, status: data[1], protocol: data[2]));
          }
        }),
      );
    }

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
    _awayByEngine.clear();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPendingSpoolClear) ?? false) {
      await clearBoardBacklog();
    }
    if (_offlineScanEnabled) {
      await requestSpoolFlush();
      await _systemControl?.write(BleProtocol.wdLogSendCmd, withoutResponse: false);
    }
  }

  Future<bool> confirmWdLogImported() async {
    if (_systemControl == null) return false;
    await _systemControl!.write(BleProtocol.wdLogClearCmd, withoutResponse: false);
    return true;
  }

  static const _kPendingSpoolClear = 'pendingSpoolClear';

  Future<void> clearBoardBacklog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPendingSpoolClear, true);
    if (_systemControl == null) return;
    try {
      await _systemControl!.write(BleProtocol.spoolClearCmd, withoutResponse: false);
      await prefs.setBool(_kPendingSpoolClear, false);
      DebugLog.log('BLE: board spool cleared');
    } on Exception catch (e) {
      DebugLog.log('BLE: board spool clear failed, retry on next connect: $e');
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

  final _ringResultStream = StreamController<({String mac, int status, int protocol})>.broadcast();
  Stream<({String mac, int status, int protocol})> get ringResults => _ringResultStream.stream;

  final _enowHubStream = StreamController<({bool active, int nodes, int refuse, int records})>.broadcast();
  Stream<({bool active, int nodes, int refuse, int records})> get enowHubStatus => _enowHubStream.stream;

  final _enowNodeStream = StreamController<EnowHubNode>.broadcast();
  Stream<EnowHubNode> get enowHubNodes => _enowNodeStream.stream;
  bool enowHubActive = false;
  final Map<String, EnowHubNode> enowHubNodeMap = {};
  final Set<String> _enowSkipped = {};
  final Map<String, Set<String>> _enowUnique = {};

  static String enowSourceId(String mac) {
    final b = _macBytes(mac);
    if (b == null) return '';
    return 'E${(((b[4] << 8) | b[5]) & 0xFFF).toRadixString(16).toUpperCase().padLeft(3, '0')}';
  }

  int enowNetworksFor(String mac) => _enowUnique[enowSourceId(mac)]?.length ?? 0;

  int get enowNetworksTotal => {for (final s in _enowUnique.values) ...s}.length;

  Future<void> enowHubRefresh() async {
    if (_systemControl == null) return;
    final status = enowHubStatus.first.timeout(const Duration(milliseconds: 1500));
    await enowHubPoll();
    try {
      await status;
    } on TimeoutException {
      return;
    }
    while (true) {
      try {
        await enowHubNodes.first.timeout(const Duration(milliseconds: 250));
      } on TimeoutException {
        return;
      }
    }
  }

  Future<void> enowHubSkipForSession(Set<String> macs) async {
    for (final m in macs) {
      if (await enowHubPair(m, pair: false)) _enowSkipped.add(m);
    }
  }

  Future<void> enowHubRestoreSkipped() async {
    final macs = Set.of(_enowSkipped);
    _enowSkipped.clear();
    for (final m in macs) {
      await enowHubPair(m);
    }
  }

  static String _macHex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

  static List<int>? _macBytes(String mac) {
    final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (hex.length != 12) return null;
    return [for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  Future<bool> enowHubPair(String mac, {bool pair = true}) async {
    final b = _macBytes(mac);
    if (_systemControl == null || b == null) return false;
    await _systemControl!.write(Uint8List.fromList([0x0F, 0xC0, 0xDE, pair ? 3 : 4, ...b]), withoutResponse: false);
    return true;
  }

  Future<void> enowHubCapture(bool on) async {
    if (_systemControl == null) return;
    await _systemControl!.write(Uint8List.fromList([0x0F, 0xC0, 0xDE, 5, on ? 1 : 0]), withoutResponse: false);
  }

  Future<bool> enowHub({required bool start, String passphrase = '', List<String> allowlist = const []}) async {
    if (_systemControl == null) return false;
    final pass = utf8.encode(passphrase);
    if (pass.length > 32 || allowlist.length > 16) return false;
    final macs = <int>[];
    for (final m in allowlist) {
      final b = _macBytes(m);
      if (b == null) return false;
      macs.addAll(b);
    }
    await _systemControl!.write(
      Uint8List.fromList(start
          ? [0x0F, 0xC0, 0xDE, 1, pass.length, ...pass, allowlist.length, ...macs]
          : [0x0F, 0xC0, 0xDE, 0]),
      withoutResponse: false,
    );
    return true;
  }

  Future<void> enowHubPoll() async {
    if (_systemControl == null) return;
    await _systemControl!.write(Uint8List.fromList([0x0F, 0xC0, 0xDE, 2]), withoutResponse: false);
  }

  Future<bool> ringTracker(String mac) async {
    if (_systemControl == null) return false;
    final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (hex.length != 12) return false;
    final bytes = [for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
    final random = (bytes[0] & 0xC0) != 0;
    await _systemControl!.write(
      Uint8List.fromList([0x0E, 0xC0, 0xDE, ...bytes, random ? 1 : 0]),
      withoutResponse: false,
    );
    return true;
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

  Future<bool> confirmSpoolImported() async {
    if (_systemControl == null) return false;
    await _systemControl!.write(BleProtocol.spoolClearCmd, withoutResponse: false);
    DebugLog.log('BLE: spool clear sent after DB commit');
    return true;
  }

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

  bool get hasMelodySupport => _melody != null;

  Future<void> writeMelodyOps(List<List<int>> ops) async {
    final c = _melody;
    if (c == null) return;
    try {
      for (final op in ops) {
        await c.write(op, withoutResponse: false);
      }
    } catch (e) {
      DebugLog.log('BLE: melody write failed: $e');
    }
  }

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
  }

  Future<void> sendEngineConfig(Engine engine, Uint8List payload) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(engine: engine, payload: payload),
    );
  }

  /// Push the global WiFi band mask (bit0=2.4GHz, bit1=5GHz) to all WiFi engines.
  Future<void> sendWifiBand(int mask) async {
    if (_engineControl == null) return;
    await _engineControl!.write(BleProtocol.encodeWifiBand(mask));
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

  Future<void> setDetectorSigMask(int mask) async {
    if (_detectorConfig == null) {
      DebugLog.log('BLE: detectorConfig char missing; skip sigmask');
      return;
    }
    await _detectorConfig!
        .write(Uint8List.fromList([0x03, mask & 0xFF, (mask >> 8) & 0xFF]), withoutResponse: false);
    DebugLog.log('BLE: detector sigmask=0x${(mask & 0xFFFF).toRadixString(16)}');
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

  Future<int> readCommandedEngineMask() async {
    if (_engineControl == null) return -1;
    try {
      final data = await _engineControl!.read();
      final status = BleProtocol.decodeEngineStatus(data);
      _engineStates.add(status);
      return commandedEngineMask(status.states);
    } catch (e) {
      DebugLog.log('BLE: commanded-engine-mask read failed: $e');
      return -1;
    }
  }

  Future<void> resyncOnResume() async {
    if (_currentState != NodeConnectionState.ready || (_device == null && !isUsbLinked)) {
      if (_device != null &&
          !_userInitiatedDisconnect &&
          _currentState != NodeConnectionState.connecting &&
          _currentState != NodeConnectionState.negotiating &&
          _currentState != NodeConnectionState.syncing) {
        DebugLog.log('BLE: resume — link down, restarting reconnect loop');
        _startReconnect();
      } else if (_device == null && _lastDevice != null) {
        DebugLog.log('BLE: resume — device torn down on detach, reconnecting to last');
        await reconnectPrimary();
      } else {
        DebugLog.log('BLE: resume — not connected, autoconnect handles it');
      }
      return;
    }
    DebugLog.log('BLE: app resumed — reconcile to firmware state');
    try {
      await _readDeviceConfig();
      await _refreshEngineState();
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
    if (_currentState != NodeConnectionState.ready) return;
    try {
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
    } on Exception catch (e) {
      DebugLog.log('BLE: GPS push dropped: $e');
    }
  }

  Future<GpsStatus?> readGpsStatus() async {
    if (_gpsReceive == null || !isConnected) return null;
    try {
      return BleProtocol.decodeGpsStatus(await _gpsReceive!.read());
    } catch (e) {
      DebugLog.log('BLE: GPS status read failed: $e');
      return null;
    }
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
    bool allowOuiOnly = false,
    int? radioPolicy,
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
        allowOuiOnly: allowOuiOnly,
        radioPolicy: radioPolicy,
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
    _reconnectTimer?.cancel();
    DebugLog.log('BLE: disconnect — leaving engine state to firmware (offline-scan aware)');
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    try {
      await _device?.disconnect(queue: false);
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('BLE: device.disconnect failed: ${e.description}');
    }
    _device = null;
    _role = '';
    await _closeUsb();
    _currentState = NodeConnectionState.disconnected; _connectionState.add(NodeConnectionState.disconnected);
  }

  Future<void> _closeUsb() async {
    final session = _usbSession;
    _usbSession = null;
    _usbDevice = null;
    await session?.close();
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
    _role = '';
    await _closeUsb();
    _currentState = NodeConnectionState.disconnected;
    _connectionState.add(NodeConnectionState.disconnected);
  }

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
    _isReconnect = true;
    signalAutoReconnect(true);
    DebugLog.log('BLE: resume — reconnecting to ${dev.platformName}');
    try {
      await connect(dev,
          sessionId: DateTime.now().millisecondsSinceEpoch.toString());
    } on Exception catch (e) {
      if (_currentState != NodeConnectionState.ready) {
        _currentState = NodeConnectionState.disconnected;
        _connectionState.add(NodeConnectionState.disconnected);
      }
      DebugLog.log('BLE: reconnect on resume failed: $e');
    }
  }

  void dispose() {
    disconnect();
    _livenessTimer?.cancel();
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
    _wdLogFrames.close();
    _fleetOtaStream.close();
    _pcapStatsStream.close();
    _pcapDataStream.close();
  }

  // -- PCAP --

  Future<void> startPcap({
    int mode = 0,
    int channelStart = 1,
    int channelEnd = 11,
    int mode5g = 1,
    String? targetNodeId,
  }) async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList(
          [0x01, mode, channelStart, channelEnd, 0x00, mode5g & 0x03],
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

  Future<void> pausePcap() async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList([0x04]), // PCAP_CTRL_PAUSE
      ),
    );
  }

  Future<void> resumePcap() async {
    if (_engineControl == null) return;
    await _engineControl!.write(
      BleProtocol.encodeEngineConfig(
        engine: Engine.pcap,
        payload: Uint8List.fromList([0x05]), // PCAP_CTRL_RESUME
      ),
    );
  }


  // -- Private --

  static const linkSilenceLimit = Duration(seconds: 20);
  DateTime _lastRx = DateTime.now();
  Timer? _livenessTimer;
  bool _probing = false;

  Future<void> _checkLiveness() async {
    final c = _engineControl;
    final d = _device;
    if (_probing || c == null || d == null || _currentState != NodeConnectionState.ready) return;
    if (DateTime.now().difference(_lastRx) < linkSilenceLimit) return;
    _probing = true;
    try {
      await c.read().timeout(const Duration(seconds: 5));
      _lastRx = DateTime.now();
    } catch (e) {
      DebugLog.log('BLE: link silent ${linkSilenceLimit.inSeconds}s and probe read failed ($e), dropping link to reconnect');
      try {
        await d.disconnect();
      } catch (e2) {
        DebugLog.log('BLE: disconnect after failed probe threw: $e2');
      }
    } finally {
      _probing = false;
    }
  }

  void _onDetection(List<int> data) {
    _lastRx = DateTime.now();
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
      if (data.length < 14) return;
      final detection = BleProtocol.decodeDetection(
        data,
        sessionId: _sessionId,
        nodeId: _nodeId,
        appTimestamp: DateTime.now(),
        latitude: null,
        longitude: null,
        accuracy: null,
        satelliteCount: null,
      );
      _importSeen++;
      _importedDetections.add(detection);
      _noteAway(detection);
      return;
    }
    if (data.length < 14) return;
    final isAway = data.isNotEmpty && (data[0] & 0x80) != 0;
    final detection = BleProtocol.decodeDetection(
      data,
      sessionId: _sessionId,
      nodeId: _nodeId,
      appTimestamp: DateTime.now(),
      latitude: isAway ? null : _lastLat,
      longitude: isAway ? null : _lastLon,
      accuracy: isAway ? null : _lastAccuracy,
      satelliteCount: isAway ? null : _lastSatCount,
    );
    _detections.add(detection);
    final src = detection.sourceNodeId;
    if (enowHubActive && src.length == 4 && src.startsWith('E')) {
      (_enowUnique[src] ??= {}).add(detection.macAddress.toUpperCase());
    }
    if (isAway) {
      _noteAway(detection);
      _awayLiveDetections.add(detection);
    }
  }

  void _noteAway(Detection detection) {
    _awaySeen++;
    _awayByEngine[detection.engine.name] =
        (_awayByEngine[detection.engine.name] ?? 0) + 1;
    _awaySettle?.cancel();
    _awayImport.add(SpoolImportProgress(
        seen: _awaySeen, total: 0, dropped: _importDropped, done: false,
        aborted: false, byEngine: Map.of(_awayByEngine)));
    _awaySettle = Timer(const Duration(seconds: 3), () {
      _awayImport.add(SpoolImportProgress(
          seen: _awaySeen, total: _awaySeen, dropped: _importDropped, done: true,
          aborted: false, byEngine: Map.of(_awayByEngine)));
      _awaySeen = 0;
      _awayByEngine.clear();
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
  bool _connecting = false;

  void _startReconnect() {
    if (_device == null) return;
    if (_connecting || (_reconnectTimer?.isActive ?? false)) return;
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
      if (_device == null || _userInitiatedDisconnect) return;
      final target = _device!;
      final expectNodeId = _nodeId;
      final expectRole = _role;
      final expectMgr = expectRole == 'mgr';
      var bonded = false;
      if (Platform.isAndroid) {
        try {
          bonded = (await FlutterBluePlus.bondedDevices).any((b) => b.remoteId == target.remoteId);
        } catch (e) {
          DebugLog.log('BLE: bond lookup failed: $e');
        }
      } else {
        bonded = (await pairedBoards()).any((b) => b.id == target.remoteId.toString());
      }
      if (_device == null || _userInitiatedDisconnect) return;
      final useAuto = bonded || (Platform.isAndroid && _reconnectAttempt.isOdd);
      var found = useAuto ? target : await _scanForRemoteId(target.remoteId.toString());
      if (found == null && expectNodeId.isNotEmpty) {
        found = await _scanForSameRole(expectMgr, exclude: _reconnectRejected);
        if (found != null) {
          DebugLog.log('BLE: saved id gone — trying ${found.remoteId} (address may have rotated)');
        }
      }
      if (_device == null || _userInitiatedDisconnect) return;
      if (found == null) {
        DebugLog.log('BLE: board not seen in reconnect scan — scanning again');
        _reconnectAttempt++;
        _attemptReconnect();
        return;
      }
      _isReconnect = true;
      _reconnectExpectNodeId = expectNodeId.isEmpty ? null : expectNodeId;
      try {
        await connect(found, sessionId: _sessionId, autoConnect: useAuto);
      } catch (e) {
        DebugLog.log('BLE: reconnect attempt failed: $e');
      } finally {
        _reconnectExpectNodeId = null;
      }
      if (_currentState == NodeConnectionState.ready &&
          _device != target &&
          _primaryDeviceId == target.remoteId.toString()) {
        markAsPrimary();
      }
      if (_device != null &&
          !_userInitiatedDisconnect &&
          _currentState != NodeConnectionState.ready) {
        if (_device != target) {
          _reconnectRejected.add(_device!.remoteId.toString());
          _device = target;
          _nodeId = expectNodeId;
          _role = expectRole;
        }
        _reconnectAttempt++;
        _attemptReconnect();
      }
    });
  }

  String? _reconnectExpectNodeId;
  final Set<String> _reconnectRejected = {};

  Future<BluetoothDevice?> _scanForSameRole(bool mgr,
      {required Set<String> exclude,
      Duration timeout = const Duration(seconds: 6)}) async {
    final completer = Completer<BluetoothDevice?>();
    final sub = scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.toString();
        if (exclude.contains(id)) continue;
        final n = '${r.device.platformName} ${r.advertisementData.advName}'.toUpperCase();
        if (!n.contains('OUI-SPY')) continue;
        if (n.contains('OUI-SPY-MGR') != mgr) continue;
        if (!completer.isCompleted) completer.complete(r.device);
      }
    });
    try {
      await startScan(timeout: timeout);
    } on Exception catch (e) {
      DebugLog.log('BLE: role scan error $e');
    }
    final found = await completer.future
        .timeout(timeout + const Duration(seconds: 2), onTimeout: () => null);
    await sub.cancel();
    await stopScan();
    return found;
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
  manager.setDetectorSigMaskGetter(() => ref.read(detectorSigMaskProvider));
  manager.setFlockOuiOnlyGetter(() {
    final n = ref.read(notificationServiceProvider);
    return n.flockEnabled && n.flockOuiOnly;
  });
  ref.listen(detectorSigMaskProvider, (prev, next) {
    if (manager.currentConnectionState == NodeConnectionState.ready) {
      manager.setDetectorSigMask(next);
    }
  });
  ref.onDispose(manager.dispose);
  return manager;
});
