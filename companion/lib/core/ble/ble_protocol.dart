import 'dart:typed_data';

import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

/// Binary encode/decode for GATT characteristic payloads.
class BleProtocol {
  const BleProtocol._();

  // -- Detection event decoding --

  /// Decode a detection notification payload.
  /// v3.0 header (14 bytes): engine_id[1] mac[6] rssi[1] channel[1] ts_ms[4] method[1]
  /// v3.1 header (19 bytes): + source_node_id[5]
  /// Auto-detects format by packet size vs expected sizes for each engine.
  static Detection decodeDetection(List<int> data, {
    required String sessionId,
    required String nodeId,
    required DateTime appTimestamp,
    double? latitude,
    double? longitude,
    double? accuracy,
    int? satelliteCount,
  }) {
    final bytes = Uint8List.fromList(data);
    final view = ByteData.sublistView(bytes);

    final engineIndex = bytes[0];
    final engine = Engine.values[engineIndex.clamp(0, Engine.values.length - 1)];

    final mac = _decodeMac(bytes, 1);
    final rssi = view.getInt8(7);
    final channel = bytes[8];
    final timestampMs = view.getUint32(9, Endian.little);
    final method = bytes[13];

    const v31Sizes = {31: false, 36: true, 37: true, 96: false, 101: true, 23: false, 28: true, 47: false, 52: true, 74: true};
    final isV31 = v31Sizes[bytes.length] ?? (bytes.length >= 19 && engine == Engine.wardrive);

    final headerLen = isV31 ? 19 : 14;
    final sourceNodeId = isV31 ? _extractString(bytes, 14, 5) : '';

    final methodStr = _decodeMethod(engine, method);

    FlockExtension? flock;
    OdidExtension? odid;
    UnipwnExtension? unipwn;
    DetectorExtension? detector;
    WardriveExtension? wardrive;
    String deviceName = '';

    if (bytes.length > headerLen) {
      final ext = bytes.sublist(headerLen);
      switch (engine) {
        case Engine.flockBle:
        case Engine.flockWifi:
          flock = _decodeFlockExtension(ext);
          if (engine == Engine.flockWifi && ext.length >= 18) {
            final auth = ext[17];
            if (auth > 0) {
              wardrive = WardriveExtension(authMode: auth);
            }
          }
        case Engine.skySpy:
          odid = _decodeOdidExtension(ext);
        case Engine.uniPwn:
          unipwn = _decodeUnipwnExtension(ext);
          deviceName = _extractString(ext, 5, 20);
        case Engine.detector:
          detector = _decodeDetectorExtension(ext);
        case Engine.wardrive:
          wardrive = _decodeWardriveExtension(ext);
          deviceName = wardrive.deviceName.isNotEmpty
              ? wardrive.deviceName
              : wardrive.ssid;
        case Engine.foxhunter:
        case Engine.pcap:
          break;
      }
    }

    return Detection(
      id: '${mac}_$timestampMs',
      sessionId: sessionId,
      nodeId: nodeId,
      macAddress: mac,
      engine: engine,
      method: methodStr,
      rssi: rssi,
      channel: channel,
      deviceTimestampMs: timestampMs,
      appTimestamp: appTimestamp,
      deviceName: deviceName,
      ssid: wardrive?.ssid ?? '',
      sourceNodeId: sourceNodeId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      satelliteCount: satelliteCount,
      flock: flock,
      odid: odid,
      unipwn: unipwn,
      detector: detector,
      wardrive: wardrive,
    );
  }

  // -- GPS encoding --

  /// Encode phone GPS for writing to GPS Receive characteristic.
  /// lat[8] lon[8] alt[4] speed[4] heading[4] accuracy[4] sat_count[1] timestamp[8] = 41 bytes
  static Uint8List encodeGps({
    required double latitude,
    required double longitude,
    double altitude = 0,
    double speed = 0,
    double heading = 0,
    double accuracy = 0,
    int satelliteCount = 0,
    required int timestampMs,
    bool suppressAlerts = false,
  }) {
    final bytes = ByteData(42);
    bytes.setFloat64(0, latitude, Endian.little);
    bytes.setFloat64(8, longitude, Endian.little);
    bytes.setFloat32(16, altitude, Endian.little);
    bytes.setFloat32(20, speed, Endian.little);
    bytes.setFloat32(24, heading, Endian.little);
    bytes.setFloat32(28, accuracy, Endian.little);
    bytes.setUint8(32, satelliteCount);
    bytes.setInt64(33, timestampMs, Endian.little);
    bytes.setUint8(41, suppressAlerts ? 1 : 0);
    return bytes.buffer.asUint8List();
  }

