import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/bt_sig_registry.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/vendor_class.dart';

void main() {
  final vendors = {
    for (final l in const LineSplitter().convert(utf8.decode(gzip.decode(File('assets/oui_vendors.tsv.gz').readAsBytesSync()))))
      if (l.contains('\t')) l.split('\t')[1].trim(),
  };
  BtSigRegistry.load(
    File('assets/bt_sig/company_identifiers.yaml').readAsStringSync(),
    File('assets/bt_sig/member_uuids.yaml').readAsStringSync(),
  );

  test('every vendor rule matches a real IEEE or Bluetooth SIG company name', () {
    final names = {...vendors, ...BtSigRegistry.companies.values, ...BtSigRegistry.memberUuids.values}
        .map((n) => n.toLowerCase())
        .toList();
    final dead = [
      for (final r in VendorClass.rules)
        if (!names.any((n) => VendorClass.wordMatch(n, r.token))) r.token,
    ];
    expect(dead, isEmpty);
  });

  test('agent table fills gaps and refines generic brands; specific hand rules win', () {
    VendorClass.loadTable([for (final a in VendorClass.tableAssets) File(a).readAsStringSync()]);
    expect(VendorClass.ruleFor('PARROT AUTOMOTIVE SAS')?.bucket, 'vehicle');
    expect(VendorClass.ruleFor('Panasonic Automotive Systems Company of America')?.bucket, 'vehicle');
    expect(VendorClass.ruleFor('Hewlett Packard Enterprise')?.bucket, 'network');
    expect(VendorClass.ruleFor('Geotab')?.label, 'a Geotab fleet tracker');
    expect(VendorClass.ruleFor('TOMOE VALVE CO.,LTD')?.bucket, isNot('console'));
    expect(VendorClass.ruleFor('Valve Corporation')?.bucket, 'console');
  });

  test('chip-vendor MACs name the product classes the chip ships in', () {
    VendorClass.loadTable([for (final a in VendorClass.tableAssets) File(a).readAsStringSync()]);
    const o = Observation(key: 'B:3', kind: RadioKind.ble, mac: '00:11:22:33:44:55', name: 'TestDevice');
    expect(DeviceExplain.listLabel(o, vendor: 'Silicon Laboratories'),
        'Silicon Laboratories · Zigbee/Z-Wave smart-home device or smart meter');
    expect(VendorClass.ruleFor('Texas Instruments')!.label, contains('TI chip'));
    expect(VendorClass.ruleFor('Nordic Semiconductor ASA')!.label, contains('Nordic chip'));
    expect(VendorClass.ruleFor('Realtek Semiconductor Corp.')!.label, contains('Realtek chip'));
    expect(VendorClass.ruleFor('MediaTek, Inc.')!.label, contains('MediaTek chip'));
    expect(VendorClass.ruleFor('Murata Manufacturing Co., Ltd.')!.label, contains('Murata'));
    expect(VendorClass.ruleFor('AzureWave Technology Inc.')!.label, contains('laptop or PC'));
  });

  test('every Wi-Fi vendor rule matches a real IEEE or Bluetooth SIG company name', () {
    final names = {...vendors, ...BtSigRegistry.companies.values}.map((n) => n.toLowerCase()).toList();
    expect([for (final r in VendorClass.wifiRules) if (!names.any((n) => VendorClass.wordMatch(n, r.token))) r.token], isEmpty);
  });

  test('word match rejects partial words', () {
    expect(VendorClass.ruleFor('SonoSite, Inc.'), isNull);
    expect(VendorClass.ruleFor('Engineering LLC'), isNull);
    expect(VendorClass.ruleFor('Sonos, Inc.')!.bucket, 'audio-personal');
    expect(VendorClass.ruleFor('Hewlett Packard Enterprise')!.bucket, 'network');
  });

  test('SIG registry parses and resolves company IDs', () {
    expect(BtSigRegistry.companies.length, greaterThan(4000));
    expect(BtSigRegistry.memberUuids.length, greaterThan(700));
    expect(BtSigRegistry.companies[0x0275], 'Geotab');
    expect(BtSigRegistry.companies[0x0BA9], 'Allterco Robotics ltd');
    expect(BtSigRegistry.companies[0x004C], contains('Apple'));
  });

  test('randomized MAC never gets a vendor guess; factory MAC does', () {
    const pub = Observation(key: 'W:1', kind: RadioKind.wifi, mac: '44:19:B6:11:22:33', name: '');
    expect(DeviceExplain.guess(pub, const [], vendor: 'Hangzhou Hikvision Digital Technology Co.,Ltd.').headline,
        contains('Hikvision'));
    const rnd = Observation(key: 'W:2', kind: RadioKind.wifi, mac: '46:19:B6:11:22:33', name: '');
    expect(VendorClass.hint(rnd, 'Hangzhou Hikvision Digital Technology Co.,Ltd.'), isNull);
  });

  test('BLE company ID resolves through SIG to a category', () {
    const o = Observation(
      key: 'B:1',
      kind: RadioKind.ble,
      mac: 'D0:11:22:33:44:55',
      mfgRecords: [MfgRecord(0x0275, '00')],
    );
    expect(BtSigRegistry.hints(o).map((h) => h.label), contains('a Geotab fleet tracker'));
    const unknown = Observation(key: 'B:2', kind: RadioKind.ble, mac: 'D0:11:22:33:44:56', mfgRecords: [MfgRecord(0x1130, '00')]);
    expect(BtSigRegistry.hints(unknown).single.label, 'a Pi Variables, Inc. device');
  });
}
