// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/core/ota/ota_signature.dart';
import 'package:oui_spy/core/update/release_manifest.dart';
import 'package:oui_spy/core/update/update_service.dart';
import 'package:pointycastle/export.dart';

const _pyKey =
    '04add76bbb6e54fb99c680f803272d5fa4c4dc246967beebb0b4e623fc5b56f6814ee7c3b26732d64030288ad935d0f1d917ee2ddaefcb750229e3e4ddc337743d';
const _pyManifest =
    '7b0a202022666f726d6174223a20312c0a202022617070223a20226f75692d737079222c0a202022746167223a202276392e392e39222c0a20202276657273696f6e223a2022392e392e39222c0a2020226275696c64223a20332c0a20202266696c6573223a205b0a202020207b0a202020202020226e616d65223a20226f75692d7370792d76392e392e392e61706b222c0a2020202020202273697a65223a2031372c0a20202020202022736861323536223a202239303633663433653130356263633963643738333665663734373739373063626666333839653639616132323139353463653535663836313661363135626630220a202020207d0a20205d0a7d0a';
const _pySig =
    'dbafa44d19bb3898129a050f2765eee1704ae1d5a19df932454d1394accd9564b1192ac4f53a6f5d1c1f3cdfb5289bda0497a6fa4d75d4040d39cbd37e63c900';

Uint8List _hex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

Uint8List _fixed32(BigInt v) {
  final out = Uint8List(32);
  for (var i = 31; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

class _TestKey {
  _TestKey() {
    final seed = Random.secure();
    final rng = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256)))));
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(ECCurve_secp256r1()), rng));
    final pair = gen.generateKeyPair();
    _private = pair.privateKey;
    publicKey = pair.publicKey.Q!.getEncoded(false);
  }

  late final ECPrivateKey _private;
  late final Uint8List publicKey;

  Uint8List sign(Uint8List message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_private));
    final sig = signer.generateSignature(message) as ECSignature;
    return Uint8List.fromList([..._fixed32(sig.r), ..._fixed32(sig.s)]);
  }

  Uint8List signManifest(Uint8List manifest) =>
      sign(Uint8List.fromList([...ReleaseManifest.signatureContext, ...manifest]));
}

Uint8List _manifestBytes({
  String tag = 'v9.9.9',
  String version = '9.9.9',
  int build = 3,
  String app = 'oui-spy',
  int format = 1,
  List<Map<String, Object?>>? files,
}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'format': format,
      'app': app,
      'tag': tag,
      'version': version,
      'build': build,
      'files': files ?? [_entry('oui-spy-$tag.apk', _apk)],
    })));

final Uint8List _apk = Uint8List.fromList(utf8.encode('pretend apk bytes'));

Map<String, Object?> _entry(String name, Uint8List bytes, {int? size, String? sha}) =>
    {'name': name, 'size': size ?? bytes.length, 'sha256': sha ?? sha256.convert(bytes).toString()};

