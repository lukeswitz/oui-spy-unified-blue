// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/probes/probe_frame.dart';
import 'package:oui_spy/core/probes/probe_intel.dart';
import 'package:path_provider/path_provider.dart';

/// Every Wi-Fi probe request the connected board hears, per asking device: the networks it names, how
/// often, and when. Fed by the detector's probe check and by Wi-Fi PCAP captures; kept on the phone.
class ProbeStore extends ChangeNotifier {
  ProbeStore({Future<File> Function()? file, int Function()? clock})
      : _file = file ?? _defaultFile,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    runStart = _clock();
  }

  static const int maxDevices = 5000;
  static const int maxNamesPerDevice = 64;
  static const Duration _notifyEvery = Duration(milliseconds: 300);
  static const Duration _saveEvery = Duration(seconds: 3);

  final Future<File> Function() _file;
  final int Function() _clock;
  final Map<String, ProbeDev> _devs = {};
  late final int runStart;
  Timer? _notifyTimer;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _disposed = false;
  Future<void> _saving = Future<void>.value();

  static Future<File> _defaultFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/probes.json');
  }

  int get deviceCount => _devs.length;
  Iterable<ProbeDev> get devices => _devs.values;
  ProbeDev? deviceFor(String mac) => _devs[normalizeMac(mac)];

  void add({required String mac, String? ssid, int rssi = 0, int channel = 0, int freqMhz = 0, int? atMs}) {
    final key = normalizeMac(mac);
    final now = atMs ?? _clock();
    final dev = _devs[key] ??= ProbeDev(mac: key, first: now, last: now);
    if (now < dev.first) dev.first = now;
    if (now > dev.last) dev.last = now;
    dev.count++;
    if (rssi != 0) dev.rssi = rssi;
    dev.bands |= freqMhz > 0 ? bandOfFreq(freqMhz) : bandOfChannel(channel);
    final name = ssid?.trim();
    if (name != null && name.isNotEmpty) {
      dev.ssids[name] = (dev.ssids[name] ?? 0) + 1;
      dev.ssidLast[name] = now;
      if (dev.ssids.length > maxNamesPerDevice) {
        final oldest = dev.ssidLast.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
        dev.ssids.remove(oldest);
        dev.ssidLast.remove(oldest);
      }
    }
    if (_devs.length > maxDevices) {
      final stale = _devs.values.reduce((a, b) => a.last <= b.last ? a : b);
      _devs.remove(stale.mac);
    }
    _changed();
  }

  void addSighting(ProbeSighting s) => add(mac: s.mac, ssid: s.ssid, rssi: s.rssi, freqMhz: s.freqMhz);

  void _changed() {
    _dirty = true;
    _notifyTimer ??= Timer(_notifyEvery, () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
    _saveTimer ??= Timer(_saveEvery, () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      final list = raw is Map ? raw['devices'] : null;
      if (list is! List) return;
      for (final e in list) {
        final d = ProbeDev.fromJson(e);
        if (d == null) continue;
        final live = _devs[d.mac];
        if (live == null) {
          _devs[d.mac] = d;
          continue;
        }
        live.first = d.first < live.first ? d.first : live.first;
        live.last = d.last > live.last ? d.last : live.last;
        live.count += d.count;
        live.bands |= d.bands;
        d.ssids.forEach((k, v) => live.ssids[k] = (live.ssids[k] ?? 0) + v);
        d.ssidLast.forEach((k, v) => live.ssidLast[k] = v > (live.ssidLast[k] ?? 0) ? v : live.ssidLast[k]!);
      }
      if (!_disposed) notifyListeners();
    } on FormatException catch (e) {
      DebugLog.log('PROBES: probes.json unreadable: $e');
    } on FileSystemException catch (e) {
      DebugLog.log('PROBES: probes.json read failed: $e');
    }
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return _saving;
    _dirty = false;
    final body = jsonEncode({'devices': [for (final d in _devs.values) d.toJson()]});
    return _saving = _saving.then((_) async {
      try {
        final f = await _file();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(body, flush: true);
        await tmp.rename(f.path);
      } on FileSystemException catch (e) {
        DebugLog.log('PROBES: save failed: $e');
        _dirty = true;
      }
    });
  }

  Future<void> clear() async {
    _devs.clear();
    _dirty = true;
    notifyListeners();
    await flush();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}

final probeStoreProvider = ChangeNotifierProvider<ProbeStore>((ref) {
  final store = ProbeStore();
  final ble = ref.read(bleManagerProvider);
  final subs = <StreamSubscription<Object?>>[
    ble.detections.listen((d) {
      if (d.method != 'probe_ssid') return;
      final name = d.detector?.filterDescription?.trim() ?? '';
      if (name.isEmpty) return;
      store.add(mac: d.macAddress, ssid: name, rssi: d.rssi, channel: d.channel);
    }),
    ble.pcapWifiRecords.listen((rec) {
      final s = parseProbeRecord(rec);
      if (s != null) store.addSighting(s);
    }),
  ];
  store.load();
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    store.flush();
  });
  return store;
});
