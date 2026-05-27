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

  PcapMode get modeEnum => mode == 1 ? PcapMode.ble : PcapMode.wifi;

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
