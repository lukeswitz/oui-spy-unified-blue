// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:oui_spy/core/watchlist_state.dart';

const int detRuleNameContains = 0x01;
const int detRuleNamePrefix = 0x02;
const int detRuleNamePattern = 0x03;
const int detRuleCompanyId = 0x04;
const int detRuleCompanyData = 0x05;
const int detRuleUuid128 = 0x06;
const int detRuleWifiProbe = 0x07;
const int detRuleWifiBeacon = 0x08;

/// BLE DetectorConfig op that adds one extension rule: [0x05][type][len][payload].
const int detCfgOpRule = 0x05;

const int detMacMax = 50;
const int detUuidMax = 50;
const int detExtMax = 32;

/// What one mesh frame carries of a detector list, in bytes.
const int detMeshListMax = 220;

/// One extension rule as the detector stores and sends it: a type byte and its payload.
class DetectorRule {
  const DetectorRule(this.type, this.payload);
  final int type;
  final Uint8List payload;

  Uint8List get record => Uint8List.fromList([type, payload.length, ...payload]);
  Uint8List get op => Uint8List.fromList([detCfgOpRule, type, payload.length, ...payload]);

  @override
  bool operator ==(Object other) =>
      other is DetectorRule && other.type == type && _sameBytes(other.payload, payload);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(payload));
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _hex(String s) {
  final c = s.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  return Uint8List.fromList([for (var i = 0; i + 1 < c.length; i += 2) int.parse(c.substring(i, i + 2), radix: 16)]);
}

extension WatchlistEntryWire on WatchlistEntry {
  bool get isUuid128 => matchType == WatchlistMatchType.serviceUuid && identifier.replaceAll('-', '').length == 32;

  /// True for entries sent as extension rules; MAC, prefix and 16-bit service UUID entries use the older records.
  bool get isExtWire => matchType.isExtRule || isUuid128;

  /// The extension rule for this entry; null when it is not one or its identifier does not parse.
  DetectorRule? get rule => detectorRuleOf(matchType, identifier);
}

DetectorRule? detectorRuleOf(WatchlistMatchType type, String identifier) {
  final id = normalizeWatchlistId(identifier, type);
  if (id == null) return null;
  switch (type) {
    case WatchlistMatchType.nameContains:
      return DetectorRule(detRuleNameContains, Uint8List.fromList(id.codeUnits));
    case WatchlistMatchType.namePrefix:
      return DetectorRule(detRuleNamePrefix, Uint8List.fromList(id.codeUnits));
    case WatchlistMatchType.namePattern:
      return DetectorRule(detRuleNamePattern, Uint8List.fromList(id.codeUnits));
    case WatchlistMatchType.companyId:
      final b = _hex(id);
      return DetectorRule(detRuleCompanyId, Uint8List.fromList([b[1], b[0]]));
    case WatchlistMatchType.companyData:
      final cid = _hex(id.substring(0, 4));
      final parts = id.substring(5).split('/');
      return DetectorRule(
          detRuleCompanyData, Uint8List.fromList([cid[1], cid[0], ..._hex(parts[0]), ..._hex(parts[1])]));
    case WatchlistMatchType.serviceUuid:
      if (id.length == 4) return null;
      return DetectorRule(detRuleUuid128, Uint8List.fromList(_hex(id).reversed.toList()));
    case WatchlistMatchType.wifiProbe:
      return DetectorRule(detRuleWifiProbe, _hex(id));
    case WatchlistMatchType.wifiBeacon:
      return DetectorRule(detRuleWifiBeacon, _hex(id));
    case WatchlistMatchType.oui:
    case WatchlistMatchType.fullMac:
    case WatchlistMatchType.name:
    case WatchlistMatchType.makerName:
      return null;
  }
}

/// Case-insensitive name tests with the detector's rules: contains, starts with, and a whole-name
/// pattern where # is a hex digit, ? any character and * any run.
bool nameRuleMatches(WatchlistMatchType type, String identifier, String name) {
  final id = identifier.toLowerCase();
  final n = name.toLowerCase();
  switch (type) {
    case WatchlistMatchType.nameContains:
      return id.isNotEmpty && n.contains(id);
    case WatchlistMatchType.namePrefix:
      return id.isNotEmpty && n.startsWith(id);
    case WatchlistMatchType.namePattern:
      return _glob(id, n);
    default:
      return false;
  }
}

bool _glob(String p, String s) {
  var pi = 0, si = 0, star = -1, mark = 0;
  bool one(String pc, String sc) =>
      pc == '?' || (pc == '#' ? RegExp(r'[0-9a-f]').hasMatch(sc) : pc == sc);
  while (si < s.length) {
    if (pi < p.length && p[pi] == '*') {
      star = pi++;
      mark = si;
    } else if (pi < p.length && one(p[pi], s[si])) {
      pi++;
      si++;
    } else if (star >= 0) {
      pi = star + 1;
      si = ++mark;
    } else {
      return false;
    }
  }
  while (pi < p.length && p[pi] == '*') {
    pi++;
  }
  return pi == p.length;
}

