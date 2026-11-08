import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/smarttag.dart';

const _paperFrame = '156bfa00c84062b28f00e260c3000000ad018b47';

String _withState(int state) => '1${state.toRadixString(16)}${_paperFrame.substring(2)}';

Observation _tag(String mac, String hex, int at, List<GpsSample> trail) => Observation(
      key: 'BLE:$mac',
      kind: RadioKind.ble,
      mac: mac,
      rssi: -50,
      firstSeenMs: at,
      lastSeenMs: at,
      serviceData: [ServiceDataRecord('FD5A', hex)],
      gpsTrail: trail,
    );

void main() {
  test('parses the published SmartTag frame', () {
    final t = SmartTagAdv.of(_tag('02:00:00:00:00:01', _paperFrame, 0, const []))!;
    expect(t.state, 5);
    expect(t.separated, isFalse);
    expect(t.privacyId, 'C84062B28F00E260');
    expect(t.uwb, isFalse);
  });

  test('states 1 to 3 are away from the owner', () {
    for (final s in [1, 2, 3]) {
      expect(SmartTagAdv.parse(hexToBytes(_withState(s))!)!.separated, isTrue);
    }
    for (final s in [4, 5, 6]) {
      expect(SmartTagAdv.parse(hexToBytes(_withState(s))!)!.separated, isFalse);
    }
    expect(SmartTagAdv.parse(hexToBytes(_withState(0))!), isNull);
    expect(SmartTagAdv.parse(hexToBytes('25${_paperFrame.substring(2)}')!), isNull);
    expect(SmartTagAdv.parse(hexToBytes('1502')!), isNull);
  });

  test('decoder names the state and privacy ID', () {
    final fields = AdvPayloadDecoder.decodeService(ServiceDataRecord('FD5A', _withState(3)));
    expect(fields.map((f) => f.label), ['SmartTag', 'SmartTag privacy ID', 'SmartTag UWB']);
    expect(fields.first.value, 'lost for over a day, away from its owner');
  });

  test('a separated tag keeps its trail when its address changes', () {
    final reg = DeviceRegistry();
    const a = [GpsSample(1000, 1.0, 1.0, -50), GpsSample(2000, 1.001, 1.0, -50)];
    reg.ingest(_tag('02:00:00:00:00:01', _withState(3), 2000, a));
    reg.ingest(_tag('02:00:00:00:00:02', _withState(3), 3000, const [GpsSample(3000, 1.002, 1.0, -50)]));
    final b = reg.devices.firstWhere((d) => d.obs.mac == '02:00:00:00:00:02');
    expect(b.obs.gpsTrail.length, 3);
    expect(b.obs.gpsTrail.first.atMs, 1000);
  });

  test('a tag with its owner is not linked across addresses', () {
    final reg = DeviceRegistry();
    const a = [GpsSample(1000, 1.0, 1.0, -50), GpsSample(2000, 1.001, 1.0, -50)];
    reg.ingest(_tag('02:00:00:00:00:01', _withState(5), 2000, a));
    reg.ingest(_tag('02:00:00:00:00:02', _withState(5), 3000, const [GpsSample(3000, 1.002, 1.0, -50)]));
    final b = reg.devices.firstWhere((d) => d.obs.mac == '02:00:00:00:00:02');
    expect(b.obs.gpsTrail.length, 1);
  });
}