  // -- Engine control --

  static List<int> targetEnvelope(String nodeId) {
    if (nodeId.length != 4) {
      throw ArgumentError('nodeId must be 4-hex canonical form, got "$nodeId"');
    }
    return [0xFE, ...nodeId.codeUnits, 0x00];
  }

  static Uint8List encodeEngineControl({
    required Engine engine,
    required bool enable,
    String? targetNodeId,
  }) {
    final base = <int>[enable ? 0x01 : 0x00, engine.index];
    if (targetNodeId != null) {
      if (targetNodeId.length != 4) {
        throw ArgumentError('targetNodeId must be 4-hex canonical form, got "$targetNodeId"');
      }
      base.addAll(targetNodeId.codeUnits);
      base.add(0x00);
    }
    return Uint8List.fromList(base);
  }

  /// Encode a "disable all engines" command.
  /// action[1]=0x0F engine_id[1]=0x00 (ignored by firmware)
  static Uint8List encodeDisableAll() {
    return Uint8List.fromList([0x0F, 0x00]);
  }

  /// Encode engine config update command.
  /// action[1]=0x10 engine_id[1] payload[N]
  static Uint8List encodeEngineConfig({
    required Engine engine,
    required Uint8List payload,
  }) {
    return Uint8List.fromList([0x10, engine.index, ...payload]);
  }

  /// Decode engine control status.
  /// available[1] active[1] states[6]
  static ({int available, int active, List<EngineState> states}) decodeEngineStatus(
      List<int> data) {
    final available = data[0];
    final active = data[1];
    final states = <EngineState>[];
    for (int i = 0; i < Engine.values.length && i + 2 < data.length; i++) {
      final stateIndex = data[i + 2];
      states.add(EngineState.values[stateIndex.clamp(0, EngineState.values.length - 1)]);
    }
    return (available: available, active: active, states: states);
  }

  // -- Hardware config --

  /// Encode hardware config: buzzer[1] led[1] neopixel_brightness[1] buzzer_volume[1]
  static Uint8List encodeHardwareConfig({
    required bool buzzer,
    required bool led,
    required int neopixelBrightness,
    required int buzzerVolume,
  }) {
    return Uint8List.fromList([
      buzzer ? 1 : 0,
      led ? 1 : 0,
      neopixelBrightness.clamp(0, 255),
      buzzerVolume.clamp(0, 255),
    ]);
  }

  /// Encode alert config: cooldown[2] heartbeat[2] rediscover[2] hb_active[2]
  static Uint8List encodeAlertConfig({
    required int cooldownMs,
    required int heartbeatMs,
    required int rediscoverMs,
    required int hbActiveMs,
  }) {
    final bytes = ByteData(8);
    bytes.setUint16(0, cooldownMs, Endian.little);
    bytes.setUint16(2, heartbeatMs, Endian.little);
    bytes.setUint16(4, rediscoverMs, Endian.little);
    bytes.setUint16(6, hbActiveMs, Endian.little);
    return bytes.buffer.asUint8List();
  }

  // -- Foxhunter --

  /// Encode foxhunter target MAC + optional channel hint.
  /// MAC[6] + channel[1]. Channel 0 = hop ch1/6/11, 1-14 = lock to channel.
  static Uint8List encodeFoxhunterTarget(String mac, {int channel = 0}) {
    final macBytes = _encodeMac(mac);
    final result = Uint8List(7);
    result.setRange(0, 6, macBytes);
    result[6] = channel.clamp(0, 14);
    return result;
  }

  /// Decode foxhunter RSSI notification: rssi[1] interval_ms[2]
  static ({int rssi, int intervalMs}) decodeFoxhunterRssi(List<int> data) {
    final view = ByteData.sublistView(Uint8List.fromList(data));
    return (rssi: view.getInt8(0), intervalMs: view.getUint16(1, Endian.little));
  }

  // -- UniPwn --

