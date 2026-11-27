// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/gps/gps_provider.dart';
import 'package:oui_spy/core/link/sdr.dart';
import 'package:oui_spy/core/models/engine.dart';
import 'package:oui_spy/core/wardrive_state.dart';
import 'package:oui_spy/core/watch_alert_log.dart';

const _enabled = bool.fromEnvironment('SMOKE');
const _seconds = int.fromEnvironment('SMOKE_SECS', defaultValue: 40);

List<int> _mac(String mac) => [for (final h in mac.split(':')) int.parse(h, radix: 16)];

List<int> _str(String s, int len) {
  final b = List<int>.filled(len, 0);
  final u = utf8.encode(s);
  for (var i = 0; i < u.length && i < len; i++) {
    b[i] = u[i];
  }
  return b;
}

List<int> smokeFrame(Engine e, String mac, int rssi, int channel, int method, List<int> ext) {
  final ts = DateTime.now().millisecondsSinceEpoch & 0xffffffff;
  return [
    e.index,
    ..._mac(mac),
    rssi & 0xff,
    channel,
    ts & 0xff,
    (ts >> 8) & 0xff,
    (ts >> 16) & 0xff,
    (ts >> 24) & 0xff,
    method,
    ..._str('SMOKE', 5),
    ...ext,
  ];
}

List<int> _wardriveExt(String ssid, int auth, String name) => [
      ..._str(ssid, 33),
      auth,
      ..._str(name, 21),
    ];

List<int> _flockExt({required bool raven, required String fw, required int signals, required String name}) => [
      raven ? 1 : 0,
      ..._str(fw, 16),
      3,
      ..._str(name, 32),
      signals,
    ];

List<int> _detectorExt(String desc, int confidence) => [1, ..._str(desc, 32), confidence];

List<int> smokeOdidExt({
  required String uavId,
  required String opId,
  required double lat,
  required double lon,
  required double? pilotLat,
  required double? pilotLon,
  required int alt,
  required int agl,
  required int speed,
  required int heading,
  required String selfId,
}) {
  final b = ByteData(136);
  void put(int off, List<int> v) {
    for (var i = 0; i < v.length; i++) {
      b.setUint8(off + i, v[i]);
    }
  }

  put(0, _str(uavId, 21));
  put(21, _str(opId, 21));
  b.setFloat64(42, lat, Endian.little);
  b.setFloat64(50, lon, Endian.little);
  b.setInt16(58, alt, Endian.little);
  b.setInt16(60, agl, Endian.little);
  b.setInt16(62, speed, Endian.little);
  b.setInt16(64, heading, Endian.little);
  b.setFloat64(66, pilotLat ?? 0, Endian.little);
  b.setFloat64(74, pilotLon ?? 0, Endian.little);
  put(82, _str(selfId, 24));
  b.setInt16(106, alt - 2, Endian.little);
  b.setInt16(108, 1, Endian.little);
  b.setInt16(110, pilotLat == null ? 0 : alt - agl, Endian.little);
  b.setUint16(112, 1, Endian.little);
  b.setUint16(114, 50, Endian.little);
  b.setInt16(116, 120, Endian.little);
  b.setInt16(118, 0, Endian.little);
  b.setUint16(120, 1234, Endian.little);
  put(122, [2, 1, 1, pilotLat == null ? 0 : 1, 1, 1, 2, 0, 2, 10, 4, 3, 2, 1]);
  return b.buffer.asUint8List();
}

List<int> smokePhoneOdidAdv(double lat, double lon, int counter) {
  List<int> le(int v, int n) => [for (var i = 0; i < n; i++) (v >> (8 * i)) & 0xff];
  final basic = [0x02, (1 << 4) | 2, ..._str('DEMO5K6L7M8N9P', 20), 0, 0, 0];
  final loc = [
    0x12, 2 << 4, 45, 20, 0,
    ...le((lat * 1e7).round(), 4), ...le((lon * 1e7).round(), 4),
    ...le((1120 * 2), 2), ...le((1120 * 2), 2), ...le((1030 * 2), 2),
    0, 0, ...le(1234, 2), 0, 0,
  ];
  final op = [0x52, 0, ..._str('GBR-OP-DEMO0002', 20), 0, 0, 0];
  final pack = [0xF2, 0x19, 3, ...basic, ...loc, ...op];
  final data = [0x16, 0xFA, 0xFF, 0x0D, counter & 0xff, ...pack];
  return [data.length, ...data];
}

