// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:oui_spy/core/ble/ble_protocol.dart';
import 'package:oui_spy/core/detector_rules.dart';
import 'package:oui_spy/core/watchlist_state.dart';

/// Record kinds in a filter edit or a node's filter list: 0x01 to 0x08 are the extension rules of
/// [detector_rules.dart]; these two carry the older MAC, prefix and 16-bit service UUID rows.
const int detRecMac = 0x10;
const int detRecUuid16 = 0x11;

class PresetRow {
  const PresetRow(this.type, this.identifier, this.description);
  final WatchlistMatchType type;
  final String identifier;
  final String description;

  bool get isWifi => type == WatchlistMatchType.wifiProbe || type == WatchlistMatchType.wifiBeacon;

  WatchlistEntry get entry => WatchlistEntry(identifier: identifier, matchType: type, description: description);
}

PresetRow _r(WatchlistMatchType t, String id, String d) => PresetRow(t, id, d);

class DetectorPreset {
  const DetectorPreset(this.id, this.key, this.name, this.about, this.rows);

  /// The byte a node's preset command carries.
  final int id;
  final String key;
  final String name;
  final String about;
  final List<PresetRow> rows;

  int get wifiRows => rows.where((r) => r.isWifi).length;
  int get bleRows => rows.length - wifiRows;
}

