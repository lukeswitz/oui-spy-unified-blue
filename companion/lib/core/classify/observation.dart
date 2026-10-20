enum RadioKind { wifi, ble }

class MfgRecord {
  final int companyId;
  final String dataHex;
  const MfgRecord(this.companyId, this.dataHex);
}

class ServiceDataRecord {
  final String uuid;
  final String dataHex;
  const ServiceDataRecord(this.uuid, this.dataHex);
}

class GpsSample {
  final int atMs;
  final double lat;
  final double lon;
  final int rssi;
  const GpsSample(this.atMs, this.lat, this.lon, [this.rssi = 0]);
}

class Observation {
  final String key;
  final RadioKind kind;
  final String mac;
  final String name;
  final int rssi;
  final int rssiMin;
  final int rssiMax;
  final int firstSeenMs;
  final int lastSeenMs;
  final bool hiddenSsid;
  final List<String> serviceUuids;
  final List<MfgRecord> mfgRecords;
  final List<ServiceDataRecord> serviceData;
  final List<String> vendorIeOuis;
  final int? appearance;
  final List<GpsSample> gpsTrail;
  final int channel;
  final int? authMode;
  final bool isAp;
  final String? detectorMethod;
  final String? detectorDesc;
  final String? detectorNode;

  const Observation({
    required this.key,
    required this.kind,
    required this.mac,
    this.name = '',
    this.rssi = -100,
    int? rssiMin,
    int? rssiMax,
    this.firstSeenMs = 0,
    this.lastSeenMs = 0,
    this.hiddenSsid = false,
    this.serviceUuids = const [],
    this.mfgRecords = const [],
    this.serviceData = const [],
    this.vendorIeOuis = const [],
    this.appearance,
    this.gpsTrail = const [],
    this.channel = 0,
    this.authMode,
    this.isAp = false,
    this.detectorMethod,
    this.detectorDesc,
    this.detectorNode,
  }) : rssiMin = rssiMin ?? rssi,
       rssiMax = rssiMax ?? rssi;

  String get oui => MacUtil.prefixBytes(mac);
  bool get randomized => MacUtil.isRandomized(mac);

  Observation withTrail(List<GpsSample> trail) => Observation(
    key: key,
    kind: kind,
    mac: mac,
    name: name,
    rssi: rssi,
    rssiMin: rssiMin,
    rssiMax: rssiMax,
    firstSeenMs: firstSeenMs,
    lastSeenMs: lastSeenMs,
    hiddenSsid: hiddenSsid,
    serviceUuids: serviceUuids,
    mfgRecords: mfgRecords,
    serviceData: serviceData,
    vendorIeOuis: vendorIeOuis,
    appearance: appearance,
    gpsTrail: trail,
    channel: channel,
    authMode: authMode,
    isAp: isAp,
    detectorMethod: detectorMethod,
    detectorDesc: detectorDesc,
    detectorNode: detectorNode,
  );

  Observation merge(Observation next) => Observation(
    key: key,
    kind: kind,
    mac: mac,
    name: next.name.isNotEmpty ? next.name : name,
    rssi: next.rssi,
    rssiMin: next.rssi < rssiMin ? next.rssi : rssiMin,
    rssiMax: next.rssi > rssiMax ? next.rssi : rssiMax,
    firstSeenMs: firstSeenMs,
    lastSeenMs: next.lastSeenMs,
    hiddenSsid: next.hiddenSsid,
    serviceUuids: next.serviceUuids.isNotEmpty ? next.serviceUuids : serviceUuids,
    mfgRecords: next.mfgRecords.isNotEmpty ? next.mfgRecords : mfgRecords,
    serviceData: next.serviceData.isNotEmpty ? next.serviceData : serviceData,
    vendorIeOuis: next.vendorIeOuis.isNotEmpty ? next.vendorIeOuis : vendorIeOuis,
    appearance: next.appearance ?? appearance,
    gpsTrail: next.gpsTrail.isEmpty ? gpsTrail : [...gpsTrail, ...next.gpsTrail],
    channel: next.channel != 0 ? next.channel : channel,
    authMode: next.authMode ?? authMode,
    isAp: isAp || next.isAp,
    detectorMethod: next.detectorMethod ?? detectorMethod,
    detectorDesc: next.detectorMethod != null ? next.detectorDesc : detectorDesc,
    detectorNode: next.detectorMethod != null ? next.detectorNode : detectorNode,
  );
}

String hexOnly(String raw) {
  final b = StringBuffer();
  for (final c in raw.codeUnits) {
    if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
      b.writeCharCode(c >= 97 ? c - 32 : c);
    }
  }
  return b.toString();
}

class MacUtil {
  static String normalize(String raw) {
    final hex = hexOnly(raw);
    if (hex.length < 2) return raw.toUpperCase();
    final parts = <String>[];
    for (var i = 0; i < hex.length; i += 2) {
      parts.add(hex.substring(i, i + 2 > hex.length ? hex.length : i + 2));
    }
    return parts.join(':');
  }

  static String prefixBytes(String mac, [int n = 3]) {
    final parts = normalize(mac).split(':');
    return parts.take(n).join(':');
  }

  static int? _first(String mac) {
    final hex = hexOnly(mac);
    if (hex.length < 2) return null;
    return int.tryParse(hex.substring(0, 2), radix: 16);
  }

  static bool isRandomized(String mac) {
    final f = _first(mac);
    return f != null && (f & 0x02) != 0 && (f & 0x01) == 0;
  }

  static String? wifiOui24Universal(String mac) {
    final hex = hexOnly(mac);
    if (hex.length < 6) return null;
    final f = int.tryParse(hex.substring(0, 2), radix: 16);
    if (f == null || (f & 0x02) == 0 || (f & 0x01) != 0) return null;
    return (f & 0xFD).toRadixString(16).padLeft(2, '0').toUpperCase() + hex.substring(2, 6);
  }

  static bool matchesPrefix(String mac, String prefix) {
    final p = hexOnly(prefix);
    return p.isNotEmpty && hexOnly(mac).startsWith(p);
  }
}

Set<String> uuidAliases(String raw) {
  final hex = hexOnly(raw);
  final out = <String>{raw.toUpperCase(), hex};
  const tail = '00001000800000805F9B34FB';
  String? short;
  if (hex.length == 4) {
    short = hex;
  } else if (hex.length == 32 && hex.startsWith('0000') && hex.endsWith(tail)) {
    short = hex.substring(4, 8);
  }
  if (short != null) {
    out
      ..add(short)
      ..add('0x$short')
      ..add('0000$short-0000-1000-8000-00805F9B34FB')
      ..add('0000$short$tail');
  }
  return out;
}

int? uuid16(String uuid) {
  final hex = hexOnly(uuid);
  if (hex.length == 4) return int.tryParse(hex, radix: 16);
  if (hex.length == 32 && hex.startsWith('0000') && hex.endsWith('00001000800000805F9B34FB')) {
    return int.tryParse(hex.substring(4, 8), radix: 16);
  }
  return null;
}
