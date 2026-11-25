// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:oui_spy/core/models/engine.dart';

enum RadioFilter { ble, wifi }

enum FilterPreset {
  all('ALL', null, null),
  ble('BLE', _bleEngines, RadioFilter.ble),
  wifi('WIFI', _wifiEngines, RadioFilter.wifi),
  flock('FLOCK', _flockEngines, null),
  drones('DRONES', _droneEngines, null),
  alerts('ALERTS', _alertEngines, null);

  const FilterPreset(this.label, this.engines, this.radio);
  final String label;
  final Set<Engine>? engines;
  final RadioFilter? radio;

  static const _bleEngines = {
    Engine.detector,
    Engine.flockBle,
    Engine.foxhunter,
    Engine.uniPwn,
    Engine.wardrive,
  };
  static const _wifiEngines = {
    Engine.detector,
    Engine.flockWifi,
    Engine.foxhunter,
    Engine.skySpy,
    Engine.wardrive,
  };
  static const _flockEngines = {Engine.flockBle, Engine.flockWifi};
  static const _droneEngines = {Engine.skySpy};
  static const _alertEngines = {Engine.detector};

  Set<Engine> resolve() => engines ?? Engine.values.toSet();

  bool matches(Set<Engine> active, RadioFilter? activeRadio) {
    if (radio != activeRadio) return false;
    final target = resolve();
    return active.length == target.length && active.containsAll(target);
  }
}