  /// Encode UniPwn exploit command: target_mac[6] command_type[1] payload_len[1] payload[N]
  static Uint8List encodeUnipwnCommand({
    required String targetMac,
    required int commandType,
    String payload = '',
  }) {
    final mac = _encodeMac(targetMac);
    final payloadBytes = Uint8List.fromList(payload.codeUnits);
    final result = Uint8List(8 + payloadBytes.length);
    result.setRange(0, 6, mac);
    result[6] = commandType;
    result[7] = payloadBytes.length;
    result.setRange(8, 8 + payloadBytes.length, payloadBytes);
    return result;
  }

  // -- Mesh config --

  /// Encode mesh config: enabled[1] encryption[1] key[32] peer_count[1] peers[N*6]
  static Uint8List encodeMeshConfig({
    required bool enabled,
    required bool encryption,
    required Uint8List key,
    required List<Uint8List> peerMacs,
  }) {
    final peerCount = peerMacs.length.clamp(0, 6);
    final size = 2 + (encryption ? 32 : 0) + 1 + (peerCount * 6);
    final buf = ByteData(size);
    var offset = 0;

    buf.setUint8(offset++, enabled ? 1 : 0);
    buf.setUint8(offset++, encryption ? 1 : 0);

    if (encryption) {
      final keyBytes = buf.buffer.asUint8List();
      keyBytes.setRange(offset, offset + 32, key);
      offset += 32;
    }

    buf.setUint8(offset++, peerCount);
    for (var i = 0; i < peerCount; i++) {
      final macBytes = buf.buffer.asUint8List();
      macBytes.setRange(offset, offset + 6, peerMacs[i]);
      offset += 6;
    }

    return buf.buffer.asUint8List();
  }

  static ({
    bool enabled,
    int peerCount,
    int connectedPeers,
    int rxCount,
    int txCount,
    List<({String id, int role, int activeEngines})> liveNodes,
  }) decodeMeshStatus(List<int> data) {
    if (data.length < 11) {
      return (
        enabled: false,
        peerCount: 0,
        connectedPeers: 0,
        rxCount: 0,
        txCount: 0,
        liveNodes: const [],
      );
    }
    final bytes = Uint8List.fromList(data);
    final view = ByteData.sublistView(bytes);
    final live = <({String id, int role, int activeEngines})>[];
    if (data.length >= 12) {
      final n = data[11];
      const entryLen = 7;
      for (int i = 0; i < n && 12 + (i + 1) * entryLen <= data.length; i++) {
        final off = 12 + i * entryLen;
        final idBytes = bytes.sublist(off, off + 4);
        final id = String.fromCharCodes(idBytes);
        live.add((id: id, role: data[off + 5], activeEngines: data[off + 6]));
      }
    }
    return (
      enabled: data[0] != 0,
      peerCount: data[1],
      connectedPeers: data[2],
      rxCount: view.getUint32(3, Endian.little),
      txCount: view.getUint32(7, Endian.little),
      liveNodes: live,
    );
  }

  // -- Private helpers --

  static String _decodeMac(Uint8List bytes, int offset) {
    return List.generate(
      6,
      (i) => bytes[offset + i].toRadixString(16).padLeft(2, '0'),
    ).join(':');
  }

  static Uint8List _encodeMac(String mac) {
    return parseMacToBytes(mac);
  }

