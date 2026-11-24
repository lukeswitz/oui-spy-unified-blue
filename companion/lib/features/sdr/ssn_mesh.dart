const ssnModel = 'SilverSpring-Mesh';

bool isSsn(Map<String, dynamic> f) => f['model'] == ssnModel;

String? ssnMaker(String eui) {
  final h = eui.toLowerCase();
  if (h.startsWith('000781')) return 'Itron';
  if (h.startsWith('001350')) return 'Silver Spring';
  return null;
}

String ssnShort(String eui) => eui.length > 6 ? '…${eui.substring(eui.length - 6)}' : eui;

String? ssnRole(String eui) {
  final h = eui.toLowerCase();
  if (h.length == 16 && h.substring(6, 10) == 'fffe') return 'access point';
  if (h.startsWith('0013500500')) return 'meter';
  return null;
}

String ssnNode(String eui, {bool gateway = false}) {
  final m = ssnMaker(eui);
  final role = gateway ? 'access point' : ssnRole(eui);
  final name = [?m, ?role].join(' ');
  return name.isEmpty ? 'node ${ssnShort(eui)}' : '$name ${ssnShort(eui)}';
}

class SsnRoute {
  const SsnRoute(this.maxHops, this.pathCost, this.linkCost, this.gateway, this.next);
  final int maxHops;
  final int pathCost;
  final int linkCost;
  final String gateway;
  final List<String> next;
}

List<SsnRoute> ssnRoutes(String? s) {
  if (s == null || s.isEmpty) return const [];
  final out = <SsnRoute>[];
  for (final part in s.split(';')) {
    final m = RegExp(r'hop<=(\d+) cost=(\d+)/(\d+) egress=([0-9a-f]{16})').firstMatch(part);
    if (m == null) continue;
    out.add(SsnRoute(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      m[4]!,
      [for (final n in RegExp(r'next=([0-9a-f]{16})').allMatches(part)) n[1]!],
    ));
  }
  return out;
}

class SsnIpv6 {
  const SsnIpv6(this.src, this.dst, this.srcPort, this.dstPort, this.length, this.checksumOk, this.mgmtLen);
  final String src;
  final String dst;
  final int? srcPort;
  final int? dstPort;
  final int? length;
  final bool? checksumOk;
  final int? mgmtLen;

  bool get management => dstPort == 648;
}

SsnIpv6? ssnIpv6(String? s) {
  if (s == null || s.isEmpty) return null;
  final a = RegExp(r'\[([0-9a-f:]+)\] -> \[([0-9a-f:]+)\]').firstMatch(s);
  if (a == null) return null;
  final u = RegExp(r'(\d+)->(\d+) len=(\d+) cksum=(ok|bad)').firstMatch(s);
  final g = RegExp(r'mgmt_len=(\d+)').firstMatch(s);
  return SsnIpv6(
    a[1]!,
    a[2]!,
    u == null ? null : int.parse(u[1]!),
    u == null ? null : int.parse(u[2]!),
    u == null ? null : int.parse(u[3]!),
    u == null ? null : u[4] == 'ok',
    g == null ? null : int.parse(g[1]!),
  );
}

String ssnAction(Map<String, dynamic> f) {
  final src = f['src_id'] as String?;
  final dst = f['dst_id'] as String?;
  final link = f['link'] as String? ?? '';
  final to = dst == null ? '' : ssnNode(dst);
  final ip = ssnIpv6(f['ipv6'] as String?);
  if (ip != null && ip.management) {
    return 'Sends an encrypted utility command${dst == null ? '' : ' to $to'}';
  }
  if (src != null && dst != null) {
    return switch (link) {
      'poll' => 'Checks that $to can receive',
      'poll_ack' => 'Tells $to it is ready to receive',
      'data' => 'Sends data to $to',
      'data_ack' => 'Confirms data from $to arrived',
      _ => 'Talks to $to',
    };
  }
  if (dst != null) {
    return switch (link) {
      'poll_ack' => 'Reply to $to: ready to receive',
      'data' => 'Data for $to',
      'data_ack' => 'Reply to $to: data arrived',
      _ => 'Message for $to',
    };
  }
  if (ssnRoutes(f['routes'] as String?).isNotEmpty) return 'Announces its route to the utility';
  return link == 'broadcast' ? 'Announces itself to the mesh' : 'Mesh message';
}

String ssnTitle(Map<String, dynamic> f) {
  final src = f['src_id'] as String?;
  if (src != null) return ssnNode(src);
  final dst = f['dst_id'] as String?;
  return dst != null ? 'To ${ssnNode(dst)}' : 'Smart-meter mesh';
}