class _FakeGithub implements HttpClientAdapter {
  final Map<String, Uint8List> bodies = {};
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final url = options.uri.toString();
    requested.add(url);
    final body = bodies[url];
    if (body == null) return ResponseBody.fromString('missing', 404);
    return ResponseBody.fromBytes(body, 200, headers: {
      Headers.contentTypeHeader: [url.contains('api.github.com') ? Headers.jsonContentType : 'application/octet-stream'],
      Headers.contentLengthHeader: ['${body.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _prefix = 'https://github.com/${OtaService.githubOwner}/${OtaService.githubRepo}/releases/download/';
const _latest = 'https://api.github.com/repos/${OtaService.githubOwner}/${OtaService.githubRepo}/releases/latest';

void _publish(_FakeGithub gh, {
  required Uint8List manifest,
  required Uint8List signature,
  String tag = 'v9.9.9',
  Uint8List? apk,
  String? apkUrl,
  bool withSig = true,
}) {
  final assets = <Map<String, String>>[
    {'name': 'release.json', 'browser_download_url': '$_prefix$tag/release.json'},
    if (withSig) {'name': 'release.json.sig', 'browser_download_url': '$_prefix$tag/release.json.sig'},
    {'name': 'oui-spy-$tag.apk', 'browser_download_url': apkUrl ?? '$_prefix$tag/oui-spy-$tag.apk'},
  ];
  gh.bodies[_latest] = Uint8List.fromList(utf8.encode(jsonEncode({'tag_name': tag, 'assets': assets})));
  gh.bodies['$_prefix$tag/release.json'] = manifest;
  gh.bodies['$_prefix$tag/release.json.sig'] = signature;
  gh.bodies['$_prefix$tag/oui-spy-$tag.apk'] = apk ?? _apk;
}

void main() {
  const current = AppVersion([0, 7, 0, 1]);

  group('signature', () {
    test('accepts release.json signed by sign_ota.py', () {
      final m = ReleaseManifest.parseVerified(_hex(_pyManifest), _hex(_pySig), key: _hex(_pyKey));
      expect(m.tag, 'v9.9.9');
      expect(m.version.parts, [9, 9, 9, 3]);
      expect(m.files.single.name, 'oui-spy-v9.9.9.apk');
      expect(m.files.single.size, 17);
    });

    test('refuses a changed manifest', () {
      final bad = _hex(_pyManifest)..[20] ^= 1;
      expect(() => ReleaseManifest.parseVerified(bad, _hex(_pySig), key: _hex(_pyKey)),
          throwsA(isA<ReleaseRefused>()));
    });

    test('refuses another key', () {
      final other = _TestKey();
      expect(() => ReleaseManifest.parseVerified(_hex(_pyManifest), _hex(_pySig), key: other.publicKey),
          throwsA(isA<ReleaseRefused>()));
    });

    test('refuses the embedded release key for a throwaway-signed manifest', () {
      final k = _TestKey();
      final m = _manifestBytes();
      expect(() => ReleaseManifest.parseVerified(m, k.signManifest(m)), throwsA(isA<ReleaseRefused>()));
      expect(ReleaseManifest.signatureValid(m, k.signManifest(m), key: k.publicKey), isTrue);
    });

    test('refuses a short or empty signature', () {
      expect(ReleaseManifest.signatureValid(_hex(_pyManifest), Uint8List(0), key: _hex(_pyKey)), isFalse);
      expect(ReleaseManifest.signatureValid(_hex(_pyManifest), _hex(_pySig).sublist(1), key: _hex(_pyKey)), isFalse);
    });

    test('a firmware signature does not verify as a manifest signature', () {
      final k = _TestKey();
      final m = _manifestBytes();
      expect(OtaSignature.verifyDetached(m, k.sign(m), key: k.publicKey), isTrue);
      expect(ReleaseManifest.signatureValid(m, k.sign(m), key: k.publicKey), isFalse);
    });
  });

  group('manifest parse', () {
    test('reads a good manifest', () {
      final m = ReleaseManifest.parse(_manifestBytes());
      expect(m.version.toString(), '9.9.9+3');
    });

    void refuses(String why, Uint8List bytes) =>
        test('refuses $why', () => expect(() => ReleaseManifest.parse(bytes), throwsA(isA<ReleaseRefused>())));

    refuses('wrong format', _manifestBytes(format: 2));
    refuses('wrong app', _manifestBytes(app: 'other'));
    refuses('bad version', _manifestBytes(version: '1.2'));
    refuses('negative build', _manifestBytes(build: -1));
    refuses('empty files', _manifestBytes(files: []));
    refuses('bad sha256', _manifestBytes(files: [_entry('a.apk', _apk, sha: 'XYZ')]));
    refuses('zero size', _manifestBytes(files: [_entry('a.apk', _apk, size: 0)]));
    refuses('path in name', _manifestBytes(files: [_entry('../a.apk', _apk)]));
    refuses('duplicate names', _manifestBytes(files: [_entry('a.apk', _apk), _entry('a.apk', _apk)]));
    refuses('listing release.json', _manifestBytes(files: [_entry('release.json', _apk)]));
    refuses('not JSON', Uint8List.fromList(utf8.encode('nope')));
    refuses('a JSON array', Uint8List.fromList(utf8.encode('[]')));
  });

  group('version compare', () {
    int cmp(String a, String b) => AppVersion.tryParse(a.split('+')[0], a.split('+')[1])!
        .compareTo(AppVersion.tryParse(b.split('+')[0], b.split('+')[1])!);

    test('orders by version then build', () {
      expect(cmp('0.7.1+1', '0.7.0+1'), greaterThan(0));
      expect(cmp('0.7.0+2', '0.7.0+1'), greaterThan(0));
      expect(cmp('0.7.0+1', '0.7.0+1'), 0);
      expect(cmp('0.6.9+9', '0.7.0+1'), lessThan(0));
      expect(cmp('0.10.0+1', '0.9.0+1'), greaterThan(0));
    });

    test('rejects text that is not a version', () {
      expect(AppVersion.tryParse('1.2', '1'), isNull);
      expect(AppVersion.tryParse('1.2.3', 'x'), isNull);
    });
  });

  group('UpdateService', () {
    late _FakeGithub gh;
    late _TestKey key;
    late Directory tmp;

    UpdateService service({UpdateTarget target = UpdateTarget.android}) {
      final dio = Dio()..httpClientAdapter = gh;
      return UpdateService(
        dio: dio,
        target: target,
        key: key.publicKey,
        tempDir: () async => tmp,
        downloadsDir: () async => Directory('${tmp.path}/Downloads')..createSync(),
        reveal: (_) async {},
      );
    }

    void publishGood({Uint8List? apk, List<Map<String, Object?>>? files, String tag = 'v9.9.9', String version = '9.9.9', int build = 3, bool withSig = true, String? apkUrl}) {
      final m = _manifestBytes(tag: tag, version: version, build: build, files: files);
      _publish(gh, manifest: m, signature: key.signManifest(m), tag: tag, apk: apk, withSig: withSig, apkUrl: apkUrl);
    }

    setUp(() {
      gh = _FakeGithub();
      key = _TestKey();
      tmp = Directory.systemTemp.createTempSync('update_test');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('offers a newer signed release', () async {
      publishGood();
      final offer = await service().check(current);
      expect(offer, isNotNull);
      expect(offer!.version.toString(), '9.9.9+3');
      expect(offer.file!.name, 'oui-spy-v9.9.9.apk');
    });

    test('says up to date for the same version and build', () async {
      publishGood(version: '0.7.0', build: 1);
      expect(await service().check(current), isNull);
    });

    test('refuses an older release', () async {
      publishGood(version: '0.6.9', build: 9);
      await expectLater(service().check(current), throwsA(isA<ReleaseRefused>()));
    });

    test('offers a higher build of the same version', () async {
      publishGood(version: '0.7.0', build: 2);
      expect(await service().check(current), isNotNull);
    });

    test('refuses a release with no signature asset', () async {
      publishGood(withSig: false);
      await expectLater(service().check(current), throwsA(isA<ReleaseRefused>()));
    });

    test('refuses a manifest signed by another key', () async {
      final m = _manifestBytes();
      _publish(gh, manifest: m, signature: _TestKey().signManifest(m));
      await expectLater(service().check(current), throwsA(isA<ReleaseRefused>()));
    });

    test('refuses a manifest signed for another tag', () async {
      final m = _manifestBytes(tag: 'v9.9.8', version: '9.9.8');
      _publish(gh, manifest: m, signature: key.signManifest(m), tag: 'v9.9.9');
      await expectLater(service().check(current), throwsA(isA<ReleaseRefused>()));
    });

    test('refuses a signed release that lacks this platform build', () async {
      publishGood(files: [_entry('oui-spy-macos-v9.9.9.zip', _apk)]);
      await expectLater(service().check(current), throwsA(isA<ReleaseRefused>()));
    });

    test('refuses an asset link that is not a release download of this repo', () async {
      publishGood(apkUrl: 'https://example.invalid/oui-spy-v9.9.9.apk');
      await expectLater(service().check(current), throwsA(isA<ReleaseRefused>()));
    });

    test('iOS gets the TestFlight link and no file', () async {
      publishGood();
      final offer = await service(target: UpdateTarget.ios).check(current);
      expect(offer!.file, isNull);
      expect(offer.url, UpdateService.testFlightUrl);
    });

    test('downloads a file that matches its signed size and sha256', () async {
      publishGood();
      final svc = service();
      final file = await svc.download((await svc.check(current))!);
      expect(file.readAsBytesSync(), _apk);
      expect(file.path.endsWith('/updates/oui-spy-v9.9.9.apk'), isTrue);
      expect(Directory('${tmp.path}/updates').listSync().length, 1);
    });

    test('refuses and deletes a download whose sha256 differs', () async {
      final tampered = Uint8List.fromList(_apk)..[0] ^= 1;
      publishGood(apk: tampered);
      final svc = service();
      final offer = (await svc.check(current))!;
      await expectLater(svc.download(offer), throwsA(isA<ReleaseRefused>()));
      expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
    });

    test('refuses a download shorter than its signed size', () async {
      publishGood(apk: _apk.sublist(0, 5));
      final svc = service();
      final offer = (await svc.check(current))!;
      await expectLater(svc.download(offer), throwsA(isA<ReleaseRefused>()));
      expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
    });

    test('refuses a download longer than its signed size', () async {
      publishGood(apk: Uint8List.fromList([..._apk, 0]));
      final svc = service();
      final offer = (await svc.check(current))!;
      await expectLater(svc.download(offer), throwsA(isA<ReleaseRefused>()));
      expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
    });

    test('macOS saves the verified zip to Downloads without replacing an older save', () async {
      final zip = Uint8List.fromList(utf8.encode('pretend zip'));
      final m = _manifestBytes(files: [_entry('oui-spy-macos-v9.9.9.zip', zip)]);
      _publish(gh, manifest: m, signature: key.signManifest(m));
      gh.bodies['${_prefix}v9.9.9/oui-spy-macos-v9.9.9.zip'] = zip;
      gh.bodies[_latest] = Uint8List.fromList(utf8.encode(jsonEncode({
        'tag_name': 'v9.9.9',
        'assets': [
          {'name': 'release.json', 'browser_download_url': '${_prefix}v9.9.9/release.json'},
          {'name': 'release.json.sig', 'browser_download_url': '${_prefix}v9.9.9/release.json.sig'},
          {'name': 'oui-spy-macos-v9.9.9.zip', 'browser_download_url': '${_prefix}v9.9.9/oui-spy-macos-v9.9.9.zip'},
        ],
      })));
      final svc = service(target: UpdateTarget.macos);
      final offer = (await svc.check(current))!;
      final first = await svc.install(await svc.download(offer), offer);
      final second = await svc.install(await svc.download(offer), offer);
      expect(first.outcome, InstallOutcome.savedToDownloads);
      expect(File(first.path!).readAsBytesSync(), zip);
      expect(second.path, isNot(first.path));
      expect(File(second.path!).existsSync(), isTrue);
    });
  });
}
