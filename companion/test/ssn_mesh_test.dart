import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/features/sdr/sdr433_classify.dart';
import 'package:oui_spy/features/sdr/ssn_mesh.dart';

const _a = '000781000000aaaa';
const _b = '000781000000bbbb';
const _c = '001350fffe00cccc';
const _gw = '001350fffe00eeee';

Map<String, dynamic> _f(Map<String, dynamic> extra) => {'kind': 'rtl433', 'model': ssnModel, 'channel': 34, ...extra};

void main() {
  test('maker and role come from the EUI-64', () {
    expect(ssnNode(_a), 'Itron …00aaaa');
    expect(ssnNode(_c), 'Silver Spring access point …00cccc');
    expect(ssnNode('0013500500000001'), 'Silver Spring meter …000001');
    expect(ssnNode(_a, gateway: true), 'Itron access point …00aaaa');
    expect(ssnNode('0011220000000001'), 'node …000001');
  });

  test('poll between two meters reads as a sentence', () {
    final f = _f({'id': _a, 'src_id': _a, 'dst_id': _b, 'link': 'poll'});
    expect(ssnTitle(f), 'Itron …00aaaa');
    expect(ssnAction(f), 'Checks that Itron …00bbbb can receive');
    expect(ssnSpecs(f), contains('Hop channel 34'));
  });

  test('an ack with only a destination names the receiver, not a sender', () {
    final f = _f({'id': _b, 'dst_id': _b, 'link': 'data_ack'});
    expect(ssnTitle(f), 'To Itron …00bbbb');
    expect(ssnAction(f), 'Reply to Itron …00bbbb: data arrived');
  });

  test('routes name the gateway and hop limit', () {
    final f = _f({
      'id': _c,
      'src_id': _c,
      'routes': 'hop<=5 cost=120/40 egress=$_gw next=$_a; hop<=3 cost=60/20 egress=$_gw',
      'data': '0200',
      'tlvs': 'D1/2 :ok',
      'seed': '2f',
      'len': 2,
      'cli_tx_pri': 2,
      'fet': 100,
    });
    final r = ssnRoutes(f['routes'] as String);
    expect(r.length, 2);
    expect(r.first.maxHops, 5);
    expect(r.first.next, [_a]);
    expect(ssnSpecs(f).first, 'Routes via Silver Spring access point …00eeee, up to 5 hops');
    expect(ssnAction(f), 'Announces its route to the utility');
    final rows = ssnDetailRows(f);
    expect(rows.map((e) => e.$1), containsAll(['What it is', 'From', 'Route 1', 'Route 2', 'Hop channel', 'Readings']));
    expect(rows.map((e) => e.$1),
        containsAll(['Frame, descrambled (hex)', 'Records in the frame', 'Scrambler seed (hex)', 'Frame length']));
    expect(rows.map((e) => e.$1), isNot(anyOf(contains('Send priority'), contains('Hop timing'), contains('Model'))));
  });

  test('port 648 is an encrypted utility command', () {
    final f = _f({
      'id': _a,
      'src_id': _a,
      'dst_id': _b,
      'link': 'data',
      'ipv6': '[2001:0db8:0000:0000:0000:0000:0000:0001] -> [2001:0db8:0000:0000:0000:0000:0000:0002] 5000->648 len=60 cksum=ok mgmt_len=20',
    });
    final ip = ssnIpv6(f['ipv6'] as String)!;
    expect(ip.dstPort, 648);
    expect(ip.checksumOk, isTrue);
    expect(ip.mgmtLen, 20);
    expect(ssnAction(f), 'Sends an encrypted utility command to Itron …00bbbb');
    expect(ssnSpecs(f), contains('20 bytes, encrypted'));
  });

  test('summary counts radios by maker, links and gateways', () {
    final s = ssnSummary([
      _f({'src_id': _a, 'dst_id': _b, 'link': 'poll'}),
      _f({'src_id': _b, 'dst_id': _a, 'link': 'poll_ack'}),
      _f({'src_id': _c, 'routes': 'hop<=4 cost=1/1 egress=$_gw'}),
      {'kind': 'rtl433', 'model': 'Acurite-Tower'},
    ])!;
    expect(s.itron, 2);
    expect(s.silverSpring, 1);
    expect(s.links, 1);
    expect(s.gateways, {_gw});
    expect(s.text, 'Smart-meter mesh: 3 radios (2 Itron, 1 Silver Spring), 1 link, 1 gateway');
    expect(ssnSummary([{'model': 'Acurite-Tower'}]), isNull);
  });

  test('detail labels are words, and the model has a plain description', () {
    expect(sdrFieldLabel('link_rssi'), 'Signal it reports from its neighbor');
    expect(sdrFieldLabel('seed'), 'Scrambler seed');
    expect(describeModel(ssnModel, Sdr433Category.meter), startsWith('Smart-meter mesh radio'));
  });
}
