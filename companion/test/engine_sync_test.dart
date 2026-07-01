import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/wardrive_state.dart';

void main() {
  final statusFrame = <int>[
    0xFF,
    0x40,
    0, 2, 2, 0, 2, 0, 2, 0,
  ];

  test('commanded mask differs from live active mask', () {
    final s = BleProtocol.decodeEngineStatus(statusFrame);
    expect(s.active, 0x40);
    expect(commandedEngineMask(s.states), 0x56);
    expect(s.active == commandedEngineMask(s.states), isFalse);
  });

  test('flock/drone/detector adopt from the commanded mask', () {
    final s = BleProtocol.decodeEngineStatus(statusFrame);
    expect(targetsFromEngineMask(commandedEngineMask(s.states)),
        {WardriveTarget.flock, WardriveTarget.drone});
    expect(targetsFromEngineMask(0x57),
        {WardriveTarget.flock, WardriveTarget.drone, WardriveTarget.detector});
  });

  test('wigle is never auto-adopted from the engine mask', () {
    expect(targetsFromEngineMask(0x40), isEmpty);
    expect(targetsFromEngineMask(0x57).contains(WardriveTarget.wigle), isFalse);
    expect(targetsFromEngineMask(0xFF).contains(WardriveTarget.wigle), isFalse);
  });
}