List<String> ssnSpecs(Map<String, dynamic> f) {
  final out = <String>[];
  final routes = ssnRoutes(f['routes'] as String?);
  for (final r in routes.take(2)) {
    out.add('Routes via ${ssnNode(r.gateway, gateway: true)}, up to ${r.maxHops} hops');
  }
  final ip = ssnIpv6(f['ipv6'] as String?);
  if (ip != null && !ip.management && ip.dstPort != null) out.add('IPv6 port ${ip.dstPort}, ${ip.length} bytes');
  if (ip != null && ip.management && ip.mgmtLen != null) out.add('${ip.mgmtLen} bytes, encrypted');
  final ch = f['channel'];
  if (ch != null) out.add('Hop channel $ch');
  final rssi = f['link_rssi'];
  if (rssi is num) out.add('Hears its neighbor at $rssi dBm');
  return out;
}

String _full(String eui, {bool gateway = false}) {
  final m = ssnMaker(eui);
  final role = gateway ? 'access point' : ssnRole(eui);
  return [?m, ?role, eui].join(' ');
}

List<(String, String)> ssnDetailRows(Map<String, dynamic> f) {
  final rows = <(String, String)>[('What it is', ssnAction(f))];
  final src = f['src_id'] as String?;
  final dst = f['dst_id'] as String?;
  if (src != null) rows.add(('From', _full(src)));
  if (dst != null) rows.add(('To', _full(dst)));
  for (final (i, r) in ssnRoutes(f['routes'] as String?).indexed) {
    rows.add(('Route ${i + 1}',
        'Through ${_full(r.gateway, gateway: true)}, up to ${r.maxHops} hops'
            '${r.next.isEmpty ? '' : ', first hop ${r.next.map(ssnNode).join(', ')}'}'));
  }
  final ip = ssnIpv6(f['ipv6'] as String?);
  if (ip != null) {
    rows.add(('IPv6 from', ip.src));
    rows.add(('IPv6 to', ip.dst));
    if (ip.dstPort != null) {
      rows.add(('UDP', '${ip.srcPort} → ${ip.dstPort}, ${ip.length} bytes, checksum ${ip.checksumOk! ? 'ok' : 'bad'}'));
    }
    if (ip.management) rows.add(('Command', 'Encrypted management message${ip.mgmtLen == null ? '' : ', ${ip.mgmtLen} bytes'}'));
  }
  final ch = f['channel'];
  if (ch != null) rows.add(('Hop channel', '$ch'));
  final rssi = f['rssi'];
  if (rssi is num) rows.add(('Signal here', '$rssi dB'));
  final link = f['link_rssi'];
  if (link is num) rows.add(('Signal it hears from its neighbor', '$link dBm'));
  final freq = f['frequency'];
  if (freq is num) rows.add(('Frequency', '${(freq / 1e6).toStringAsFixed(3)} MHz'));
  rows.add(('Readings', 'Encrypted (AES-CCM), not readable from the air'));
  final data = f['data'];
  if (data is String && data.isNotEmpty) rows.add(('Frame, descrambled (hex)', data));
  final tlvs = f['tlvs'];
  if (tlvs is String && tlvs.isNotEmpty) rows.add(('Records in the frame', tlvs));
  final seed = f['seed'];
  if (seed != null) rows.add(('Scrambler seed (hex)', '$seed'));
  final len = f['len'];
  if (len != null) rows.add(('Frame length', '$len bytes, CRC-32 checked'));
  return rows;
}

class SsnMeshSummary {
  const SsnMeshSummary(this.itron, this.silverSpring, this.other, this.gateways, this.links);
  final int itron;
  final int silverSpring;
  final int other;
  final Set<String> gateways;
  final int links;

  int get radios => itron + silverSpring + other;

  String get text {
    final parts = <String>[
      if (itron > 0) '$itron Itron',
      if (silverSpring > 0) '$silverSpring Silver Spring',
      if (other > 0) '$other other',
    ];
    final g = gateways.isEmpty ? '' : ', ${gateways.length} gateway${gateways.length == 1 ? '' : 's'}';
    return 'Smart-meter mesh: $radios radio${radios == 1 ? '' : 's'} (${parts.join(', ')}), '
        '$links link${links == 1 ? '' : 's'}$g';
  }
}

SsnMeshSummary? ssnSummary(Iterable<Map<String, dynamic>> frames) {
  final nodes = <String>{};
  final gateways = <String>{};
  final links = <String>{};
  for (final f in frames) {
    if (!isSsn(f)) continue;
    final src = f['src_id'] as String?;
    final dst = f['dst_id'] as String?;
    if (src != null) nodes.add(src);
    if (dst != null) nodes.add(dst);
    if (src != null && dst != null) links.add(([src, dst]..sort()).join('-'));
    for (final r in ssnRoutes(f['routes'] as String?)) {
      gateways.add(r.gateway);
    }
  }
  if (nodes.isEmpty) return null;
  var itron = 0, ss = 0, other = 0;
  for (final n in nodes) {
    switch (ssnMaker(n)) {
      case 'Itron':
        itron++;
      case 'Silver Spring':
        ss++;
      default:
        other++;
    }
  }
  return SsnMeshSummary(itron, ss, other, gateways, links.length);
}