String ruleHint(WatchlistMatchType t) => switch (t) {
      WatchlistMatchType.oui => 'AA:BB:CC',
      WatchlistMatchType.fullMac => 'AA:BB:CC:DD:EE:FF',
      WatchlistMatchType.serviceUuid => 'FD5F',
      WatchlistMatchType.name => 'Device name',
      WatchlistMatchType.nameContains => 'Flipper',
      WatchlistMatchType.namePrefix => 'Flipper ',
      WatchlistMatchType.namePattern => 'S################C',
      WatchlistMatchType.companyId => '004C',
      WatchlistMatchType.companyData => '004C:121910/FFFF30',
      WatchlistMatchType.wifiProbe => 'AA:BB:CC',
      WatchlistMatchType.wifiBeacon => 'AA:BB:CC',
      WatchlistMatchType.makerName => 'Motorola',
    };

String ruleLabel(WatchlistMatchType t) => switch (t) {
      WatchlistMatchType.oui => 'Maker prefix (first 3 bytes)',
      WatchlistMatchType.fullMac => 'Full MAC address',
      WatchlistMatchType.serviceUuid => '16-bit or 128-bit service UUID',
      WatchlistMatchType.name => 'Name pattern',
      WatchlistMatchType.nameContains => 'Text in the Bluetooth name',
      WatchlistMatchType.namePrefix => 'Start of the Bluetooth name',
      WatchlistMatchType.namePattern => 'Whole Bluetooth name pattern',
      WatchlistMatchType.companyId => 'Bluetooth company ID (hex)',
      WatchlistMatchType.companyData => 'Company data',
      WatchlistMatchType.wifiProbe => 'Wi-Fi probe address prefix',
      WatchlistMatchType.wifiBeacon => 'Wi-Fi beacon address prefix',
      WatchlistMatchType.makerName => 'Maker name',
    };

String ruleHelp(WatchlistMatchType t) => switch (t) {
      WatchlistMatchType.oui => 'Matches the first 3 bytes of a Bluetooth or Wi-Fi address.',
      WatchlistMatchType.fullMac => 'Matches one exact address.',
      WatchlistMatchType.serviceUuid => 'Matches an advertised service UUID, such as FD5F.',
      WatchlistMatchType.name => 'Phone only. Use * for any run and ? for any character.',
      WatchlistMatchType.nameContains => 'Case-insensitive, up to 18 characters.',
      WatchlistMatchType.namePrefix => 'Case-insensitive, up to 18 characters; spaces count.',
      WatchlistMatchType.namePattern => 'Whole name. # is a hex digit, ? any character, * any run.',
      WatchlistMatchType.companyId => 'The first two bytes of manufacturer data, such as 004C for Apple.',
      WatchlistMatchType.companyData => 'CCCC:HEX or CCCC:HEX/MASK. Bits set in the mask must match, such as 004C:121910/FFFF30.',
      WatchlistMatchType.wifiProbe => 'Source address of a probe or association request: 3 to 6 bytes.',
      WatchlistMatchType.wifiBeacon => 'Source address of a beacon or probe response: 3 to 6 bytes.',
      WatchlistMatchType.makerName => 'Phone only: matched against the maker name for an address. Nodes never receive it.',
    };

/// How the enabled watchlist fills the detector's lists, and whether one mesh frame carries it whole.
class WatchlistBudget {
  const WatchlistBudget({
    required this.macs,
    required this.uuids,
    required this.rules,
    required this.phoneOnly,
    required this.wireBytes,
  });

  final int macs;
  final int uuids;
  final int rules;
  final int phoneOnly;
  final int wireBytes;

  bool get overMacs => macs > detMacMax;
  bool get overUuids => uuids > detUuidMax;
  bool get overRules => rules > detExtMax;
  bool get overMeshFrame => wireBytes > detMeshListMax;
  bool get overDevice => overMacs || overUuids || overRules;

  /// One line for the import and add toasts; empty when everything fits.
  String get warning {
    final parts = <String>[
      if (overMacs) 'a device holds $detMacMax MAC and prefix rules',
      if (overUuids) 'a device holds $detUuidMax service UUIDs',
      if (overRules) 'a device holds $detExtMax name, company, Wi-Fi and 128-bit rules',
      if (overMeshFrame) 'one mesh frame carries $detMeshListMax bytes of the list, so nodes on the fleet list get the first part',
    ];
    return parts.join('; ');
  }
}

WatchlistBudget watchlistBudget(Iterable<WatchlistEntry> entries) {
  var macs = 0, uuids = 0, rules = 0, phoneOnly = 0, ext = 0;
  for (final e in entries) {
    if (!e.matchType.isNodeRule) {
      phoneOnly++;
    } else if (e.isExtWire) {
      final r = e.rule;
      if (r == null) continue;
      rules++;
      ext += 2 + r.payload.length;
    } else if (e.isServiceUuid) {
      uuids++;
    } else {
      macs++;
    }
  }
  final wire = 1 + 7 * macs.clamp(0, detMacMax) + 1 + 2 * uuids.clamp(0, detUuidMax) + (rules > 0 ? 1 + ext : 0);
  return WatchlistBudget(macs: macs, uuids: uuids, rules: rules, phoneOnly: phoneOnly, wireBytes: wire);
}