/// The signature sets a node can install by id. The rows match the node firmware's table row for row
/// (src/engines/detector_presets.h); a test keeps the two in step.
final List<DetectorPreset> detectorPresets = [
  DetectorPreset(0, 'axon', 'Axon', 'Axon body cameras, TASERs and in-car units', [
    _r(WatchlistMatchType.oui, '00:25:DF', 'AXON'),
    _r(WatchlistMatchType.wifiProbe, '00:25:DF', 'AXON (WiFi)'),
    _r(WatchlistMatchType.wifiBeacon, '00:25:DF', 'AXON (WiFi)'),
  ]),
  DetectorPreset(1, 'meta', 'Meta glasses', 'Ray-Ban and Oakley Meta smart glasses', [
    _r(WatchlistMatchType.oui, '7C:2A:9E', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.wifiProbe, '7C:2A:9E', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.oui, '98:59:49', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.wifiProbe, '98:59:49', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.oui, '80:AA:1C', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.wifiProbe, '80:AA:1C', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.oui, '38:47:12', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.wifiProbe, '38:47:12', 'META/RAYBAN SMARTGLASSES'),
    _r(WatchlistMatchType.companyId, '0D53', 'Meta glasses (Luxottica)'),
    _r(WatchlistMatchType.serviceUuid, 'FD5F', 'Meta glasses service'),
    _r(WatchlistMatchType.companyId, '058E', 'Meta Platforms (headsets)'),
    _r(WatchlistMatchType.companyId, '01AB', 'Meta Platforms'),
    _r(WatchlistMatchType.serviceUuid, 'FEB7', 'Meta Platforms service'),
    _r(WatchlistMatchType.serviceUuid, 'FEB8', 'Meta Platforms service'),
    _r(WatchlistMatchType.nameContains, 'Ray-Ban', 'Ray-Ban Meta glasses (BLE name)'),
    _r(WatchlistMatchType.nameContains, 'Oakley', 'Oakley Meta glasses (BLE name)'),
    _r(WatchlistMatchType.nameContains, 'Wayfarer', 'Ray-Ban Meta Wayfarer'),
  ]),
  DetectorPreset(2, 'ipro', 'i-PRO', 'i-PRO body cameras', [
    _r(WatchlistMatchType.wifiProbe, 'D4:2D:C5', 'I-PRO'),
    _r(WatchlistMatchType.oui, 'D4:2D:C5', 'I-PRO body cam'),
  ]),
  DetectorPreset(3, 'verkada', 'Verkada', 'Verkada security cameras, by Wi-Fi', [
    _r(WatchlistMatchType.wifiProbe, 'E0:A7:00', 'Verkada'),
    _r(WatchlistMatchType.wifiBeacon, 'E0:A7:00', 'Verkada'),
  ]),
  DetectorPreset(4, 'trackers', 'Trackers', 'AirTag and Find My items, SmartTag, Tile, Chipolo, Pebblebee', [
    _r(WatchlistMatchType.companyData, '004C:121910/FFFF30', 'AirTag, separated'),
    _r(WatchlistMatchType.companyData, '004C:121920/FFFF30', 'Find My accessory, separated'),
    _r(WatchlistMatchType.companyData, '004C:121930/FFFF30', 'AirPods, separated'),
    _r(WatchlistMatchType.serviceUuid, 'FD5A', 'Samsung SmartTag'),
    _r(WatchlistMatchType.serviceUuid, 'FD59', 'Samsung SmartTag, not set up'),
    _r(WatchlistMatchType.serviceUuid, 'FEED', 'Tile'),
    _r(WatchlistMatchType.serviceUuid, 'FEEC', 'Tile, not activated'),
    _r(WatchlistMatchType.serviceUuid, 'FE33', 'Chipolo'),
    _r(WatchlistMatchType.serviceUuid, 'FA25', 'Pebblebee'),
    _r(WatchlistMatchType.serviceUuid, 'FCB2', 'Tracker (DULT standard)'),
  ]),
  DetectorPreset(5, 'drones', 'Drones', 'Remote ID and DJI over Bluetooth, Teal over Wi-Fi', [
    _r(WatchlistMatchType.serviceUuid, 'FFFA', 'Remote ID broadcast (Bluetooth)'),
    _r(WatchlistMatchType.companyId, '08AA', 'DJI CID (drones, RCs, Osmo)'),
    _r(WatchlistMatchType.oui, '4C:43:F6', 'DJI OUI'),
    _r(WatchlistMatchType.oui, '88:29:85', 'DJI OUI'),
    _r(WatchlistMatchType.wifiBeacon, 'B0:30:C8', 'Teal Drones (WiFi)'),
  ]),
  DetectorPreset(6, 'vehicles', 'Vehicles', 'Teslas and Bluetooth OBD-II dongles', [
    _r(WatchlistMatchType.namePattern, 'S################C', 'Tesla vehicle (name)'),
    _r(WatchlistMatchType.serviceUuid, 'FE96', 'Tesla svc UUID'),
    _r(WatchlistMatchType.serviceUuid, 'FE97', 'Tesla svc UUID'),
    _r(WatchlistMatchType.companyId, '022B', 'Tesla CID'),
    _r(WatchlistMatchType.nameContains, 'OBDII', 'OBD-II dongle'),
    _r(WatchlistMatchType.nameContains, 'OBDBLE', 'OBD-II dongle'),
    _r(WatchlistMatchType.nameContains, 'OBDLink', 'OBDLink dongle'),
    _r(WatchlistMatchType.nameContains, 'Vgate', 'Vgate OBD dongle'),
    _r(WatchlistMatchType.nameContains, 'vLinker', 'vLinker OBD dongle'),
    _r(WatchlistMatchType.nameContains, 'VEEPEAK', 'Veepeak OBD dongle'),
  ]),
  DetectorPreset(7, 'wearables', 'Wearables', 'Snap, Even Realities, Brilliant Labs, GoPro, Insta360, PLAUD', [
    _r(WatchlistMatchType.companyId, '03C2', 'Snap Spectacles CID'),
    _r(WatchlistMatchType.serviceUuid, 'FE45', 'Snap Spectacles svc UUID'),
    _r(WatchlistMatchType.oui, '98:A4:0E', 'Snap Inc OUI'),
    _r(WatchlistMatchType.companyId, '10F9', 'Even Realities glasses CID'),
    _r(WatchlistMatchType.serviceUuid, '7A230001-5475-A6A4-654C-8431F6AD49C4', 'Brilliant Labs Frame glasses'),
    _r(WatchlistMatchType.serviceUuid, 'FEA6', 'GoPro camera'),
    _r(WatchlistMatchType.serviceUuid, 'FEA5', 'GoPro camera'),
    _r(WatchlistMatchType.companyId, '02F2', 'GoPro CID'),
    _r(WatchlistMatchType.companyId, '10D7', 'Insta360 camera CID'),
    _r(WatchlistMatchType.serviceUuid, 'FC2D', 'Insta360 camera'),
    _r(WatchlistMatchType.serviceUuid, 'FC2E', 'Insta360 camera'),
    _r(WatchlistMatchType.serviceUuid, 'FC2F', 'Insta360 camera'),
    _r(WatchlistMatchType.serviceUuid, 'FC30', 'Insta360 camera'),
    _r(WatchlistMatchType.companyId, '0FB2', 'PLAUD voice recorder CID'),
  ]),
  DetectorPreset(8, 'flipper', 'Flipper', 'Flipper Zero', [
    _r(WatchlistMatchType.oui, '80:E1:26', 'FLIPPER ZERO'),
    _r(WatchlistMatchType.wifiProbe, '80:E1:26', 'FLIPPER ZERO'),
    _r(WatchlistMatchType.oui, '80:E1:27', 'FLIPPER ZERO'),
    _r(WatchlistMatchType.wifiProbe, '80:E1:27', 'FLIPPER ZERO'),
    _r(WatchlistMatchType.oui, '0C:FA:22', 'FLIPPER ZERO'),
    _r(WatchlistMatchType.wifiProbe, '0C:FA:22', 'FLIPPER ZERO'),
    _r(WatchlistMatchType.nameContains, 'Flipper', 'Flipper Zero (BLE name)'),
    _r(WatchlistMatchType.serviceUuid, '3081', 'Flipper Zero svc UUID (black)'),
    _r(WatchlistMatchType.serviceUuid, '3082', 'Flipper Zero svc UUID (white)'),
    _r(WatchlistMatchType.serviceUuid, '3083', 'Flipper Zero (transparent)'),
    _r(WatchlistMatchType.serviceUuid, '3080', 'Flipper Zero'),
    _r(WatchlistMatchType.namePrefix, 'Flipper ', 'Flipper Zero (name)'),
    _r(WatchlistMatchType.companyId, '0E29', 'Flipper Devices CID'),
  ]),
  DetectorPreset(9, 'police', 'Police', 'Motorola Solutions, WatchGuard, Digital Ally, Utility, plate readers, ShotSpotter', [
    _r(WatchlistMatchType.companyId, '04EC', 'Motorola Solutions company'),
    _r(WatchlistMatchType.serviceUuid, 'FD8E', 'Motorola Solutions svc UUID'),
    _r(WatchlistMatchType.serviceUuid, 'FE04', 'Motorola Solutions svc UUID'),
    _r(WatchlistMatchType.companyId, '060C', 'Vuzix CID (smart glasses, HUDs)'),
    _r(WatchlistMatchType.oui, '00:04:7D', 'Motorola Solutions OUI'),
    _r(WatchlistMatchType.oui, '00:18:85', 'Motorola Solutions OUI'),
    _r(WatchlistMatchType.oui, '00:1F:92', 'Motorola Solutions OUI'),
    _r(WatchlistMatchType.oui, '4C:CC:34', 'Motorola Solutions OUI'),
    _r(WatchlistMatchType.oui, '10:74:6F', 'Motorola Solutions (radios)'),
    _r(WatchlistMatchType.oui, '9C:86:2B', 'Motorola Solutions (radios)'),
    _r(WatchlistMatchType.oui, 'B8:E2:8C', 'Motorola Solutions (radios)'),
    _r(WatchlistMatchType.wifiProbe, '00:1D:96', 'WatchGuard Video camera'),
    _r(WatchlistMatchType.wifiBeacon, '00:1D:96', 'WatchGuard Video AP (WiFi)'),
    _r(WatchlistMatchType.wifiProbe, '00:23:BD', 'Digital Ally cam (WiFi)'),
    _r(WatchlistMatchType.wifiBeacon, '00:23:BD', 'Digital Ally AP (WiFi)'),
    _r(WatchlistMatchType.wifiProbe, '00:09:BC', 'Utility / BodyWorn (WiFi)'),
    _r(WatchlistMatchType.wifiBeacon, '00:09:BC', 'Utility car router'),
    _r(WatchlistMatchType.wifiProbe, '00:16:ED', 'Utility / BodyWorn (WiFi)'),
    _r(WatchlistMatchType.wifiBeacon, '00:16:ED', 'Utility car router'),
    _r(WatchlistMatchType.wifiBeacon, '00:BF:15', 'Genetec AutoVu reader'),
    _r(WatchlistMatchType.wifiBeacon, '0C:BF:15', 'Genetec AutoVu reader'),
    _r(WatchlistMatchType.wifiBeacon, 'D4:11:D6', 'ShotSpotter sensor (WiFi)'),
    _r(WatchlistMatchType.wifiBeacon, '70:1A:D5', 'Avigilon Alta camera (WiFi)'),
  ]),
];

