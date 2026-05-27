import 'dart:typed_data';

enum PcapMode { wifi, ble }

/// Mirrors firmware PcapStats struct in src/protocol.h (packed little-endian, 60 bytes).
class PcapStats {
  const PcapStats({
    required this.state,
    required this.mode,
    required this.currentChannel,
    required this.beaconCount,
    required this.probeReqCount,
    required this.probeRespCount,
    required this.deauthCount,
    required this.disassocCount,
    required this.dataCount,
    required this.ctrlCount,
    required this.mgmtOtherCount,
    required this.bleAdvCount,
    required this.bleScanCount,
    required this.bytesWritten,
    required this.droppedFrames,
    required this.fileSize,
    required this.uptimeMs,
    this.autoEnabled = false,
    this.autoDurationSec = 10,
    this.pausedMask = 0,
    this.autoRemainingMs = 0,
    this.autoTriggerSrc = 0xFF,
    this.autoTriggerMac = const [0, 0, 0, 0, 0, 0],
  });

  /// 0=idle, 1=capturing, 2=full, 3=error
  final int state;

  /// 0=WIFI radiotap, 1=BLE LL PHDR
  final int mode;
  final int currentChannel;
  final int beaconCount;
  final int probeReqCount;
  final int probeRespCount;
  final int deauthCount;
  final int disassocCount;
  final int dataCount;
  final int ctrlCount;
  final int mgmtOtherCount;
  final int bleAdvCount;
  final int bleScanCount;
  final int bytesWritten;
  final int droppedFrames;
  final int fileSize;
  final int uptimeMs;
  final bool autoEnabled;
  final int autoDurationSec;
  final int pausedMask;
  final int autoRemainingMs;

  /// EngineId of trigger source for an auto-PCAP capture. 0xFF when manual/idle.
  final int autoTriggerSrc;

  /// MAC (6 bytes) that triggered auto-PCAP. All-zero when manual/idle.
  final List<int> autoTriggerMac;

  PcapMode get modeEnum => mode == 1 ? PcapMode.ble : PcapMode.wifi;

  bool get isAutoTriggered =>
      autoTriggerSrc != 0xFF && autoTriggerMac.any((b) => b != 0);

  String get autoTriggerMacStr => autoTriggerMac
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');

  String get autoTriggerEngineName {
    switch (autoTriggerSrc) {
      case 0: return 'detector';
      case 1:
      case 2: return 'flock';
      case 3: return 'foxhunter';
      case 4: return 'skyspy';
      case 5: return 'unipwn';
      case 6: return 'wardrive';
      case 7: return 'pcap';
      default: return 'manual';
    }
  }

  static const empty = PcapStats(
    state: 0,
    mode: 0,
    currentChannel: 0,
    beaconCount: 0,
    probeReqCount: 0,
    probeRespCount: 0,
    deauthCount: 0,
    disassocCount: 0,
    dataCount: 0,
    ctrlCount: 0,
    mgmtOtherCount: 0,
    bleAdvCount: 0,
    bleScanCount: 0,
    bytesWritten: 0,
    droppedFrames: 0,
    fileSize: 0,
    uptimeMs: 0,
  );

  static PcapStats? decode(List<int> raw) {
    if (raw.length < 60) return null;
    final bd = ByteData.sublistView(Uint8List.fromList(raw));
    return PcapStats(
      state: bd.getUint8(0),
      mode: bd.getUint8(1),
      currentChannel: bd.getUint8(2),
      // _reserved at offset 3
      beaconCount: bd.getUint32(4, Endian.little),
      probeReqCount: bd.getUint32(8, Endian.little),
      probeRespCount: bd.getUint32(12, Endian.little),
      deauthCount: bd.getUint32(16, Endian.little),
      disassocCount: bd.getUint32(20, Endian.little),
      dataCount: bd.getUint32(24, Endian.little),
      ctrlCount: bd.getUint32(28, Endian.little),
      mgmtOtherCount: bd.getUint32(32, Endian.little),
      bleAdvCount: bd.getUint32(36, Endian.little),
      bleScanCount: bd.getUint32(40, Endian.little),
      bytesWritten: bd.getUint32(44, Endian.little),
      droppedFrames: bd.getUint32(48, Endian.little),
      fileSize: bd.getUint32(52, Endian.little),
      uptimeMs: bd.getUint32(56, Endian.little),
      autoEnabled: raw.length >= 61 ? bd.getUint8(60) != 0 : false,
      autoDurationSec: raw.length >= 63 ? bd.getUint16(61, Endian.little) : 10,
      pausedMask: raw.length >= 64 ? bd.getUint8(63) : 0,
      autoRemainingMs: raw.length >= 68 ? bd.getUint32(64, Endian.little) : 0,
      autoTriggerSrc: raw.length >= 69 ? bd.getUint8(68) : 0xFF,
      autoTriggerMac: raw.length >= 75
          ? List<int>.unmodifiable(raw.sublist(69, 75))
          : const [0, 0, 0, 0, 0, 0],
    );
  }

  String get stateLabel => switch (state) {
        0 => 'IDLE',
        1 => 'CAPTURING',
        2 => 'FULL',
        3 => 'ERROR',
        _ => 'UNKNOWN',
      };

  String get modeLabel => mode == 1 ? 'BLE LL' : 'WIFI 802.11';
}
