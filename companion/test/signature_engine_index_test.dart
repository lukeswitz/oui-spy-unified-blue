import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';

const _ouiOrName = Signature(id: 'oui-or-name', name: 'x', kind: SignatureClass.other, rules: [
  MatchRule(RuleKind.oui, text: 'AA:BB:CC'),
  MatchRule(RuleKind.nameContains, text: 'Speaker'),
]);
const _glob = Signature(id: 'glob', name: 'x', kind: SignatureClass.other, rules: [
  MatchRule(RuleKind.nameGlob, text: 'LVS-*'),
]);
const _midGlob = Signature(id: 'mid', name: 'x', kind: SignatureClass.other, rules: [
  MatchRule(RuleKind.nameGlob, text: '*_cam?'),
]);
const _hidden = Signature(id: 'hidden', name: 'x', kind: SignatureClass.other, rules: [
  MatchRule(RuleKind.hiddenSsid, radio: RadioKind.wifi),
]);

List<String> _ids(SignatureEngine e, {String mac = '02:00:00:00:00:01', String name = '', bool hidden = false}) =>
    [
      for (final s in e.match(Observation(
          key: 'k', kind: hidden ? RadioKind.wifi : RadioKind.ble, mac: mac, name: name, hiddenSsid: hidden)))
        s.id
    ];

void main() {
  final engine = SignatureEngine(const [_ouiOrName, _glob, _midGlob, _hidden]);

  test('an unnamed device still matches through the OUI index', () {
    expect(_ids(engine, mac: 'AA:BB:CC:00:00:01'), ['oui-or-name']);
  });

  test('name rules match named devices and only those', () {
    expect(_ids(engine, name: 'Living Room SPEAKER'), ['oui-or-name']);
    expect(_ids(engine), isEmpty);
  });

  test('glob matching is unchanged by the prefix check', () {
    expect(_ids(engine, name: 'LVS-1'), ['glob']);
    expect(_ids(engine, name: 'lvs-2'), ['glob']);
    expect(_ids(engine, name: 'xLVS-3'), isEmpty);
    expect(_ids(engine, name: 'LVS-\nx'), isEmpty);
    expect(_ids(engine, name: 'door_CAM1'), ['mid']);
  });

  test('a rule that needs no name still runs on unnamed devices', () {
    expect(_ids(engine, hidden: true), ['hidden']);
  });
}
