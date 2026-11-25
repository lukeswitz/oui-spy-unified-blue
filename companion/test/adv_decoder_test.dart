// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

Map<String, String> _byLabel(List<AdvField> f) => {for (final x in f) x.label: x.value};

Observation _ble(String mfgHex) => Observation(
      key: 'BLE:AA:BB:CC:DD:EE:99',
      kind: RadioKind.ble,
      mac: 'AA:BB:CC:DD:EE:99',
      rssi: -50,
      mfgRecords: [MfgRecord(0x004C, mfgHex)],
    );

String _ascii(String s) => s.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  test('apple iBeacon decodes uuid major minor tx', () {
    const mfg = '0215E2C56DB5DFFB48D2B060D0F5A71096E000010002C5';
    final m = _byLabel(AdvPayloadDecoder.decodeManufacturer(const MfgRecord(0x004C, mfg)));
    expect(m['Apple Continuity type'], '0x02 · iBeacon');
    expect(m['iBeacon UUID'], 'e2c56db5-dffb-48d2-b060-d0f5a71096e0');
    expect(m['iBeacon major / minor'], '1 / 2');
    expect(m['iBeacon calibrated TX']!.startsWith('-59'), isTrue);
  });

  test('apple proximity pairing names AirPods', () {
    const mfg = '0707010F2051981100';
    final m = _byLabel(AdvPayloadDecoder.decodeManufacturer(const MfgRecord(0x004C, mfg)));
    expect(m['Product'], 'AirPods (2nd generation)');
    expect(m['Battery (left / right)'], '80% / 90%');
    expect(m['Case battery'], '10%');
    expect(m['Charging'], 'case');
  });

  test('apple find my labels offline finding', () {
    final f = AdvPayloadDecoder.decodeManufacturer(MfgRecord(0x004C, '120A${'00' * 10}'));
    expect(f.any((x) => x.label == 'Find My / Offline Finding'), isTrue);
  });

  test('unknown company yields no fields', () {
    expect(AdvPayloadDecoder.decodeManufacturer(const MfgRecord(0x9999, 'AABB')), isEmpty);
    expect(AdvPayloadDecoder.decodeManufacturer(const MfgRecord(0x004C, 'XYZ')), isEmpty);
  });

  test('fast pair 3-byte model id is pairing', () {
    final m = _byLabel(AdvPayloadDecoder.decodeService(const ServiceDataRecord('FE2C', '000006')));
    expect(m['Google Fast Pair']!.contains('pairing mode'), isTrue);
    expect(m['Model ID'], '0x000006 (not in the local name list)');
  });

  test('fast pair longer payload is account-key bloom', () {
    final f = AdvPayloadDecoder.decodeService(const ServiceDataRecord('FE2C', '01020304050607'));
    expect(f.single.value.contains('Already paired'), isTrue);
  });

  test('eddystone uid splits namespace and instance', () {
    final m = _byLabel(AdvPayloadDecoder.decodeService(
        const ServiceDataRecord('FEAA', '00C500112233445566778899AABBCCDDEEFF0000')));
    expect(m['Eddystone-UID namespace'], '00112233445566778899');
    expect(m['Eddystone-UID instance'], 'AABBCCDDEEFF');
  });

  test('find hub frame is not eddystone', () {
    final f = AdvPayloadDecoder.decodeService(ServiceDataRecord('FEAA', '41${'11' * 20}00'));
    expect(f.firstWhere((x) => x.label == 'Find Hub').value, 'separated (unwanted-tracking mode)');
    expect(f.any((x) => x.label.startsWith('Eddystone')), isFalse);
  });

  test('eddystone url expands scheme and suffix', () {
    final f = AdvPayloadDecoder.decodeService(ServiceDataRecord('FEAA', '10C501${_ascii('example')}07'));
    expect(f.single.value, 'https://www.example.com');
  });

  test('microsoft cdp names device type', () {
    final f = AdvPayloadDecoder.decodeManufacturer(const MfgRecord(0x0006, '0109'));
    expect(f.single.value.contains('Windows desktop'), isTrue);
  });

  test('role hints flag iBeacon and tesla key', () {
    final hints = AdvPayloadDecoder.roleHints(_ble('0215E2C56DB5DFFB48D2B060D0F5A71096E000010002C5'));
    expect(hints.any((h) => h.label == 'an iBeacon'), isTrue);
    final tesla = _ble('${teslaIBeaconMfgPrefix}00010002C5');
    expect(AdvPayloadDecoder.roleHints(tesla).any((h) => h.label.contains('Tesla')), isTrue);
  });
}
