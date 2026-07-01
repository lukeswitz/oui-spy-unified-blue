import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';

class OtaRelease {
  OtaRelease({
    required this.tag,
    required this.version,
    required this.assetName,
    required this.assetUrl,
    required this.body,
    required this.publishedAt,
  });

  final String tag;
  final List<int> version;
  final String assetName;
  final String assetUrl;
  final String body;
  final DateTime publishedAt;
}

enum OtaPhase {
  idle,
  checking,
  downloading,
  uploading,
  verifying,
  rebooting,
  upToDate,
  error,
}

class OtaProgress {
  const OtaProgress({
    required this.phase,
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.message = '',
    this.error,
  });

  final OtaPhase phase;
  final int bytesSent;
  final int bytesTotal;
  final String message;
  final String? error;

  double get fraction =>
      bytesTotal == 0 ? 0.0 : (bytesSent / bytesTotal).clamp(0.0, 1.0);
}

class OtaService {
  OtaService(this._ble);

  final BleManager _ble;
  final Dio _dio = Dio();

  static const String githubOwner = 'lukeswitz';
  static const String githubRepo = 'oui-spy-unified-blue';
  static const String firmwareAssetSuffix = '.bin';

  final StreamController<OtaProgress> _progress =
      StreamController<OtaProgress>.broadcast();
  Stream<OtaProgress> get progress => _progress.stream;

  bool _running = false;
  bool get isRunning => _running;

  final ValueNotifier<bool> otaActive = ValueNotifier<bool>(false);
  Timer? _activeTimer;

  void markOtaActive({Duration ttl = const Duration(seconds: 150)}) {
    _activeTimer?.cancel();
    otaActive.value = true;
    _activeTimer = Timer(ttl, () => otaActive.value = false);
  }

  void clearOtaActive() {
    _activeTimer?.cancel();
    otaActive.value = false;
  }

  static List<int>? parseVersion(String v) {
    final cleaned = v.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split(RegExp(r'[.\-+]'));
    final out = <int>[];
    for (final p in parts) {
      if (p.isEmpty) continue;
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }

  static int compareVersion(List<int> a, List<int> b) {
    final n = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av - bv;
    }
    return 0;
  }

  static int _scoreAsset(String name, String board, String role) {
    final n = name.toLowerCase();
    if (!n.endsWith('.bin')) return -1;
    if (!n.contains('oui-spy')) return -1;
    if (n.contains('-bootloader') ||
        n.contains('-partitions') ||
        n.contains('-boot_app0')) return -1;
    int score = 1;
    if (board.isNotEmpty && n.contains(board.toLowerCase())) score += 10;
    if (role.isNotEmpty && n.contains('-$role-')) score += 5;
    return score;
  }

  static const String _otaApiOverride =
      String.fromEnvironment('OTA_API', defaultValue: '');

  Future<Map<String, dynamic>?> _getLatestJson() async {
    final url = _otaApiOverride.isNotEmpty
        ? _otaApiOverride
        : 'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
    final resp = await _dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        responseType: ResponseType.json,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    return resp.data;
  }

  OtaRelease? _releaseFromJson(Map<String, dynamic> data, String board, String role,
      {bool emitError = true}) {
    final tag = data['tag_name']?.toString() ?? '';
    final body = data['body']?.toString() ?? '';
    final publishedRaw = data['published_at']?.toString() ?? '';
    final published = DateTime.tryParse(publishedRaw) ?? DateTime.now();
    final version = parseVersion(tag);
    if (version == null) {
      DebugLog.log('OTA: unparseable release tag "$tag"');
      if (emitError) {
        _progress.add(OtaProgress(
          phase: OtaPhase.error,
          error: 'Latest release tag "$tag" unparseable',
        ));
      }
      return null;
    }

    final assets = (data['assets'] as List?) ?? const [];
    String? assetName;
    String? assetUrl;
    int bestScore = 0;
    for (final a in assets) {
      final m = a as Map<String, dynamic>;
      final name = m['name']?.toString() ?? '';
      final score = _scoreAsset(name, board, role);
      if (score > bestScore) {
        bestScore = score;
        assetName = name;
        assetUrl = m['browser_download_url']?.toString();
      }
    }
    if (assetName == null || assetUrl == null) {
      DebugLog.log('OTA: no .bin asset in release $tag for board=$board role=$role');
      if (emitError) {
        _progress.add(OtaProgress(
          phase: OtaPhase.error,
          error: 'Latest release $tag has no firmware .bin asset',
        ));
      }
      return null;
    }

    return OtaRelease(
      tag: tag,
      version: version,
      assetName: assetName,
      assetUrl: assetUrl,
      body: body,
      publishedAt: published,
    );
  }

