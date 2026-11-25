// Copyright (c) 2026 Luke Switzer
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/node_positions.dart';
import 'package:oui_spy/core/triangulation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TriSettings {
  const TriSettings({this.enabled = true, this.p0 = kTriDefaultP0, this.n = kTriDefaultN});
  final bool enabled;
  final double p0;
  final double n;

  TriSettings copyWith({bool? enabled, double? p0, double? n}) =>
      TriSettings(enabled: enabled ?? this.enabled, p0: p0 ?? this.p0, n: n ?? this.n);
}

class TriSettingsNotifier extends StateNotifier<TriSettings> {
  TriSettingsNotifier() : super(const TriSettings()) {
    _load();
  }

  static const _kEnabled = 'tri_enabled';
  static const _kP0 = 'tri_p0';
  static const _kN = 'tri_n';
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed) return;
    state = TriSettings(
      enabled: p.getBool(_kEnabled) ?? true,
      p0: p.getDouble(_kP0) ?? kTriDefaultP0,
      n: p.getDouble(_kN) ?? kTriDefaultN,
    );
  }

  Future<void> setEnabled(bool on) async {
    _changed = true;
    state = state.copyWith(enabled: on);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, on);
  }

  Future<void> setP0(double v) async {
    _changed = true;
    state = state.copyWith(p0: v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kP0, v);
  }

  Future<void> setN(double v) async {
    _changed = true;
    state = state.copyWith(n: v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kN, v);
  }
}

final triSettingsProvider =
    StateNotifierProvider<TriSettingsNotifier, TriSettings>((ref) => TriSettingsNotifier());

/// Feeds node-heard RSSI into the solver and holds the latest fixes for the map.
class TriangulationController extends ChangeNotifier {
  TriangulationController({
    required this.placed,
    required this.settings,
    required this.selfNode,
    this.minInterval = const Duration(milliseconds: 1500),
  });

  final Map<String, LatLng> Function() placed;
  final TriSettings Function() settings;
  final String Function() selfNode;
  final Duration minInterval;
  final TriangulationEngine _engine = TriangulationEngine();
  List<TriDeviceFix> _fixes = const [];
  DateTime _lastCompute = DateTime.fromMillisecondsSinceEpoch(0);

  List<TriDeviceFix> get fixes {
    final cutoff = DateTime.now().subtract(kTriWindow);
    return [for (final f in _fixes) if (f.heardAt.isAfter(cutoff)) f];
  }

  Timer? _timer;

  void onDetection(Detection d, {DateTime? now}) {
    final s = settings();
    if (!s.enabled || d.macAddress.isEmpty || d.rssi >= 0) return;
    final nodes = placed();
    if (nodes.length < 3) return;
    final id = AppState.canonicalNodeId(d.sourceNodeId.isEmpty ? selfNode() : d.sourceNodeId);
    if (id.isEmpty || !nodes.containsKey(id)) return;
    final t = now ?? DateTime.now();
    _engine.add(d.macAddress, id, d.rssi, t);
    final wait = minInterval - t.difference(_lastCompute);
    if (wait <= Duration.zero) {
      _recompute(t);
    } else {
      _timer ??= Timer(wait, () {
        _timer = null;
        _recompute(DateTime.now());
      });
    }
  }

  void _recompute(DateTime t) {
    final s = settings();
    final nodes = placed();
    _lastCompute = t;
    final next = s.enabled && nodes.length >= 3 ? _engine.compute(t, nodes, p0: s.p0, n: s.n) : const <TriDeviceFix>[];
    if (next.isEmpty && _fixes.isEmpty) return;
    _fixes = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final triangulationProvider = ChangeNotifierProvider<TriangulationController>((ref) {
  final ble = ref.watch(bleManagerProvider);
  final c = TriangulationController(
    placed: () => ref.read(nodePositionsProvider),
    settings: () => ref.read(triSettingsProvider),
    selfNode: () => ref.read(appStateProvider).nodeId,
  );
  final sub = ble.detections.listen(c.onDetection);
  ref.onDispose(sub.cancel);
  return c;
});
