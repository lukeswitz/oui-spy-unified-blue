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
const _flood = String.fromEnvironment('BENCH_FLOOD');
const _floodN = int.fromEnvironment('FLOOD_N', defaultValue: 1000);
const _floodRate = int.fromEnvironment('FLOOD_RATE', defaultValue: 100);
const _floodSecs = int.fromEnvironment('FLOOD_SECS', defaultValue: 60);

String _hx(int v) => (v & 0xff).toRadixString(16).padLeft(2, '0').toUpperCase();

Observation _crowdObs(int i, int now, {bool spam = false}) {
  final mac = '${spam ? '5A' : '6E'}:${_hx(i >> 16)}:${_hx(i >> 8)}:${_hx(i)}:${_hx(i * 7)}:${_hx(i * 13)}';
  final kind = spam ? 0 : i % 4;
  return Observation(
    key: 'BLE:$mac',
    kind: RadioKind.ble,
    mac: mac,
    name: kind == 1 ? 'Phone $i' : '',
    rssi: spam ? -52 : -40 - (i * 37 % 56),
    firstSeenMs: now,
    lastSeenMs: now,
    mfgRecords: [
      if (kind == 0) MfgRecord(0x004C, '0706010E2022F5${_hx(i)}'),
      if (kind == 2) MfgRecord(0x004C, '1005031C${_hx(i)}A1B2'),
    ],
  );
}

void _runFlood(ProviderContainer container) {
  final reg = container.read(deviceRegistryProvider);
  final source = _flood.endsWith('_phone') ? 'phone' : 'esp32';
  final spam = _flood.startsWith('spam');
  var frames = 0, janky = 0;
  var worst = 0.0, sum = 0.0, buildSum = 0.0, rasterSum = 0.0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final ms = (t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds) / 1000.0;
      frames++;
      sum += ms;
      buildSum += t.buildDuration.inMicroseconds / 1000.0;
      rasterSum += t.rasterDuration.inMicroseconds / 1000.0;
      if (ms > worst) worst = ms;
      if (ms > 16.7) janky++;
    }
  });
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await reg.loadCatalog();
    container.read(routerProvider).go('/detections');
    container.read(detectionsViewProvider.notifier).state =
        _screen == 'live' ? DetectionsView.live : DetectionsView.devices;
    final start = DateTime.now().millisecondsSinceEpoch;
    final lastSent = <int, int>{};
    var next = 0, spamNext = 0, flagged = -1;
    var ingestUs = 0, ingests = 0;
    debugPrint('BENCHF start mode=$_flood source=$source n=$_floodN rate=$_floodRate/s secs=$_floodSecs');
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sw = Stopwatch()..start();
      final perTick = (_floodRate / 10).ceil();
      if (spam) {
        for (var k = 0; k < perTick; k++) {
          reg.ingest(_crowdObs(spamNext++, now, spam: true), source: source);
          ingests++;
        }
      } else {
        for (var k = 0; k < perTick && next < _floodN; k++, next++) {
          reg.ingest(_crowdObs(next, now), source: source);
          lastSent[next] = now;
          ingests++;
        }
        for (final e in lastSent.entries) {
          if (now - e.value >= 10000) {
            reg.ingest(_crowdObs(e.key, now), source: source);
            lastSent[e.key] = now;
            ingests++;
          }
        }
      }
      ingestUs += sw.elapsedMicroseconds;
      final n = reg.pairingFlood.notice;
      if (n != null && flagged < 0) flagged = now - start;
      if ((now - start) ~/ 1000 != ((now - start - 100) ~/ 1000)) {
        final avg = frames == 0 ? 0.0 : sum / frames;
        final gw = Stopwatch()..start();
        var gn = 0;
        for (final d in reg.devices) {
          if (d.guess.confidence.index >= 0) gn++;
        }
        final guessMs = gw.elapsedMicroseconds / 1000.0;
        gw.reset();
        final ow = Stopwatch()..start();
        for (final d in reg.devices) {
          if (d.ownGuess.confidence.index >= 0) gn++;
        }
        final ownMs = ow.elapsedMicroseconds / 1000.0;
        debugPrint('BENCHF guessAll=${guessMs.toStringAsFixed(1)}ms ownGuessAll=${ownMs.toStringAsFixed(1)}ms n=$gn');
        debugPrint('BENCHF t=${(now - start) ~/ 1000}s devices=${reg.count} ingests=$ingests '
            'ingestMs=${(ingestUs / 1000).toStringAsFixed(1)} frames=$frames janky=$janky '
            'avg=${avg.toStringAsFixed(2)} worst=${worst.toStringAsFixed(1)} '
            'build=${(frames == 0 ? 0 : buildSum / frames).toStringAsFixed(1)} '
            'raster=${(frames == 0 ? 0 : rasterSum / frames).toStringAsFixed(1)} '
            'flood=${n == null ? '-' : '${n.title()} p${n.popupCount} n${n.nameCount}'}');
        frames = 0; janky = 0; worst = 0; sum = 0; buildSum = 0; rasterSum = 0; ingestUs = 0; ingests = 0;
      }
      if (now - start >= _floodSecs * 1000) {
        t.cancel();
        debugPrint('BENCHF done mode=$_flood firstFlagMs=$flagged devices=${reg.count}');
      }
    });
  });
}

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
  if (_flood.isNotEmpty) {
    _runFlood(container);
    return;
  }

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