/// The record a filter edit carries for [e]: a MAC or prefix row, a 16-bit service UUID, or an extension rule.
/// Null for kinds that stay on the phone and for identifiers that do not parse.
Uint8List? filterRecordOf(WatchlistEntry e) {
  if (!e.matchType.isNodeRule) return null;
  final id = normalizeWatchlistId(e.identifier, e.matchType);
  if (id == null) return null;
  if (e.isExtWire) return e.rule?.record;
  if (e.matchType == WatchlistMatchType.serviceUuid) {
    final v = int.parse(id, radix: 16);
    return Uint8List.fromList([detRecUuid16, 2, v & 0xFF, v >> 8]);
  }
  final mac = [for (final p in id.split(':')) int.parse(p, radix: 16)];
  return Uint8List.fromList([detRecMac, 1 + mac.length, mac.length, ...mac]);
}

/// Splits [records] into edits of at most [BleProtocol.filterOpDataMax] bytes, never inside a record.
List<Uint8List> packFilterRecords(Iterable<Uint8List> records) {
  final out = <Uint8List>[];
  var cur = <int>[];
  for (final r in records) {
    if (cur.isNotEmpty && cur.length + r.length > BleProtocol.filterOpDataMax) {
      out.add(Uint8List.fromList(cur));
      cur = [];
    }
    cur.addAll(r);
  }
  if (cur.isNotEmpty) out.add(Uint8List.fromList(cur));
  return out;
}

