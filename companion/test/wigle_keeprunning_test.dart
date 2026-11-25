// Copyright (c) 2026 Luke Switzer
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/wardrive_state.dart';

void main() {
  const runningMask = 0x01 | 0x02 | 0x04 | 0x10;

  test('targetsFromEngineMask never yields wigle', () {
    expect(targetsFromEngineMask(0x40), isEmpty);
    expect(targetsFromEngineMask(0x57).contains(WardriveTarget.wigle), isFalse);
  });

  test('keep-running ON: wigle ALWAYS deselected even when user had it', () {
    final current = {
      WardriveTarget.flock,
      WardriveTarget.drone,
      WardriveTarget.wigle,
      WardriveTarget.detector,
    };
    final r = reconciledTargets(runningMask, current, true);
    expect(r.contains(WardriveTarget.wigle), isFalse);
    expect(r, {
      WardriveTarget.flock,
      WardriveTarget.drone,
      WardriveTarget.detector,
    });
  });

  test('keep-running OFF: user wigle selection preserved', () {
    final current = {WardriveTarget.flock, WardriveTarget.wigle};
    final r = reconciledTargets(runningMask, current, false);
    expect(r.contains(WardriveTarget.wigle), isTrue);
  });

  test('keep-running OFF: no wigle when user never selected it', () {
    final current = {WardriveTarget.flock};
    final r = reconciledTargets(runningMask, current, false);
    expect(r.contains(WardriveTarget.wigle), isFalse);
  });
}
