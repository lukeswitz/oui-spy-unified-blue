import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/trusted_networks.dart';

const _day = TrustedNetworks.learnMs;
const _home = (1.0, 1.0);

TrustedSighting _ap(String bssid, {String vendor = 'Netgear', int? auth = 3, (double, double)? at = _home}) =>
    TrustedSighting(bssid, vendor, auth, at?.$1, at?.$2);

Future<TrustedNetworks> _trusted() async {
  final t = TrustedNetworks(persist: false);
  await t.trust('MyNetwork', [_ap('AA:BB:CC:00:00:01')], 0);
  return t;
}

void main() {
  test('a new access point from the same maker and security is learned quietly', () async {
    final t = await _trusted();
    expect(t.check('MyNetwork', _ap('AA:BB:CC:00:00:02'), _day + 1), isNull);
    expect(t.networks.single.aps.length, 2);
  });

  test('an open lookalike from another maker warns', () async {
    final t = await _trusted();
    final r = t.check('MyNetwork', _ap('02:00:00:00:00:09', vendor: '', auth: 0), _day + 1);
    expect(r, [TrustedNetworks.weakSecurity, TrustedNetworks.unknownMaker]);
    expect(t.networks.single.aps.length, 1);
  });

  test('the same warning is not repeated within the cooldown', () async {
    final t = await _trusted();
    expect(t.check('MyNetwork', _ap('02:00:00:00:00:09', vendor: ''), _day + 1), isNotNull);
    expect(t.check('MyNetwork', _ap('02:00:00:00:00:09', vendor: ''), _day + 2), isNull);
  });

  test('far from usual places warns only after learning', () async {
    final t = await _trusted();
    const far = (1.1, 1.0);
    expect(t.check('MyNetwork', _ap('AA:BB:CC:00:00:01', at: far), 1000), isNull);
    final t2 = await _trusted();
    expect(t2.check('MyNetwork', _ap('AA:BB:CC:00:00:01', at: far), _day + 1), [TrustedNetworks.awayFromUsual]);
  });

  test('untrusted names and a network with no history are never flagged', () async {
    final t = await _trusted();
    expect(t.check('Other', _ap('02:00:00:00:00:09', vendor: '', auth: 0), _day + 1), isNull);
    await t.trust('NewNet', const [], 0);
    expect(t.check('NewNet', _ap('02:00:00:00:00:07', vendor: '', auth: 0), _day + 1), isNull);
    expect(t.networks.firstWhere((n) => n.ssid == 'NewNet').aps.length, 1);
  });

  test('round-trips through JSON', () async {
    final t = await _trusted();
    final n = TrustedNetwork.fromJson(t.networks.single.toJson());
    expect(n.ssid, 'MyNetwork');
    expect(n.aps.single.vendor, 'Netgear');
    expect(n.places.single, _home);
  });
}
