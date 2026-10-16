import 'device_explain.dart';
import 'observation.dart';

class KinIndex {
  KinIndex({this.cap = 4000});

  final int cap;
  final _byKey = <String, (String, String, Guess)>{};

  static const _platformCompanies = {0x004C, 0x0006, 0x00E0, 0x0075};

  static String? nameStem(String name) {
    var s = name.trim().toLowerCase();
    s = s.replaceFirst(RegExp(r'[\s_\-:#(\[]*(?=[0-9a-f]*[0-9])[0-9a-f]{2,}[\])]?$'), '');
    s = s.replaceFirst(RegExp(r'[\s_\-:#]*[0-9]+$'), '').trim();
    return s.length >= 3 ? s : null;
  }

  static String? advShape(Observation o) {
    if (o.mfgRecords.any((m) => _platformCompanies.contains(m.companyId))) return null;
    final uuids = {...o.serviceUuids.map(hexOnly), ...o.serviceData.map((s) => 'sd${hexOnly(s.uuid)}')}.toList()..sort();
    final custom = uuids.any((u) {
      final h = u.startsWith('sd') ? u.substring(2) : u;
      return h.length == 32 && !h.endsWith('00001000800000805F9B34FB');
    });
    if (!custom) return null;
    final mfg = [
      for (final m in o.mfgRecords) '${m.companyId.toRadixString(16)}:${hexOnly(m.dataHex).length ~/ 2}',
    ]..sort();
    return '${mfg.join(',')}|${uuids.join(',')}|${o.appearance ?? ''}';
  }

  static List<String> keysOf(Observation o) {
    if (o.kind != RadioKind.ble) return const [];
    final stem = nameStem(o.name);
    final shape = advShape(o);
    return [if (stem != null) 'n:$stem', if (shape != null) 's:$shape'];
  }

  void learn(Observation o, Guess g) {
    if (g.confidence == Confidence.low || DeviceExplain.isGeneric(g)) return;
    for (final k in keysOf(o)) {
      final prev = _byKey[k];
      if (prev != null && prev.$1 != o.key && prev.$3.confidence.index < g.confidence.index) continue;
      _byKey.remove(k);
      _byKey[k] = (o.key, o.name, g);
    }
    while (_byKey.length > cap) {
      _byKey.remove(_byKey.keys.first);
    }
  }

  Guess? lookup(Observation o) {
    for (final k in keysOf(o)) {
      final hit = _byKey[k];
      if (hit == null || hit.$1 == o.key) continue;
      final (_, name, g) = hit;
      final conf = g.confidence == Confidence.high ? Confidence.medium : Confidence.low;
      final who = name.isNotEmpty ? '"$name"' : 'another device';
      return Guess(
        '${DeviceExplain.hedge(conf)} ${DeviceExplain.stripHedge(g.headline)}',
        k.startsWith('n:')
            ? 'It shares a name pattern with $who nearby, which was identified that way.'
            : 'It sends the same custom Bluetooth service layout as $who nearby, which was identified that way.',
        conf,
        bucket: g.bucket,
      );
    }
    return null;
  }

  void clear() => _byKey.clear();
}
