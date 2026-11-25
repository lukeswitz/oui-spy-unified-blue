// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';

typedef NodeTimerFactory = Timer Function(Duration after, void Function() fire);

class NodeWatch {
  NodeWatch({
    required this.onDown,
    required this.onUp,
    this.downAfter = const Duration(seconds: 45),
    this.sayGap = const Duration(seconds: 30),
    DateTime Function()? now,
    NodeTimerFactory? timer,
  })  : _now = now ?? DateTime.now,
        _timer = timer ?? Timer.new;

  final void Function(String id) onDown;
  final void Function(String id) onUp;
  final Duration downAfter;
  final Duration sayGap;
  final DateTime Function() _now;
  final NodeTimerFactory _timer;

  final Set<String> _known = {};
  final Set<String> _down = {};
  final Map<String, Timer> _pending = {};
  final Map<String, DateTime> _said = {};

  Set<String> get down => Set.unmodifiable(_down);

  void update(Set<String> live) {
    for (final id in live) {
      _pending.remove(id)?.cancel();
      _known.add(id);
      if (_down.remove(id)) _say(id, up: true);
    }
    for (final id in _known) {
      if (live.contains(id) || _down.contains(id) || _pending.containsKey(id)) continue;
      _pending[id] = _timer(downAfter, () {
        _pending.remove(id);
        _down.add(id);
        _say(id, up: false);
      });
    }
  }

  void reset() {
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
    _known.clear();
    _down.clear();
  }

  void _say(String id, {required bool up}) {
    final key = '$id|$up';
    final now = _now();
    final last = _said[key];
    if (last != null && now.difference(last) < sayGap) return;
    _said[key] = now;
    if (up) {
      onUp(id);
    } else {
      onDown(id);
    }
  }
}
