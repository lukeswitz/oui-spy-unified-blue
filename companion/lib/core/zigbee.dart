// Copyright (c) 2026 Luke Switzer
import 'package:flutter/material.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/theme/app_theme.dart';

const zigbeeMethod = 'ieee802154';
const zigbeeLabel = '802.15.4 (Zigbee, Thread)';
const zigbeeRadioBit = 0x04;
const zigbeeChannelMin = 11;
const zigbeeChannelMax = 26;

bool boardHas802154(String board) => board.toLowerCase().contains('c5');

const zigbeeIcon = Icons.hub;

Color get zigbeeColor => AppTheme.themed(const Color(0xFFA6E22E));

enum ZigbeeFrameType { beacon, data, ack, command, other }

enum ZigbeeBeacon { none, zigbee, thread }

class ZigbeeInfo {
  const ZigbeeInfo({
    required this.frameType,
    required this.pan,
    required this.shortAddress,
    required this.eui64,
    required this.lqi,
    required this.beacon,
    required this.beaconExtPan,
    required this.beaconInfo,
    required this.routerCapacity,
    required this.endDeviceCapacity,
  });

  final ZigbeeFrameType frameType;
  final int? pan;
  final int? shortAddress;
  final String? eui64;
  final int lqi;
  final ZigbeeBeacon beacon;
  final String? beaconExtPan;
  final int beaconInfo;
  final bool routerCapacity;
  final bool endDeviceCapacity;

  static const fixedLength = 16;

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

  static ZigbeeInfo? parse(List<int>? adv) {
    if (adv == null || adv.length < fixedLength) return null;
    final type = switch (adv[0]) {
      0 => ZigbeeFrameType.beacon,
      1 => ZigbeeFrameType.data,
      2 => ZigbeeFrameType.ack,
      3 => ZigbeeFrameType.command,
      _ => ZigbeeFrameType.other,
    };
    final panRaw = adv[2] | (adv[3] << 8);
    final shortRaw = adv[4] | (adv[5] << 8);
    final srcMode = adv[1];
    final beaconKind = switch (adv[15]) {
      1 => ZigbeeBeacon.zigbee,
      2 => ZigbeeBeacon.thread,
      _ => ZigbeeBeacon.none,
    };
    var extPan = false;
    String? extPanText;
    var info = 0;
    var caps = 0;
    if (beaconKind != ZigbeeBeacon.none && adv.length >= fixedLength + 9) {
      extPan = true;
      extPanText = _hex(adv.sublist(fixedLength, fixedLength + 8));
      info = adv[fixedLength + 8];
      if (beaconKind == ZigbeeBeacon.zigbee && adv.length >= fixedLength + 10) caps = adv[fixedLength + 9];
    }
    return ZigbeeInfo(
      frameType: type,
      pan: panRaw == 0xFFFF ? null : panRaw,
      shortAddress: srcMode == 2 ? shortRaw : null,
      eui64: srcMode == 3 ? _hex(adv.sublist(6, 14)) : null,
      lqi: adv[14],
      beacon: extPan ? beaconKind : ZigbeeBeacon.none,
      beaconExtPan: extPanText,
      beaconInfo: info,
      routerCapacity: caps & 0x01 != 0,
      endDeviceCapacity: caps & 0x02 != 0,
    );
  }

  String get panLabel => pan == null ? '--' : '0x${pan!.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  String get addressLabel => eui64 ?? (shortAddress == null ? '--' : '0x${shortAddress!.toRadixString(16).padLeft(4, '0').toUpperCase()}');

  String get frameLabel => switch (frameType) {
        ZigbeeFrameType.beacon => 'BEACON',
        ZigbeeFrameType.data => 'DATA',
        ZigbeeFrameType.ack => 'ACK',
        ZigbeeFrameType.command => 'COMMAND',
        ZigbeeFrameType.other => 'OTHER',
      };

  String get protocolLabel => switch (beacon) {
        ZigbeeBeacon.zigbee => 'Zigbee',
        ZigbeeBeacon.thread => 'Thread',
        ZigbeeBeacon.none => '802.15.4',
      };

  int? get stackProfile => beacon == ZigbeeBeacon.zigbee ? beaconInfo & 0x0F : null;
  int? get nwkVersion => beacon == ZigbeeBeacon.zigbee ? beaconInfo >> 4 : null;
  int? get threadVersion => beacon == ZigbeeBeacon.thread ? beaconInfo >> 4 : null;
}

ZigbeeInfo? zigbeeInfoFor(Detection d) =>
    d.method == zigbeeMethod && d.wardrive != null ? ZigbeeInfo.parse(wardriveAdvRaw[d.wardrive!]) : null;

String zigbeeVendorKey(Detection d) =>
    d.method != zigbeeMethod ? d.macAddress : (zigbeeInfoFor(d)?.eui64 ?? '');

int zigbeeFrequencyMhz(int channel) => 2405 + 5 * (channel - zigbeeChannelMin);

String zigbeeHeadline(Detection d) {
  if (d.ssid.isNotEmpty) return d.ssid;
  final z = zigbeeInfoFor(d);
  if (z == null) return d.macAddress.toUpperCase();
  return 'PAN ${z.panLabel} ${z.addressLabel}';
}
