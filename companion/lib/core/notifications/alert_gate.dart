// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:oui_spy/core/classify/observation.dart';

const alertRearmSeconds = 60;

enum AlertSfx {
  hit('Filter hit', 'snd_hit'),
  tracker('Tracker', 'snd_tracker'),
  watch('Watched device', 'snd_watch'),
  drone('Drone appears', 'snd_drone'),
  nodeDown('Node down', 'snd_node_down'),
  nodeUp('Node back', 'snd_node_up');

  const AlertSfx(this.label, this.prefKey);
  final String label;
  final String prefKey;
}

AlertSfx alertSfxFor({String? watchLabel, bool drone = false, bool tracker = false}) {
  if (watchLabel != null) return AlertSfx.watch;
  if (drone) return AlertSfx.drone;
  if (tracker) return AlertSfx.tracker;
  return AlertSfx.hit;
}

enum AlertVerdict { fire, notDue, muted, silenced }

class AlertGate {
  AlertGate({int gapSeconds = alertRearmSeconds}) : gap = Duration(seconds: gapSeconds);

  static const heardCap = 20000;

  Duration gap;
  bool silenced = false;
  final Set<String> mutedDevices = {};
  final Map<String, int> _heard = {};

  static String keyOf(String mac) => MacUtil.normalize(mac);

  bool isDeviceMuted(String mac) => mutedDevices.contains(keyOf(mac));

  bool due(String key, int nowMs, {int? lastSeenMs}) {
    final prev = _heard[key];
    if (_heard.length > heardCap) _heard.clear();
    if (prev == null || nowMs > prev) _heard[key] = nowMs;
    if (prev == null && lastSeenMs == null) return true;
    final last = [?prev, ?lastSeenMs].reduce((a, b) => a > b ? a : b);
    return nowMs - last > gap.inMilliseconds;
  }

  AlertVerdict block(String key, {String? watchLabel, bool kindMuted = false}) {
    if (watchLabel == null && (kindMuted || mutedDevices.contains(key))) return AlertVerdict.muted;
    if (silenced) return AlertVerdict.silenced;
    return AlertVerdict.fire;
  }

  AlertVerdict check(String key, int nowMs,
      {int? lastSeenMs, String? watchLabel, bool kindMuted = false}) {
    if (!due(key, nowMs, lastSeenMs: lastSeenMs)) return AlertVerdict.notDue;
    return block(key, watchLabel: watchLabel, kindMuted: kindMuted);
  }
}