/// One row of a node's filter list, as the node reported it.
class NodeFilterRow {
  const NodeFilterRow(this.kind, this.payload);
  final int kind;
  final Uint8List payload;

  Uint8List get record => Uint8List.fromList([kind, payload.length, ...payload]);

  static String _hex(Iterable<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  static String _colon(Iterable<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

  /// The watchlist form of this row; null for a kind this app does not know.
  WatchlistEntry? get entry {
    switch (kind) {
      case detRecMac:
        if (payload.isEmpty || payload.length != 1 + payload[0]) return null;
        final mac = payload.sublist(1);
        return WatchlistEntry(
            identifier: _colon(mac), matchType: mac.length == 6 ? WatchlistMatchType.fullMac : WatchlistMatchType.oui);
      case detRecUuid16:
        if (payload.length != 2) return null;
        return WatchlistEntry(identifier: _hex([payload[1], payload[0]]), matchType: WatchlistMatchType.serviceUuid);
      case detRuleNameContains:
        return WatchlistEntry(identifier: String.fromCharCodes(payload), matchType: WatchlistMatchType.nameContains);
      case detRuleNamePrefix:
        return WatchlistEntry(identifier: String.fromCharCodes(payload), matchType: WatchlistMatchType.namePrefix);
      case detRuleNamePattern:
        return WatchlistEntry(identifier: String.fromCharCodes(payload), matchType: WatchlistMatchType.namePattern);
      case detRuleCompanyId:
        if (payload.length != 2) return null;
        return WatchlistEntry(identifier: _hex([payload[1], payload[0]]), matchType: WatchlistMatchType.companyId);
      case detRuleCompanyData:
        if (payload.length < 4 || payload.length.isOdd) return null;
        final k = (payload.length - 2) ~/ 2;
        return WatchlistEntry(
            identifier: '${_hex([payload[1], payload[0]])}:${_hex(payload.sublist(2, 2 + k))}/${_hex(payload.sublist(2 + k))}',
            matchType: WatchlistMatchType.companyData);
      case detRuleUuid128:
        if (payload.length != 16) return null;
        final h = _hex(payload.reversed);
        return WatchlistEntry(
            identifier:
                '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}',
            matchType: WatchlistMatchType.serviceUuid);
      case detRuleWifiProbe:
        return WatchlistEntry(identifier: _colon(payload), matchType: WatchlistMatchType.wifiProbe);
      case detRuleWifiBeacon:
        return WatchlistEntry(identifier: _colon(payload), matchType: WatchlistMatchType.wifiBeacon);
    }
    return null;
  }
}

/// Reads a record stream, a filter edit or a node's list: [kind][len][payload] repeated. A cut or
/// overlong record ends the list; unknown kinds are skipped.
List<NodeFilterRow> decodeFilterRecords(List<int> b) {
  final out = <NodeFilterRow>[];
  var o = 0;
  while (o + 2 <= b.length) {
    final kind = b[o], len = b[o + 1];
    if (o + 2 + len > b.length) break;
    final row = NodeFilterRow(kind, Uint8List.fromList(b.sublist(o + 2, o + 2 + len)));
    if (row.entry != null) out.add(row);
    o += 2 + len;
  }
  return out;
}

/// Pages of one node's filter list as they arrive, in any order.
class NodeFilterReport {
  NodeFilterReport(this.id, this.seq, this.pages);

  final String id;
  final int seq;
  final int pages;
  final Map<int, Uint8List> _got = {};

  bool add(NodeFilterFrame f) {
    if (f.seq != seq || f.pages != pages || f.page >= pages) return false;
    _got[f.page] = f.data;
    return true;
  }

  int get received => _got.length;
  bool get complete => pages > 0 && _got.length == pages;

  List<NodeFilterRow> get rows => decodeFilterRecords([
        for (var p = 0; p < pages; p++) ...?_got[p],
      ]);
}

String filterOpName(int op) => switch (op) {
      BleProtocol.filterOpAdd => 'add',
      BleProtocol.filterOpDel => 'remove',
      BleProtocol.filterOpClear => 'clear',
      BleProtocol.filterOpPreset => 'preset',
      BleProtocol.filterOpGet => 'read',
      _ => 'edit',
    };

/// How a node answered a filter edit, such as "added 4, skipped 2" or "refused: nothing it can match".
String nodeFilterOpText(NodeFilterResult r, int op) {
  if (r.status != 0) return 'refused: ${filterOpRefusalText(r.status)}';
  final held = '${r.filterMacs + r.filterUuids + r.filterRules} rows';
  return switch (op) {
    BleProtocol.filterOpGet => 'holds $held',
    BleProtocol.filterOpClear => 'cleared ${r.changed}',
    BleProtocol.filterOpDel => 'removed ${r.changed}, holds $held',
    _ => 'added ${r.changed}${r.skipped > 0 ? ', skipped ${r.skipped}' : ''}, holds $held',
  };
}

String filterOpRefusalText(int status) => switch (status) {
      1 => 'detector not on this build',
      2 => 'detector turned off for it',
      3 => 'no room for these rows',
      4 => 'nothing it can match with its radio setting',
      5 => 'rows it could not read',
      _ => 'refused',
    };

/// "On 3 of 4 nodes; NODE2 refused (no room for these rows)". Null when no node was expected.
String? filterOpSummary(MeshFilterOp p, String Function(String id) label) {
  if (p.expected == 0) return null;
  final took = p.results.where((r) => r.status == 0).length;
  final parts = <String>[
    'On $took of ${p.expected} ${p.expected == 1 ? 'node' : 'nodes'}',
    for (final r in p.results)
      if (r.status != 0)
        '${label(r.id)} refused (${filterOpRefusalText(r.status)})'
      else if (r.skipped > 0)
        '${label(r.id)} skipped ${r.skipped} ${r.skipped == 1 ? 'row' : 'rows'}',
  ];
  final silent = p.expected - p.results.length;
  if (silent > 0) parts.add('$silent did not answer (older firmware does not)');
  return parts.join('; ');
}
