import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// All GATT service and characteristic UUIDs for OUI-SPY firmware.
///
/// Base UUID: 0000XXXX-0a15-4b70-ba00-c010ae1ba01c
/// Must match firmware protocol.h exactly.
class GattUuids {
  const GattUuids._();

  static const _base = '0a15-4b70-ba00-c010ae1ba01c';

  // Service
  static final service = Guid('00000001-$_base');

  // -- Shared characteristics --

  /// READ: firmware version, node ID, name, MAC, uptime, heap, SPIFFS, config hash
  static final deviceInfo = Guid('00000001-$_base');

  /// READ, WRITE, NOTIFY: engine bitmask control
  static final engineControl = Guid('00000002-$_base');

  /// NOTIFY: binary-packed detection events from all engines
  static final detectionEvents = Guid('00000010-$_base');

  /// READ, NOTIFY: device status (engines, counts, heap, SPIFFS)
  static final deviceStatus = Guid('00000011-$_base');

  /// WRITE: app pushes phone GPS to device
  static final gpsReceive = Guid('00000012-$_base');

  /// READ, WRITE: buzzer, LED, NeoPixel brightness
  static final hardwareConfig = Guid('00000020-$_base');

  /// READ, WRITE: cooldown, heartbeat, rediscover timing
  static final alertConfig = Guid('00000021-$_base');

  /// READ, NOTIFY: chunked session data download
  static final sessionSync = Guid('00000030-$_base');

  /// READ, WRITE: WiFi STA credentials
  static final wifiConfig = Guid('00000040-$_base');

  /// WRITE, NOTIFY: WiFi commands (scan, connect, disconnect, mode switch)
  static final wifiCommand = Guid('00000041-$_base');

  /// WRITE, NOTIFY: OTA control (start, abort, verify, progress)
  static final dfuControl = Guid('00000050-$_base');

  /// WRITE_NR: OTA data chunks
  static final dfuData = Guid('00000051-$_base');

  /// WRITE, NOTIFY: system control — reboot, factory reset, OTA confirm
  static final systemControl = Guid('00000052-$_base');

  // -- Engine-specific characteristics --

  /// READ, WRITE: Detector watchlist (chunked)
  static final detectorConfig = Guid('00000100-$_base');

  /// READ, WRITE: Flock-BLE OUI list, name patterns, mfg IDs (chunked)
  static final flockBleConfig = Guid('00000110-$_base');

  /// READ, WRITE: Flock-WiFi channel, dwell, RSSI, frame toggles, SSID keywords
  static final flockWifiConfig = Guid('00000120-$_base');

  /// READ, WRITE: Foxhunter target MAC
  static final foxhunterConfig = Guid('00000130-$_base');

  /// NOTIFY: Foxhunter live RSSI stream
  static final foxhunterRssi = Guid('00000131-$_base');

  /// NOTIFY: Sky Spy full ODID drone telemetry
  static final skySpyTelemetry = Guid('00000140-$_base');

  /// READ, NOTIFY: UniPwn discovered Unitree robots
  static final unipwnDevices = Guid('00000150-$_base');

  /// WRITE, NOTIFY: UniPwn exploit commands and progress
  static final unipwnCommand = Guid('00000151-$_base');

  /// READ, WRITE: Mesh configuration (enable, encryption key, peers)
  static final meshConfig = Guid('00000060-$_base');

  /// READ, NOTIFY: Mesh status (peers, packet counts)
  static final meshStatus = Guid('00000061-$_base');

  /// WRITE, NOTIFY: Orchestration — relay commands to peers, receive peer status
  static final orchestration = Guid('00000070-$_base');

  // -- PCAP capture --

  /// WRITE: PCAP control (download_start, download_abort)
  static final pcapControl = Guid('00000160-$_base');

  /// READ, NOTIFY: PCAP live stats (binary PcapStats struct)
  static final pcapStats = Guid('00000161-$_base');

  /// NOTIFY: PCAP chunked file download (start/chunk/commit/abort opcodes)
  static final pcapData = Guid('00000162-$_base');
}
