import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ota/ota_service.dart';

const int kPort = 8731;

const String kOtaApi = String.fromEnvironment('OTA_API');

const List<String> kAssets = [
  'oui-spy-node-xiao_s3-v0.5.1.bin',
  'oui-spy-node-s3_devkitc-v0.5.1.bin',
  'oui-spy-node-tdongle_s3-v0.5.1.bin',
  'oui-spy-node-xiao_c5-v0.5.1.bin',
  'oui-spy-node-stickc-v0.5.1.bin',
  'oui-spy-node-stickc_plus-v0.5.1.bin',
  'oui-spy-node-stickc_plus2-v0.5.1.bin',
  'oui-spy-mgr-wroom-v0.5.1.bin',
  'oui-spy-mgr-xiao_c3-v0.5.1.bin',
  'oui-spy-mgr-xiao_s3-v0.5.1.bin',
  'oui-spy-mgr-s3_devkitc-v0.5.1.bin',
  'oui-spy-node-xiao_s3-v0.5.1-bootloader.bin',
  'oui-spy-node-xiao_s3-v0.5.1-partitions.bin',
  'oui-spy-node-xiao_s3-v0.5.1-boot_app0.bin',
];

Map<String, dynamic> releaseJson(List<String> names) => {
      'tag_name': 'v0.5.1',
      'body': 'release notes',
      'published_at': '2026-01-01T00:00:00Z',
      'assets': [
        for (final n in names)
          {'name': n, 'browser_download_url': 'https://example.invalid/$n'},
      ],
    };

void main() {
  if (kOtaApi != 'http://127.0.0.1:$kPort/latest') {
    test('ota asset pick', () {},
        skip: 'run with --dart-define=OTA_API=http://127.0.0.1:$kPort/latest');
    return;
  }

  late HttpServer server;
  List<String> served = kAssets;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, kPort);
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(releaseJson(served)))
        ..close();
    });
  });

  tearDownAll(() async => server.close(force: true));

  Future<String?> pick(String board, String role) async {
    final ota = OtaService(BleManager());
    final r = await ota.fetchLatestRelease(board: board, role: role);
    return r?.assetName;
  }

  test('each board gets its own image', () async {
    expect(await pick('xiao_s3', 'node'), 'oui-spy-node-xiao_s3-v0.5.1.bin');
    expect(await pick('s3_devkitc', 'node'),
        'oui-spy-node-s3_devkitc-v0.5.1.bin');
    expect(await pick('tdongle_s3', 'node'),
        'oui-spy-node-tdongle_s3-v0.5.1.bin');
    expect(await pick('xiao_c5', 'node'), 'oui-spy-node-xiao_c5-v0.5.1.bin');
    expect(await pick('wroom', 'mgr'), 'oui-spy-mgr-wroom-v0.5.1.bin');
    expect(await pick('xiao_c3', 'mgr'), 'oui-spy-mgr-xiao_c3-v0.5.1.bin');
    expect(await pick('xiao_s3', 'mgr'), 'oui-spy-mgr-xiao_s3-v0.5.1.bin');
    expect(
        await pick('s3_devkitc', 'mgr'), 'oui-spy-mgr-s3_devkitc-v0.5.1.bin');
  });

  test('board name that is a prefix of another never takes its image', () async {
    for (final order in [kAssets, kAssets.reversed.toList()]) {
      served = order;
      expect(await pick('stickc', 'node'), 'oui-spy-node-stickc-v0.5.1.bin');
      expect(await pick('stickc_plus', 'node'),
          'oui-spy-node-stickc_plus-v0.5.1.bin');
      expect(await pick('stickc_plus2', 'node'),
          'oui-spy-node-stickc_plus2-v0.5.1.bin');
    }
    served = kAssets;
  });

  test('unpublished board gets nothing, never another chip image', () async {
    expect(await pick('tdongle_c5', 'node'), isNull);
  });

  test('tdongle_c5 resolves once its asset ships', () async {
    served = [...kAssets, 'oui-spy-node-tdongle_c5-v0.5.1.bin'];
    addTearDown(() => served = kAssets);
    expect(await pick('tdongle_c5', 'node'),
        'oui-spy-node-tdongle_c5-v0.5.1.bin');
  });

  test('unknown board still falls back', () async {
    expect(await pick('', 'node'), isNotNull);
  });
}
