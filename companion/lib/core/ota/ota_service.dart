import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/debug_log.dart';

/// GitHub release fetcher + chunked DFU writer for OUI-SPY firmware.
///
/// Wire protocol matches firmware src/ota_handler.cpp:
///   START:  opcode(0x01)[1] + total_length[4] + crc32[4]   = 9 bytes
///   DATA:   opcode(0x02)[1] + seq_num[2] + payload[N]      = 3+N bytes
///   COMMIT: opcode(0x03)[1]                                = 1 byte
///   ABORT:  opcode(0x04)[1]                                = 1 byte
///   ACK:    opcode(0x05)[1] + seq_num[2] + status[1]       = 4 bytes (notify)
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

  /// Parse N-part dotted version: "v0.0.3.8.1" → [0,0,3,8,1].
  /// Strips leading "v", accepts any number of components.
  /// Returns null on parse failure.
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

  /// Returns >0 if a > b, <0 if a < b, 0 if equal.
  /// Compares component-wise; missing trailing components treated as 0
  /// (so [0,0,3,8] == [0,0,3,8,0]).
  static int compareVersion(List<int> a, List<int> b) {
    final n = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av - bv;
    }
    return 0;
  }

  Future<OtaRelease?> fetchLatestRelease() async {
    final url = 'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
    final resp = await _dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        responseType: ResponseType.json,
      ),
    );
    final data = resp.data;
    if (data == null) {
      _progress.add(const OtaProgress(
        phase: OtaPhase.error,
        error: 'GitHub returned empty response',
      ));
      return null;
    }

    final tag = data['tag_name']?.toString() ?? '';
    final body = data['body']?.toString() ?? '';
    final publishedRaw = data['published_at']?.toString() ?? '';
    final published = DateTime.tryParse(publishedRaw) ?? DateTime.now();
    final version = parseVersion(tag);
    if (version == null) {
      DebugLog.log('OTA: unparseable release tag "$tag"');
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'Latest release tag "$tag" unparseable',
      ));
      return null;
    }

    final assets = (data['assets'] as List?) ?? const [];
    String? assetName;
    String? assetUrl;
    for (final a in assets) {
      final m = a as Map<String, dynamic>;
      final name = m['name']?.toString() ?? '';
      if (name.toLowerCase().endsWith(firmwareAssetSuffix)) {
        assetName = name;
        assetUrl = m['browser_download_url']?.toString();
        break;
      }
    }
    if (assetName == null || assetUrl == null) {
      DebugLog.log('OTA: no .bin asset in release $tag');
      _progress.add(OtaProgress(
        phase: OtaPhase.error,
        error: 'Latest release $tag has no firmware .bin asset',
      ));
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

  /// Compares latest GitHub release version to current firmware.
  /// Returns null if up to date, the release if newer is available.
  Future<OtaRelease?> checkForUpdate(String currentVersion) async {
    _progress.add(const OtaProgress(
      phase: OtaPhase.checking,
      message: 'Fetching latest release...',
    ));
    final latest = await fetchLatestRelease();
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

  /// Push a pre-fetched firmware image (e.g. user-selected .bin) via DFU.
  Future<bool> pushLocalImage(Uint8List image) async {
    if (_running) return false;
    _running = true;
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

      int offset = 0;
      int seq = 0;
      while (offset < image.length) {
        final end =
            (offset + (chunkSize - 3)).clamp(0, image.length);
        final payload = image.sublist(offset, end);
        final pkt = Uint8List(3 + payload.length);
        final view = ByteData.sublistView(pkt);
        view.setUint8(0, 0x02);
        view.setUint16(1, seq, Endian.little);
        pkt.setRange(3, 3 + payload.length, payload);
        await dfuData.write(pkt, withoutResponse: false);
        offset = end;
        seq++;
        if ((seq & 0x1F) == 0) {
          _progress.add(OtaProgress(
            phase: OtaPhase.uploading,
            bytesSent: offset,
            bytesTotal: image.length,
            message: 'Uploading ${(offset / 1024).toStringAsFixed(0)} KB...',
          ));
        }
      }

      _progress.add(OtaProgress(
        phase: OtaPhase.verifying,
        bytesSent: image.length,
        bytesTotal: image.length,
        message: 'Verifying...',
      ));

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