void runSmokeIfEnabled(ProviderContainer container) {
  if (!_enabled) return;
  final wd = container.read(wardriveProvider);
  var started = false;
  void onWd() {
    if (started || wd.state != WardriveState.running) return;
    started = true;
    wd.removeListener(onWd);
    _inject(container);
  }

  wd.addListener(onWd);
  debugPrint('SMOKE: armed, waiting for a running session');
}

void _inject(ProviderContainer container) {
  final ble = container.read(bleManagerProvider);
  final log = container.read(watchAlertLogProvider);
  final here = container.read(gpsProvider).lastPosition;
  final lat0 = here?.latitude ?? 51.4779;
  final lon0 = here?.longitude ?? -0.0015;
  var tick = 0;
  final counts = <String, int>{};
  final heardAt = <String, (double, double)>{};
  (double, double) fixNow() {
    final fix = container.read(gpsProvider).lastPosition;
    return (fix?.latitude ?? lat0, fix?.longitude ?? lon0);
  }

  (double, double) placeOf(String mac) => heardAt.putIfAbsent(mac, fixNow);
  void send(String label, List<int> frame) {
    final (lat, lon) = fixNow();
    ble.updateGps(latitude: lat, longitude: lon, accuracy: 5);
    ble.injectDetectionFrame(frame);
    counts[label] = (counts[label] ?? 0) + 1;
  }

  final win = math.max(8, (_seconds * 0.08).round());
  debugPrint('SMOKE: injecting for ${_seconds}s, each device heard for ${win}s at the current fix');
  var waitedForFix = 0;
  Timer.periodic(const Duration(seconds: 1), (t) {
    if (tick == 0 && container.read(gpsProvider).lastPosition == null && waitedForFix++ < 20) return;
    final r = (10 + 8 * math.sin(tick * 0.8) + 4 * math.sin(tick * 2.1)).round().clamp(0, 22);
    final block = tick ~/ 6;
    const ssids = [
      'Harbor Cafe', 'Library_Guest', 'Riverside Flats', 'PrintShop-5G', 'Bakery WiFi', 'Studio 4B',
      'Corner Deli', 'Hotel Lobby', 'Gym-Members', 'Dental Office', 'Bus Shelter Free', 'Florist',
      'Flat 12', 'Kings Arms Guest', 'Museum Visitors', 'Market Stall 3', 'Bike Shop', 'Pharmacy',
      'Bookshop WiFi', 'School Office', 'Taxi Rank', 'Hair Studio', 'Pizza Place', 'Laundrette',
    ];
    for (var i = 0; i < 6; i++) {
      final mac = block == 0
          ? '02:00:00:00:01:0$i'
          : '02:00:00:01:${(block & 0xff).toRadixString(16).padLeft(2, '0')}:0$i';
      send('wifi_ap', smokeFrame(Engine.wardrive, mac, -60 - i - r, 1 + (block + i) % 11, 0,
          _wardriveExt(ssids[(block * 6 + i) % ssids.length], 3 + ((block + i) % 3), '')));
    }
    int at(double share) => (_seconds * share).round();
    bool inRange(double share) => tick >= at(share) && tick < at(share) + win;
    int passBy(double share) => (-88 + 38 * math.sin(math.pi * (tick - at(share)) / win)).round() - r ~/ 5;
    if (inRange(0)) {
      for (var i = 0; i < 2; i++) {
        send('wifi_client', smokeFrame(Engine.wardrive, '02:00:00:00:02:0$i', -70 - r, 1, 2,
            [..._wardriveExt('', 0, ''), ..._mac('02:00:00:00:01:00')]));
      }
      for (var i = 0; i < 3; i++) {
        send('wifi_mesh', smokeFrame(Engine.wardrive, '02:00:00:00:0a:0$i', -66 - i - r, 11, 0,
            _wardriveExt('Parkside Mesh', 3, '')));
      }
    }
    const bleNames = [
      'Galaxy Buds2', 'Charge 6', 'JBL Flip 6', 'Apple Watch', 'Tile', 'Bose QC45',
      'Pixel Buds', 'Mi Band 8', 'Kindle', 'Sonos Roam', 'Garmin Fenix', 'LE-Bose',
    ];
    for (var i = 0; i < 3; i++) {
      final mac = block == 0
          ? '02:00:00:00:03:0$i'
          : '02:00:00:03:${(block & 0xff).toRadixString(16).padLeft(2, '0')}:0$i';
      send('ble_adv', smokeFrame(Engine.wardrive, mac, -65 - r, 37, 1,
          _wardriveExt('', 0, bleNames[(block * 3 + i) % bleNames.length])));
    }
    send('ble_carried', smokeFrame(Engine.wardrive, '02:00:00:00:09:00', -52 - r ~/ 3, 37, 1,
        _wardriveExt('', 0, 'Pixel Buds')));
    if (inRange(0.25)) {
      send('flockBle', smokeFrame(Engine.flockBle, '02:00:00:00:04:00', passBy(0.25), 37, 1,
          _flockExt(raven: true, fw: '1.3.2', signals: 0x47, name: 'Penguin-1234567890')));
    }
    if (inRange(0.55)) {
      send('flockWifi', smokeFrame(Engine.flockWifi, '02:00:00:00:04:01', passBy(0.55), 6, 4,
          _flockExt(raven: false, fw: '', signals: 0x05, name: 'Flock-A1B2C3')));
    }
    const detectors = {
      'deauth_storm': (4, 6, 'Deauth flood'),
      'flipper': (3, 0, 'Flipper Zero'),
      'glasses': (7, 0, 'Ray-Ban Meta'),
      'probe_ssid': (5, 6, 'Directed probe'),
      'camera': (9, 6, 'Ring Doorbell'),
      'tracker': (2, 0, 'AirTag'),
    };
    var k = 0;
    for (final e in detectors.entries) {
      final (method, ch, desc) = e.value;
      if (inRange(0.08 + k * 0.13)) {
        send('detector:${e.key}', smokeFrame(Engine.detector, '02:00:00:00:05:0$k', -50 - k - r, ch, method,
            _detectorExt(desc, 1 + k % 3)));
      }
      k++;
    }
    final orbit = tick * 2 * math.pi / 90;
    send('drone_full', smokeFrame(Engine.skySpy, '02:00:00:00:06:00', -62 - r, 6, 0, smokeOdidExt(
      uavId: 'DEMO1A2B3C4D5E',
      opId: 'GBR-OP-DEMO0001',
      lat: lat0 + 0.0012 + 0.0010 * math.sin(orbit),
      lon: lon0 - 0.0004 + 0.0016 * math.cos(orbit),
      pilotLat: lat0 + 0.0004,
      pilotLon: lon0 + 0.0010,
      alt: 1700 + (tick % 20),
      agl: 60,
      speed: 5,
      heading: ((orbit * 180 / math.pi + 90) % 360).round(),
      selfId: 'Survey flight',
    )));
    if (inRange(0.35)) {
      final hover = placeOf('02:00:00:00:06:01');
      send('drone_partial', smokeFrame(Engine.skySpy, '02:00:00:00:06:01', -75 - r, 6, 0, smokeOdidExt(
        uavId: 'DEMO9Z8Y7X6W5V',
        opId: '',
        lat: hover.$1,
        lon: hover.$2,
        pilotLat: null,
        pilotLon: null,
        alt: 1650,
        agl: 30,
        speed: 0,
        heading: 270,
        selfId: '',
      )));
    }
    if (inRange(0.85)) {
      send('uniPwn', smokeFrame(Engine.uniPwn, '02:00:00:00:07:00', -68 - r, 37, 0,
          [..._str('Go2', 8), 0]));
      send('foxhunter', smokeFrame(Engine.foxhunter, '02:00:00:00:08:00', -45 - r, 37, 0, const []));
    }
    if (inRange(0.65)) {
      final hover = placeOf('02:00:00:00:06:02');
      ble.addPhoneOdid('02:00:00:00:06:02', -70 - r, smokePhoneOdidAdv(hover.$1, hover.$2, tick));
      counts['phone_odid'] = (counts['phone_odid'] ?? 0) + 1;
    }

    final (hLat, hLon) = fixNow();
    if (tick == at(0.1)) {
      log(kind: 'drone_loiter', title: 'Drone near you', reason: 'Hovering 180 m away for 6 min',
          subject: '02:00:00:00:06:00', lat: hLat, lon: hLon);
    }
    if (tick == at(0.3)) {
      log(kind: 'beacon_flood', title: 'Wi-Fi beacon flood', reason: '24 networks from one radio',
          subject: '02:00:00:00:09:00', lat: hLat, lon: hLon);
      log(kind: 'car_follow', title: 'Car following you', reason: 'Same tire sensors over 3 km and 14 min',
          subject: '02:00:00:00:03:00');
    }
    if (tick == at(0.5)) {
      log(kind: 'trusted_network', title: 'Possible evil twin of "Harbor Cafe"', reason: 'Weaker security',
          subject: '02:00:00:00:01:01', lat: hLat, lon: hLon);
    }
    if (tick == at(0.7)) {
      log(kind: 'cell_watch', title: 'Cell network warning', reason: 'Dropped to 2G', subject: 'CELL',
          lat: hLat, lon: hLon);
      log(kind: 'gps_watch', title: 'GPS warning', reason: 'Position jumped 4 km', subject: 'GPS');
    }
    if (tick == at(0.9)) {
      log(kind: 'aircraft_circle', title: 'Aircraft circling you', reason: 'DEM123 (ABC123) circled twice',
          subject: 'ABC123', lat: hLat, lon: hLon);
      counts['alerts'] = 7;
    }
    final sdr = container.read(sdrControllerProvider);
    final rnd = math.Random(tick);
    sdr.injectFrame(SdrFrame(
      centerHz: 100100000,
      rate: 2400000,
      power: [
        for (var i = 0; i < 512; i++)
          () {
            final edge = math.pow((i - 255.5).abs() / 256, 6).toDouble();
            final floor = -80 - 9 * edge + 1.6 * (rnd.nextDouble() + rnd.nextDouble() - 1);
            var sig = 0.0;
            for (final (bin, height) in const [(43, 24.0), (128, 37.0), (299, 30.0), (427, 17.0)]) {
              final x = (i - bin) / 21;
              sig = math.max(sig, height * math.exp(-x * x * x * x) * (0.93 + 0.07 * math.sin(i * 1.7 + tick)));
            }
            final dc = i == 256 ? 9.0 : 0.0;
            return floor + sig + dc + (sig > 3 ? 2.2 * (rnd.nextDouble() - 0.5) : 0);
          }(),
      ],
    ));
    for (final d in [
      SdrDetection(kind: 'rtl433', fields: {
        'model': 'ERT-SCM', 'id': 10001, 'consumption_data': 12000 + tick * 3, 'rssi': -20,
      }),
      SdrDetection(kind: 'rtl433', fields: {
        'model': 'Acurite-Tower', 'id': 2002, 'temperature_C': 21.5, 'humidity': 40, 'rssi': -25,
      }),
      SdrDetection(kind: 'tpms', fields: {'model': 'Schrader', 'id': '0000ABCD', 'pressure_kPa': 230, 'rssi': -30}),
      SdrDetection(kind: 'adsb', fields: {
        'icao': 'A835AF', 'callsign': 'UAL88', 'lat': lat0 + 0.01 + tick * 0.0004, 'lon': lon0 - 0.02 + tick * 0.0006,
        'altitude': 37000, 'velocity': 478, 'heading': 95,
      }),
      SdrDetection(kind: 'adsb', fields: {
        'icao': '4CA853', 'callsign': 'RYR1234', 'lat': lat0 - 0.015 + tick * 0.0003, 'lon': lon0 + 0.01 - tick * 0.0005,
        'altitude': 35000, 'velocity': 452, 'heading': 270,
      }),
    ]) {
      sdr.injectFrame(SdrFrame(detection: d));
      counts['sdr:${d.kind}'] = (counts['sdr:${d.kind}'] ?? 0) + 1;
    }
    if (++tick < _seconds) return;
    t.cancel();
    debugPrint('SMOKE: done ${jsonEncode(counts)}');
  });
}