  Future<OtaRelease?> fetchLatestRelease({String board = '', String role = ''}) async {
    final data = await _getLatestJson();
    if (data == null) {
      _progress.add(const OtaProgress(
        phase: OtaPhase.error,
        error: 'GitHub returned empty response',
      ));
      return null;
    }
    return _releaseFromJson(data, board, role);
  }

  Future<({OtaRelease? primary, OtaRelease? node, String? error})> fetchLatestPair({
    String board = '',
    String role = '',
    bool includeNode = false,
    String nodeBoard = 'xiao_s3',
  }) async {
    _progress.add(const OtaProgress(
      phase: OtaPhase.checking,
      message: 'Fetching latest release...',
    ));
    Map<String, dynamic>? data;
    try {
      data = await _getLatestJson();
    } on DioException catch (e) {
      DebugLog.log('OTA: GitHub fetch failed: type=${e.type} status=${e.response?.statusCode} '
          'msg=${e.message} err=${e.error}');
      final detail = e.response?.statusCode != null
          ? 'HTTP ${e.response!.statusCode}'
          : (e.error?.toString() ?? e.message ?? e.type.name);
      final msg = 'Update check failed: $detail';
      _progress.add(OtaProgress(phase: OtaPhase.error, error: msg));
      return (primary: null, node: null, error: msg);
    } catch (e) {
      final msg = 'Update check failed: $e';
      DebugLog.log('OTA: $msg');
      _progress.add(OtaProgress(phase: OtaPhase.error, error: msg));
      return (primary: null, node: null, error: msg);
    }
    if (data == null) {
      const msg = 'GitHub returned empty response';
      _progress.add(const OtaProgress(phase: OtaPhase.error, error: msg));
      return (primary: null, node: null, error: msg);
    }
    final primary = _releaseFromJson(data, board, role);
    final node =
        includeNode ? _releaseFromJson(data, nodeBoard, 'node', emitError: false) : null;
    return (primary: primary, node: node, error: null);
  }

  Future<OtaRelease?> checkForUpdate(String currentVersion, {String board = '', String role = ''}) async {
    _progress.add(const OtaProgress(
      phase: OtaPhase.checking,
      message: 'Fetching latest release...',
    ));
    final OtaRelease? latest;
    try {
      latest = await fetchLatestRelease(board: board, role: role);
    } on DioException catch (e) {
      DebugLog.log('OTA: GitHub fetch failed: ${e.type} ${e.message}');
      final msg = e.type == DioExceptionType.connectionTimeout
              || e.type == DioExceptionType.receiveTimeout
              || e.type == DioExceptionType.sendTimeout
          ? 'GitHub API timed out — check network'
          : 'Network error: ${e.message ?? e.type.toString()}';
      _progress.add(OtaProgress(phase: OtaPhase.error, error: msg));
      return null;
    }
    if (latest == null) {
      // fetchLatestRelease already emitted a specific error (no asset / bad tag)
      return null;
    }
    final cur = parseVersion(currentVersion) ?? [0, 0, 0];
    final cmp = compareVersion(latest.version, cur);
    if (cmp <= 0) {
      _progress.add(OtaProgress(
        phase: OtaPhase.upToDate,
        message: 'Up to date (${latest.tag})',
      ));
      return null;
    }
    // Update available — clear "checking" progress so UI shows install button
    _progress.add(OtaProgress(
      phase: OtaPhase.idle,
      message: 'Update available: ${latest.tag}',
    ));
    return latest;
  }

