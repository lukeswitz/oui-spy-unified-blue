// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/vendor_class.dart';

class BtSigRegistry {
  BtSigRegistry._();

  static const companyAsset = 'assets/bt_sig/company_identifiers.yaml';
  static const memberAsset = 'assets/bt_sig/member_uuids.yaml';

  static final companies = <int, String>{};
  static final memberUuids = <int, String>{};

  static final _entry = RegExp(r'^\s*-?\s*(value|uuid):\s*0x([0-9A-Fa-f]{1,4})\s*$');
  static final _name = RegExp(r'''^\s*name:\s*['"]?(.*?)['"]?\s*$''');

  static void load(String companyYaml, String memberYaml) {
    _parse(companyYaml, companies);
    _parse(memberYaml, memberUuids);
  }

  static void _parse(String yaml, Map<int, String> into) {
    int? id;
    for (final line in yaml.split('\n')) {
      final e = _entry.firstMatch(line);
      if (e != null) {
        id = int.parse(e.group(2)!, radix: 16);
        continue;
      }
      final n = _name.firstMatch(line);
      if (n != null && id != null) {
        into[id] = n.group(1)!.replaceAll("''", "'");
        id = null;
      }
    }
  }

  static List<RoleHint> hints(Observation o) {
    final out = <RoleHint>[];
    for (final m in o.mfgRecords) {
      final name = companies[m.companyId];
      if (name != null) out.add(_hint(name, 'Its Bluetooth data is tagged as made by $name.'));
    }
    for (final u in {...o.serviceUuids, ...o.serviceData.map((s) => s.uuid)}) {
      final id = uuid16(u);
      final name = id == null ? null : memberUuids[id];
      if (name != null) out.add(_hint(name, 'It uses a Bluetooth service that belongs to $name.'));
    }
    return out;
  }

  static RoleHint _hint(String company, String why) {
    final r = VendorClass.ruleFor(company);
    return r == null
        ? RoleHint('company', 'a $company device', why, 1)
        : RoleHint(r.bucket, r.label, why, r.weight);
  }
}
