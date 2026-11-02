import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/app.dart' show routerProvider;
import 'package:oui_spy/core/app_state.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/features/detections/detections_screen.dart';

const _enabled = bool.fromEnvironment('BENCH') || int.fromEnvironment('BENCH') != 0;
const _nBle = int.fromEnvironment('INJECT_BLE', defaultValue: 900);
const _nWifi = int.fromEnvironment('INJECT_WIFI', defaultValue: 200);
const _rate = int.fromEnvironment('INJECT_RATE', defaultValue: 400);
const _screen = String.fromEnvironment('BENCH_SCREEN', defaultValue: 'devices');

String _mac(int lead, int i) =>
    '$lead:00:${(i >> 16) & 0xff}:${(i >> 8) & 0xff}:${i & 0xff}:${(i ~/ 251) & 0xff}';

Observation _bleObs(int i, int now) {
  final mac = _mac(2, i);
  return Observation(key: 'BLE:$mac', kind: RadioKind.ble, mac: mac,
      rssi: -40 - (i % 55), firstSeenMs: now, lastSeenMs: now);
}

Observation _wifiObs(int i, int now) {
  final mac = _mac(6, i);
  return Observation(key: 'WIFI:$mac', kind: RadioKind.wifi, mac: mac, name: 'net$i',
      rssi: -45 - (i % 40), firstSeenMs: now, lastSeenMs: now,
      isAp: true, channel: (i % 13) + 1, authMode: 1);
}

// No-op unless built with --dart-define=BENCH=1. Drives the real app to the Devices (or Live) tab and injects a busy-RF mix into the real feed AND device registry, logging real frame timings (steady state).
void runBenchIfEnabled(ProviderContainer container) {
  if (!_enabled) return;

  final app = container.read(appStateProvider);
  app.connectionState = NodeConnectionState.ready;
  final reg = container.read(deviceRegistryProvider);

  var total = 0, janky = 0;
  var worst = 0.0, sum = 0.0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final ms = (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) / 1000.0;
      total++;
      sum += ms;
      if (ms > worst) worst = ms;
      if (ms > 16.7) janky++;
    }
  });

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await reg.loadCatalog();
    container.read(routerProvider).go('/detections');
    container.read(detectionsViewProvider.notifier).state =
        _screen == 'live' ? DetectionsView.live : DetectionsView.devices;

    final ble = container.read(bleManagerProvider);
    final totalItems = _nBle + _nWifi;
    final batch = (_rate / 20).ceil();
    final items = <bool>[];
    for (var b = 0, w = 0; b < _nBle || w < _nWifi;) {
      if (b * _nWifi <= w * _nBle && b < _nBle) { items.add(true); b++; }
      else { items.add(false); w++; }
    }
    var sent = 0, bi = 0, wi = 0;
    debugPrint('BENCH(real app): /detections "$_screen", inject $_nBle BLE + $_nWifi WiFi @~$_rate/s');

    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var k = 0; k < batch && sent < totalItems; k++, sent++) {
        if (items[sent]) {
          ble.addPhoneDetection(_mac(2, bi), '', -40 - (bi % 55), const []);
          reg.ingest(_bleObs(bi, now)); bi++;
        } else {
          ble.addPhoneWifiDetection(_mac(6, wi), 'net$wi', -45 - (wi % 40), (wi % 13) + 1, 1);
          reg.ingest(_wifiObs(wi, now)); wi++;
        }
      }
      if (sent < totalItems) return;
      timer.cancel();
      Timer(const Duration(milliseconds: 800), () {
        total = 0; janky = 0; worst = 0; sum = 0;
        var ticks = 0;
        Timer.periodic(const Duration(milliseconds: 250), (sustain) {
          final now2 = DateTime.now().millisecondsSinceEpoch;
          for (var k = 0; k < 60; k++) {
            final j = (ticks * 60 + k) % _nBle;
            ble.addPhoneDetection(_mac(2, j), '', -40 - (j % 55), const []);
            reg.ingest(_bleObs(j, now2));
          }
          if (++ticks < 32) return;
          sustain.cancel();
          Timer(const Duration(seconds: 1), () {
            final avg = total == 0 ? 0.0 : sum / total;
            debugPrint('BENCH RESULT (real app "$_screen", steady): frames=$total '
                'janky(>16.7ms)=$janky avg=${avg.toStringAsFixed(2)}ms '
                'worst=${worst.toStringAsFixed(1)}ms live=${app.recentDetections.length} devices=${reg.count}');
          });
        });
      });
    });
  });
}
