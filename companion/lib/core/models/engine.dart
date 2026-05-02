import 'package:flutter/material.dart';

/// All scan engines available in the OUI-SPY firmware.
enum Engine {
  detector('Detector', 'BLE watchlist alerting', Color(0xFF4A9EFF), 0x01),
  flockBle('Flock BLE', 'Flock Safety BLE detection', Color(0xFFB44AFF), 0x02),
  flockWifi(
      'Flock WiFi', 'Flock Safety WiFi promiscuous', Color(0xFFFF4A8A), 0x04),
  foxhunter('Foxhunter', 'RSSI proximity tracker', Color(0xFF4AFF8A), 0x08),
  skySpy('Sky Spy', 'FAA Remote ID / ODID detection', Color(0xFF4AFFEA), 0x10),
  uniPwn(
      'UniPwn', 'Unitree robot exploitation', Color(0xFFFF4A4A), 0x20),
  wardrive(
      'Wardrive', 'WiGLE-style WiFi + BLE capture', Color(0xFFFFFF4A), 0x40);

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

  bool get isWifi => this == flockWifi || this == skySpy || this == wardrive;

  IconData get icon {
    return switch (this) {
      Engine.detector => Icons.radar,
      Engine.flockBle => Icons.videocam,
      Engine.flockWifi => Icons.wifi,
      Engine.foxhunter => Icons.gps_fixed,
      Engine.skySpy => Icons.flight,
      Engine.uniPwn => Icons.smart_toy,
      Engine.wardrive => Icons.drive_eta,
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

  /// WiFi engines are mutually exclusive.
  static const _wifiEngines = {Engine.flockWifi, Engine.skySpy, Engine.wardrive};

  /// Check if [engine] can be enabled given [activeEngines].
  static bool canEnable(Engine engine, Set<Engine> activeEngines) {
    if (activeEngines.contains(engine)) return true;

    // WiFi engines: only one at a time
    if (engine.isWifi) {
      return activeEngines.intersection(_wifiEngines).isEmpty;
    }

    // UniPwn active exploitation conflicts with WiFi engines
    // (handled at runtime, not at enable time — scanning is fine)

    return true;
  }

  /// Returns engines that must be disabled to enable [engine].
  static Set<Engine> conflicts(Engine engine, Set<Engine> activeEngines) {
    final result = <Engine>{};

    if (engine.isWifi) {
      result.addAll(activeEngines.intersection(_wifiEngines));
    }

    result.remove(engine);
    return result;
  }
}
