// Copyright (c) 2026 Luke Switzer
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/presence_class.dart';

const _min = 60 * 1000;
const _h = 60 * _min;
const _p = PresenceParams();

void main() {
  final now = 30 * 24 * _h;

  test('visits split on gap, presence summed', () {
    final s = PresenceStats.fromSightings([now - 50 * _min, now - 45 * _min, now - 5 * _min, now], now, _p)!;
    expect(s.visitsInWindow, 2);
    expect(s.presenceMsInWindow, 10 * _min);
  });

  test('frequent flier', () {
    final ts = [for (var d = 0; d < 6; d++) now - d * 24 * _h];
    expect(classifyPresence(PresenceStats.fromSightings(ts, now, _p)!, now, _p), PresenceCategory.frequentFlier);
  });

  test('stationary', () {
    final ts = [for (var t = now - 7 * 24 * _h + _min; t <= now; t += 5 * _min) t];
    expect(classifyPresence(PresenceStats.fromSightings(ts, now, _p)!, now, _p), PresenceCategory.stationary);
  });

  test('new vs visitor vs transient relative to baseline', () {
    final base = now - 3 * _h;
    final present = PresenceStats.fromSightings([now - _min], now, _p, baselineStart: base)!;
    expect(classifyPresence(present, now, _p, baselineStart: base), PresenceCategory.newcomer);
    final left = PresenceStats.fromSightings([now - 2 * _h], now, _p, baselineStart: base)!;
    expect(classifyPresence(left, now, _p, baselineStart: base), PresenceCategory.visitor);
    expect(classifyPresence(left, now, _p), PresenceCategory.transient);
  });
}
