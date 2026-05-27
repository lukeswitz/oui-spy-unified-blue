import 'package:flutter/material.dart';

/// All scan engines available in the OUI-SPY firmware.
enum Engine {
  detector('Detector', 'WiFi + BLE watchlist alerting', Color(0xFF4A9EFF), 0x01),
  flockBle('Flock BLE', 'Flock Safety BLE detection', Color(0xFFB44AFF), 0x02),
  flockWifi(
      'Flock WiFi', 'Flock Safety WiFi promiscuous', Color(0xFFFF4A8A), 0x04),
  foxhunter('Foxhunter', 'WiFi + BLE proximity tracker', Color(0xFF4AFF8A), 0x08),
  skySpy('Sky Spy', 'FAA Remote ID / ODID detection', Color(0xFF4AFFEA), 0x10),
  uniPwn(
      'UniPwn', 'Unitree robot exploitation', Color(0xFFFF4A4A), 0x20),
  wardrive(
      'Wardrive', 'WiGLE-style WiFi + BLE capture', Color(0xFFFF8C4A), 0x40),
  pcap(
      'PCAP', 'WiFi/BLE PCAP capture & audit', Color(0xFF4AFFCC), 0x80);

  const Engine(this.label, this.description, this.color, this.bitmask);

  final String label;
  final String description;
  final Color color;
  final int bitmask;

  bool get isBle =>
      this == detector ||
      this == flockBle ||
      this == foxhunter ||
      this == uniPwn;

  bool get isWifi =>
      this == flockWifi ||
      this == skySpy ||
      this == wardrive ||
      this == pcap;

  /// Engines that scan both WiFi and BLE radios.
  bool get isDualRadio =>
      this == detector || this == foxhunter || this == wardrive;

  IconData get icon {
    return switch (this) {
      Engine.detector => Icons.radar,
      Engine.flockBle => Icons.videocam,
      Engine.flockWifi => Icons.wifi,
      Engine.foxhunter => Icons.gps_fixed,
      Engine.skySpy => Icons.flight,
      Engine.uniPwn => Icons.smart_toy,
      Engine.wardrive => Icons.drive_eta,
      Engine.pcap => Icons.fiber_manual_record,
    };
  }
}

/// Runtime state of a single engine on the device.
enum EngineState {
  disabled,
  idle,
  scanning,
  active,
  alerting,
  // UniPwn-specific
  targetSelected,
  connecting,
  exploiting,
  complete,
}

/// Which engines can run simultaneously.
class EngineCompatibility {
  const EngineCompatibility._();

  /// WiFi engines are mutually exclusive — except wardrive+flockWifi which
  /// coexist via firmware passive mode (flockWifi rides wardrive's sniffer).
  static const _wifiEngines = {Engine.flockWifi, Engine.skySpy, Engine.wardrive, Engine.pcap};

  static bool _wifiCompatible(Engine a, Engine b) {
    return (a == Engine.wardrive && b == Engine.flockWifi) ||
           (a == Engine.flockWifi && b == Engine.wardrive);
  }

  /// Check if [engine] can be enabled given [activeEngines].
  static bool canEnable(Engine engine, Set<Engine> activeEngines) {
    if (activeEngines.contains(engine)) return true;

    // WiFi engines: only one at a time (wardrive+flockWifi excepted)
    if (engine.isWifi) {
      final conflicts = activeEngines
          .intersection(_wifiEngines)
          .where((e) => !_wifiCompatible(engine, e));
      return conflicts.isEmpty;
    }


    return true;
  }

  /// Returns engines that must be disabled to enable [engine].
  static Set<Engine> conflicts(Engine engine, Set<Engine> activeEngines) {
    final result = <Engine>{};

    if (engine.isWifi) {
      result.addAll(activeEngines
          .intersection(_wifiEngines)
          .where((e) => !_wifiCompatible(engine, e)));
    }

    result.remove(engine);
    return result;
  }
}
