// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

Observation _w(String mac, int at) =>
    Observation(key: 'WIFI:$mac', kind: RadioKind.wifi, mac: mac, name: 'cam', rssi: -60, firstSeenMs: at, lastSeenMs: at);

void main() {
  final sig = Signature.fromJson({
    'id': 'fleet-test',
    'name': 'Test cluster',
    'kind': 'CAMERA',
    'minPeers': 3,
    'sequentialMac': true,
    'rules': [
      {'kind': 'OUI', 'text': 'AA:BB:CC'},
    ],
  });
  final e = SignatureEngine([sig]);
  const now = 100000;

  test('cluster fleet never matches a single device', () {
    expect(sig.cluster, isTrue);
    expect(e.match(_w('AA:BB:CC:00:00:10', now)), isEmpty);
  });

  test('three sequential peers in window match, far MAC and stale peer do not count', () {
    final a = _w('AA:BB:CC:00:00:10', now);
    final devs = [a, _w('AA:BB:CC:00:00:12', now), _w('AA:BB:CC:00:00:20', now - 5000)];
    expect(e.clusterMatch(a, devs, now).map((s) => s.id), ['fleet-test']);
    final weak = [a, _w('AA:BB:CC:00:00:12', now), _w('AA:BB:CC:00:F0:00', now), _w('AA:BB:CC:00:00:14', now - 70000)];
    expect(e.clusterMatch(a, weak, now), isEmpty);
  });
}
