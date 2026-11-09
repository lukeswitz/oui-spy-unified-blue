import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/adv_decoder.dart';
import 'package:oui_spy/core/classify/device_explain.dart';
import 'package:oui_spy/core/classify/fast_pair_models.dart';
import 'package:oui_spy/core/classify/observation.dart';

Map<String, String> _byLabel(List<AdvField> f) => {for (final x in f) x.label: x.value};

Observation _fp(String hex) => Observation(
      key: 'BLE:02:00:00:00:00:01',
      kind: RadioKind.ble,
      mac: '02:00:00:00:00:01',
      rssi: -50,
      serviceData: [ServiceDataRecord('FE2C', hex)],
    );

void main() {
  setUpAll(() => FastPairModels.load(File(FastPairModels.asset).readAsStringSync()));

  test('loads every row of the WhisperPair list, quoted makers included', () {
    expect(FastPairModels.models.length, 2878);
    expect(FastPairModels.models[0xF00000]!.name, 'Bose QuietComfort 35 II');
    expect(FastPairModels.models[0x92BBBD]!.maker, 'Google');
    expect(FastPairModels.models[0x6AB3CC]!.maker, 'Harman International Industries, Inc.');
    expect(FastPairModels.models[0x6AB3CC]!.tracking, isTrue);
    expect(FastPairModels.models[4309209]!.name, 'Quick Start default');
  });

  test('decoder names a listed model with maker and tracking', () {
    final m = _byLabel(AdvPayloadDecoder.decodeService(const ServiceDataRecord('FE2C', '6AB3CC')));
    expect(m['Model'], 'JBL Endurance Pace');
    expect(m['Maker'], 'Harman International Industries, Inc.');
    expect(m['Model ID'], '0x6AB3CC');
    expect(m['Tracking'], contains('location tracking'));
  });

  test('decoder keeps the bare ID for a model not in the list', () {
    expect(FastPairModels.models.containsKey(1), isFalse);
    final m = _byLabel(AdvPayloadDecoder.decodeService(const ServiceDataRecord('FE2C', '000001')));
    expect(m['Model ID'], '0x000001 (not in the local name list)');
    expect(m.containsKey('Model'), isFalse);
  });

  test('a listed model names the device and sets its kind', () {
    final buds = DeviceExplain.guess(_fp('92BBBD'), const []);
    expect(buds.headline, 'Most likely Pixel Buds');
    expect(buds.bucket, 'audio-personal');
    expect(buds.because, contains('listed as Pixel Buds by Google'));
    final tag = DeviceExplain.guess(_fp('D00CCF'), const []);
    expect(tag.headline, 'Most likely HPrime Tag');
    expect(tag.bucket, 'tag');
    final unknown = DeviceExplain.guess(_fp('000001'), const []);
    expect(unknown.headline, 'Most likely a Fast Pair accessory (often earbuds or a speaker)');
  });

  test('the list is bundled as an app asset', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final csv = await rootBundle.loadString(FastPairModels.asset);
    expect(csv, startsWith('Model ID,Device name,Manufacturer'));
  });

  test('account-key broadcasts carry no model and stay unnamed', () {
    final m = _byLabel(AdvPayloadDecoder.decodeService(const ServiceDataRecord('FE2C', '01020304050607')));
    expect(m.containsKey('Model'), isFalse);
    expect(m['Google Fast Pair'], contains('Already paired'));
  });
}