  Future<Uint8List> _download(String url) async {
    _progress.add(const OtaProgress(
      phase: OtaPhase.downloading,
      message: 'Downloading firmware...',
    ));
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
      ),
      onReceiveProgress: (received, total) {
        _progress.add(OtaProgress(
          phase: OtaPhase.downloading,
          bytesSent: received,
          bytesTotal: total < 0 ? 0 : total,
          message: 'Downloading...',
        ));
      },
    );
    return Uint8List.fromList(resp.data ?? const []);
  }

  /// Run full OTA: download .bin from release, push to firmware via DFU.
  Future<bool> performUpdate(OtaRelease release) async {
    if (_running) return false;
    _running = true;
    markOtaActive(ttl: const Duration(seconds: 120));
    try {
      final image = await _download(release.assetUrl);
      if (image.isEmpty) {
        _progress.add(const OtaProgress(
          phase: OtaPhase.error,
          error: 'Empty firmware image',
        ));
        return false;
      }
      return await _pushImage(image);
    } on DioException catch (e) {
      DebugLog.log('OTA: dio error ${e.type} ${e.message}');
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'Network error: ${e.message ?? e.type.toString()}',
      ));
      return false;
    } finally {
      _running = false;
    }
  }

  Future<bool> performWifiUpdate(OtaRelease release) async {
    if (_running) return false;
    _running = true;
    markOtaActive(ttl: const Duration(seconds: 150));
    try {
      _progress.add(const OtaProgress(
        phase: OtaPhase.uploading,
        message: 'Sending OTA URL to device...',
      ));
      await _ble.triggerWifiOta(release.assetUrl);
      _progress.add(const OtaProgress(
        phase: OtaPhase.rebooting,
        message: 'Device rebooting into WiFi-update mode. BLE goes offline while '
            'it downloads + flashes — it reconnects on its own when done '
            '(~30–60s). Do not power off.',
      ));
      return true;
    } on StateError catch (e) {
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: e.message,
      ));
      return false;
    } on FlutterBluePlusException catch (e) {
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'BLE write failed: ${e.description}',
      ));
      return false;
    } finally {
      _running = false;
    }
  }

  /// Push a pre-fetched firmware image (e.g. user-selected .bin) via DFU.
  Future<bool> pushLocalImage(Uint8List image) async {
    if (_running) return false;
    _running = true;
    markOtaActive(ttl: const Duration(seconds: 120));
    try {
      return await _pushImage(image);
    } finally {
      _running = false;
    }
  }

  Future<bool> _pushImage(Uint8List image) async {
    final dfuData = _ble.dfuData;
    final dfuControl = _ble.dfuControl;
    if (dfuData == null || dfuControl == null) {
      _progress.add(const OtaProgress(
        phase: OtaPhase.error,
        error: 'DFU characteristics not found — firmware too old?',
      ));
      return false;
    }

    if (image.isEmpty || image[0] != 0xE9) {
      final got = image.isEmpty ? 'empty' : '0x${image[0].toRadixString(16)}';
      DebugLog.log('OTA: bad magic byte: $got (expected 0xE9)');
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'Asset is not an ESP32 app image (magic=$got, expected 0xE9). '
               'Wrong file uploaded to release?',
      ));
      return false;
    }
    if (image.length < 1024) {
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'Asset too small (${image.length} bytes) — not firmware.',
      ));
      return false;
    }

    await dfuControl.setNotifyValue(true);
    final statusCompleter = Completer<bool>();
    final statusSub = dfuControl.onValueReceived.listen((data) {
      if (data.length < 4) return;
      final seq = data[1] | (data[2] << 8);
      final status = data[3];
      DebugLog.log('OTA: status seq=$seq code=0x${status.toRadixString(16)}');
      if (status == 0x00) {
        // periodic progress ACK from firmware (seq = KB received)
        return;
      }
      if (status == 0xFF) {
        if (!statusCompleter.isCompleted) statusCompleter.complete(true);
        return;
      }
      // any other code is an error from ota_handler.cpp
      if (!statusCompleter.isCompleted) statusCompleter.complete(false);
    });

    try {
      final crc = _crc32(image);
      final mtu = _ble.mtu;
      final chunkSize = (mtu - 3).clamp(20, 244);

      final start = ByteData(9);
      start.setUint8(0, 0x01);
      start.setUint32(1, image.length, Endian.little);
      start.setUint32(5, crc, Endian.little);
      _progress.add(OtaProgress(
        phase: OtaPhase.uploading,
        bytesTotal: image.length,
        message: 'Starting transfer...',
      ));
      await dfuData.write(start.buffer.asUint8List(), withoutResponse: false);

      final stopwatch = Stopwatch()..start();
      int offset = 0;
      int seq = 0;
      const int syncEvery = 128;
      while (offset < image.length) {
        final end =
            (offset + (chunkSize - 3)).clamp(0, image.length);
        final payload = image.sublist(offset, end);
        final pkt = Uint8List(3 + payload.length);
        final view = ByteData.sublistView(pkt);
        view.setUint8(0, 0x02);
        view.setUint16(1, seq, Endian.little);
        pkt.setRange(3, 3 + payload.length, payload);

        final isSync = (seq % syncEvery) == (syncEvery - 1);
        await dfuData.write(pkt, withoutResponse: !isSync);

        offset = end;
        seq++;
        if ((seq & 0x1F) == 0) {
          final kbps = stopwatch.elapsedMilliseconds == 0
              ? 0
              : (offset * 1000 ~/ stopwatch.elapsedMilliseconds) ~/ 1024;
          _progress.add(OtaProgress(
            phase: OtaPhase.uploading,
            bytesSent: offset,
            bytesTotal: image.length,
            message: '${(offset / 1024).toStringAsFixed(0)}KB '
                '/ ${(image.length / 1024).toStringAsFixed(0)}KB '
                '(${kbps}KB/s)',
          ));
        }
      }

      _progress.add(OtaProgress(
        phase: OtaPhase.verifying,
        bytesSent: image.length,
        bytesTotal: image.length,
        message: 'Verifying...',
      ));

      // COMMIT: response required so we know firmware reached CRC check.
      await dfuData.write(Uint8List.fromList([0x03]), withoutResponse: false);

      final ok = await statusCompleter.future
          .timeout(const Duration(seconds: 30), onTimeout: () {
        DebugLog.log('OTA: COMMIT ack timed out');
        return false;
      });
      if (ok) {
        _progress.add(const OtaProgress(
          phase: OtaPhase.rebooting,
          message: 'Update applied — device rebooting',
        ));
      } else {
        _progress.add(const OtaProgress(
          phase: OtaPhase.error,
          error: 'Firmware rejected image (see device serial log)',
        ));
      }
      return ok;
    } catch (e) {
      DebugLog.log('OTA: DFU transfer failed: $e');
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'Transfer interrupted: $e',
      ));
      return false;
    } finally {
      await statusSub.cancel();
    }
  }

  Future<void> abort() async {
    final dfuData = _ble.dfuData;
    if (dfuData == null) return;
    try {
      await dfuData.write(Uint8List.fromList([0x04]), withoutResponse: false);
    } on FlutterBluePlusException catch (e) {
      DebugLog.log('OTA: abort write failed: ${e.description}');
    }
    _running = false;
  }

  /// CRC32 (IEEE 802.3) matching firmware ota_handler.cpp.
  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int j = 0; j < 8; j++) {
        if (crc & 1 == 1) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

final otaServiceProvider = Provider<OtaService>((ref) {
  final ble = ref.read(bleManagerProvider);
  return OtaService(ble);
});
