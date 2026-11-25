// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

void main() {
  final eng = SignatureEngine(Signature.parseCatalog(File('assets/fieldwatch-signatures-v2.json').readAsStringSync()));

  test('locally administered AP BSSID matches its universal OUI', () {
    const o = Observation(key: 'W:1', kind: RadioKind.wifi, mac: 'B6:1E:52:11:22:33', isAp: true);
    expect(eng.match(o), isNotEmpty);
  });

  test('locally administered client MAC does not borrow a vendor OUI', () {
    const o = Observation(key: 'W:2', kind: RadioKind.wifi, mac: 'B6:1E:52:11:22:33');
    expect(eng.match(o), isEmpty);
  });
}
