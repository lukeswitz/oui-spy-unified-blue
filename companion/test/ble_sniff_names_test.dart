// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble_sniff.dart';
import 'package:oui_spy/core/classify/bt_sig_registry.dart';

void main() {
  BtSigRegistry.load(
    File('assets/bt_sig/company_identifiers.yaml').readAsStringSync(),
    File('assets/bt_sig/member_uuids.yaml').readAsStringSync(),
  );

  const ids = [
    0x004C, 0x0006, 0x00E0, 0x0075, 0x0171, 0x038F, 0x0087, 0x05A7, 0x009E, 0x02F2, 0x0059,
    0x0131, 0x02E5, 0x000F, 0x0001, 0x0157, 0x0499, 0x034D, 0x0D53, 0x08AA,
  ];

  test('each short maker name belongs to the company the Bluetooth SIG lists for that ID', () {
    for (final id in ids) {
      final registered = BtSigRegistry.companies[id]!.toLowerCase();
      final words = sniffMfrName(id).toLowerCase().split(RegExp('[^a-z]+')).where((w) => w.length > 2);
      expect(words.any(registered.contains), isTrue,
          reason: '0x${id.toRadixString(16)} is "${sniffMfrName(id)}" but the SIG lists "$registered"');
    }
  });

  test('IDs upstream mislabeled now show their registered owner', () {
    expect(sniffMfrName(0x0BF3), 'PONE BIOMETRICS AS');
    expect(sniffMfrName(0x004D), 'Staccato Communications, Inc.');
    expect(sniffMfrName(0x00D2), 'Renesas Design Netherlands B.V.');
    expect(sniffMfrName(0x008A), 'Jawbone');
    expect(sniffMfrName(0x0002), 'Intel Corp.');
    expect(sniffMfrName(0x08AA), 'DJI');
  });

  test('an ID missing from the registry shows a question mark', () {
    expect(sniffMfrName(0x2C00), '?');
  });
}
