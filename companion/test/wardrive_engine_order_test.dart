// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';

void main() {
  test('wardrive starts before engines that run passively off it, whatever the tap order', () {
    final engines = <Engine>{};
    for (final t in [
      WardriveTarget.detector,
      WardriveTarget.flock,
      WardriveTarget.drone,
      WardriveTarget.wigle,
    ]) {
      engines.addAll(t.engines(WardriveRadio.both));
    }
    expect(WardriveController.wardriveFirst(engines),
        [Engine.wardrive, Engine.detector, Engine.flockWifi, Engine.flockBle, Engine.skySpy]);
  });

  test('a selection without wardrive keeps its order', () {
    expect(WardriveController.wardriveFirst([Engine.detector, Engine.skySpy]), [Engine.detector, Engine.skySpy]);
  });
}