  static Uint8List parseMacToBytes(String mac) {
    final cleaned = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    // Standard 6-byte MAC (12 hex chars)
    if (cleaned.length == 12) {
      return Uint8List.fromList(
        List.generate(6, (i) => int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16)),
      );
    }
    // Colon-separated MAC (AA:BB:CC:DD:EE:FF)
    final parts = mac.split(':');
    if (parts.length == 6) {
      return Uint8List.fromList(
        parts.map((p) => int.parse(p, radix: 16)).toList(),
      );
    }
    if (cleaned.length >= 12) {
      final tail = cleaned.substring(cleaned.length - 12);
      return Uint8List.fromList(
        List.generate(6, (i) => int.parse(tail.substring(i * 2, i * 2 + 2), radix: 16)),
      );
    }
    // Fallback: zero MAC
    return Uint8List(6);
  }

  static String _decodeMethod(Engine engine, int method) {
    return switch (engine) {
      Engine.flockWifi => const [
          'oui_addr1',
          'oui_addr2',
          'oui_addr3',
          'ssid',
          'wildcard_probe',
        ][method.clamp(0, 4)],
      Engine.flockBle => const [
          'oui_match',
          'name_match',
          'mfg_id',
          'raven_uuid',
        ][method.clamp(0, 3)],
      Engine.skySpy => const [
          'odid_ble',
          'odid_nan',
          'odid_beacon',
        ][method.clamp(0, 2)],
      Engine.detector => const ['ble_watchlist', 'wifi_watchlist'][method.clamp(0, 1)],
      Engine.foxhunter => const ['ble_proximity', 'wifi_proximity'][method.clamp(0, 1)],
      Engine.uniPwn => 'unitree_ble',
      Engine.wardrive => const ['wifi_ap', 'ble_adv'][method.clamp(0, 1)],
      Engine.pcap => 'pcap',
    };
  }

  static FlockExtension _decodeFlockExtension(Uint8List ext) {
    final isRaven = ext.isNotEmpty && ext[0] == 1;
    String? ravenFw;
    if (ext.length > 1) {
      ravenFw = _extractString(ext, 1, 16);
    }
    return FlockExtension(isRaven: isRaven, ravenFirmware: ravenFw);
  }

  static OdidExtension _decodeOdidExtension(Uint8List ext) {
    if (ext.length < 88) return const OdidExtension();
    final view = ByteData.sublistView(ext);
    return OdidExtension(
      uavId: _extractString(ext, 0, 21),
      operatorId: _extractString(ext, 21, 21),
      droneLat: view.getFloat64(42, Endian.little),
      droneLon: view.getFloat64(50, Endian.little),
      altitudeMsl: view.getInt16(58, Endian.little),
      heightAgl: view.getInt16(60, Endian.little),
      droneSpeed: view.getInt16(62, Endian.little),
      droneHeading: view.getInt16(64, Endian.little),
      pilotLat: view.getFloat64(66, Endian.little),
      pilotLon: view.getFloat64(74, Endian.little),
    );
  }

  static UnipwnExtension _decodeUnipwnExtension(Uint8List ext) {
    if (ext.isEmpty) {
      return const UnipwnExtension(robotType: 'unknown');
    }
    final robotType = _extractString(ext, 0, 4);
    final exploited = ext.length > 4 && ext[4] == 1;
    return UnipwnExtension(robotType: robotType, exploited: exploited);
  }

  static DetectorExtension _decodeDetectorExtension(Uint8List ext) {
    if (ext.isEmpty) return const DetectorExtension();
    final isFullMac = ext[0] == 1;
    String? desc;
    if (ext.length > 1) {
      desc = _extractString(ext, 1, 32);
    }
    return DetectorExtension(isFullMac: isFullMac, filterDescription: desc);
  }

  static WardriveExtension _decodeWardriveExtension(Uint8List ext) {
    if (ext.isEmpty) return const WardriveExtension();
    final ssid = _extractString(ext, 0, 33);
    final authMode = ext.length > 33 ? ext[33] : 0;
    final deviceName = ext.length > 34 ? _extractString(ext, 34, 21) : '';
    return WardriveExtension(
      ssid: ssid,
      authMode: authMode,
      deviceName: deviceName,
    );
  }

  static String _extractString(Uint8List data, int offset, int maxLen) {
    final end = (offset + maxLen).clamp(0, data.length);
    final slice = data.sublist(offset, end);
    final nullIndex = slice.indexOf(0);
    final trimmed = nullIndex >= 0 ? slice.sublist(0, nullIndex) : slice;
    return String.fromCharCodes(trimmed);
  }

  // -- Orchestration --

  /// Encode orchestration command: command[1] engineId[1] payloadLen[1] payload[N]
  static Uint8List encodeOrchestrationCommand({
    required int command,
    required int engineId,
    Uint8List? payload,
  }) {
    final payloadLen = payload?.length ?? 0;
    final buf = Uint8List(3 + payloadLen);
    buf[0] = command;
    buf[1] = engineId;
    buf[2] = payloadLen;
    if (payload != null && payloadLen > 0) {
      buf.setRange(3, 3 + payloadLen, payload);
    }
    return buf;
  }

}
