// Copyright (c) 2026 Luke Switzer
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/core/update/release_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum UpdateTarget { android, macos, ios, other }

enum InstallOutcome { installerOpened, needsPermission, savedToDownloads }

class UpdateOffer {
  const UpdateOffer({
    required this.manifest,
    required this.target,
    this.file,
    this.url,
  });

  final ReleaseManifest manifest;
  final UpdateTarget target;
  final ManifestFile? file;
  final String? url;

  AppVersion get version => manifest.version;
}

class UpdateInstalled {
  const UpdateInstalled(this.outcome, [this.path]);
  final InstallOutcome outcome;
  final String? path;
}

class UpdateService {
  UpdateService({
    Dio? dio,
    UpdateTarget? target,
    List<int>? key,
    Future<Directory> Function()? tempDir,
    Future<Directory?> Function()? downloadsDir,
    MethodChannel? channel,
    Future<void> Function(String path)? reveal,
  })  : _dio = dio ?? Dio(),
        target = target ?? _platformTarget(),
        _key = key,
        _tempDir = tempDir ?? getTemporaryDirectory,
        _downloadsDir = downloadsDir ?? getDownloadsDirectory,
        _channel = channel ?? const MethodChannel('oui_spy/app_update'),
        _reveal = reveal ?? _revealInFinder;

  static const String testFlightUrl = 'https://testflight.apple.com/join/5RCKgnJ2';
  static const String _userAgent = 'oui-spy-companion/1.0';
  static const String _downloadPrefix =
      'https://github.com/${OtaService.githubOwner}/${OtaService.githubRepo}/releases/download/';
  static const String _latestUrl =
      'https://api.github.com/repos/${OtaService.githubOwner}/${OtaService.githubRepo}/releases/latest';

  final Dio _dio;
  final UpdateTarget target;
  final List<int>? _key;
  final Future<Directory> Function() _tempDir;
  final Future<Directory?> Function() _downloadsDir;
  final MethodChannel _channel;
  final Future<void> Function(String path) _reveal;
  DateTime? _retryAt;

  static UpdateTarget _platformTarget() {
    if (Platform.isAndroid) return UpdateTarget.android;
    if (Platform.isMacOS) return UpdateTarget.macos;
    if (Platform.isIOS) return UpdateTarget.ios;
    return UpdateTarget.other;
  }

  static Future<void> _revealInFinder(String path) async {
    final r = await Process.run('open', ['-R', path]);
    if (r.exitCode != 0) throw ReleaseRefused('could not reveal the file in Finder');
  }

  static String? assetNameFor(UpdateTarget target, String tag) => switch (target) {
        UpdateTarget.android => 'oui-spy-$tag.apk',
        UpdateTarget.macos => 'oui-spy-macos-$tag.zip',
        _ => null,
      };

  Future<UpdateOffer?> check(AppVersion current) async {
    final latest = await _getLatest();
    final tag = latest['tag_name'];
    if (tag is! String || tag.isEmpty) {
      throw ReleaseRefused('refused: the latest release has no tag');
    }
    final urls = <String, String>{};
    final assets = latest['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = a['name'];
        final url = a['browser_download_url'];
        if (name is String && url is String) urls[name] = url;
      }
    }
    final manifestUrl = _trusted(urls[ReleaseManifest.manifestAsset]);
    final sigUrl = _trusted(urls[ReleaseManifest.signatureAsset]);
    if (manifestUrl == null || sigUrl == null) {
      throw ReleaseRefused('refused: release $tag carries no signed release.json');
    }
    final manifestBytes = await _fetchBytes(manifestUrl, ReleaseManifest.maxManifestBytes);
    final sigBytes = await _fetchBytes(sigUrl, 128);
    final manifest = ReleaseManifest.parseVerified(manifestBytes, sigBytes, key: _key);
    if (manifest.tag != tag) {
      throw ReleaseRefused('refused: release.json is for ${manifest.tag}, not $tag');
    }
    final cmp = manifest.version.compareTo(current);
    if (cmp == 0) return null;
    if (cmp < 0) {
      throw ReleaseRefused('refused: ${manifest.version} is older than this app ($current)');
    }
    final wanted = assetNameFor(target, tag);
    if (wanted == null) return UpdateOffer(manifest: manifest, target: target, url: testFlightUrl);
    final file = manifest.files.where((f) => f.name == wanted).firstOrNull;
    if (file == null) {
      throw ReleaseRefused('refused: the signed release lists no $wanted');
    }
    final url = _trusted(urls[wanted]);
    if (url == null) throw ReleaseRefused('refused: release $tag carries no $wanted');
    return UpdateOffer(manifest: manifest, target: target, file: file, url: url);
  }

  Future<File> download(UpdateOffer offer, {void Function(int received, int total)? onProgress}) async {
    final file = offer.file;
    final url = offer.url;
    if (file == null || url == null) throw ReleaseRefused('this platform installs from TestFlight');
    final root = await _tempDir();
    final dir = Directory(p.join(root.path, 'updates'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final part = File(p.join(dir.path, '${file.name}.part'));
    final sink = part.openWrite();
    try {
      await _stream(url, file.size, sink.add, onProgress: onProgress);
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      await _drop(part);
      rethrow;
    }
    final size = await part.length();
    if (size != file.size) {
      await _drop(part);
      throw ReleaseRefused('refused: ${file.name} is $size bytes, its signed size is ${file.size}');
    }
    final digest = (await sha256.bind(part.openRead()).first).toString();
    if (digest != file.sha256) {
      await _drop(part);
      throw ReleaseRefused('refused: ${file.name} does not match its signed sha256');
    }
    return part.rename(p.join(dir.path, file.name));
  }

  Future<UpdateInstalled> install(File verified, UpdateOffer offer) async {
    switch (target) {
      case UpdateTarget.android:
        final r = await _channel.invokeMethod<String>('installApk', {'path': verified.path});
        return UpdateInstalled(
            r == 'permission' ? InstallOutcome.needsPermission : InstallOutcome.installerOpened);
      case UpdateTarget.macos:
        final dir = await _downloadsDir();
        if (dir == null) throw ReleaseRefused('no Downloads folder is available');
        final saved = await _copyUnique(verified, dir);
        await _reveal(saved.path);
        return UpdateInstalled(InstallOutcome.savedToDownloads, saved.path);
      case UpdateTarget.ios:
      case UpdateTarget.other:
        throw ReleaseRefused('this platform has no self-update');
    }
  }

  Future<File> _copyUnique(File src, Directory dir) async {
    final base = p.basenameWithoutExtension(src.path);
    final ext = p.extension(src.path);
    var dest = File(p.join(dir.path, '$base$ext'));
    for (var i = 1; await dest.exists(); i++) {
      dest = File(p.join(dir.path, '$base ($i)$ext'));
    }
    return src.copy(dest.path);
  }

  Future<void> _drop(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      return;
    }
  }

  String? _trusted(String? url) =>
      url != null && url.startsWith(_downloadPrefix) ? url : null;

  Future<Map<String, dynamic>> _getLatest() async {
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) throw GithubRateLimited(retryAt);
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        _latestUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': _userAgent,
          },
          responseType: ResponseType.json,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final data = resp.data;
      if (data == null) throw ReleaseRefused('GitHub returned an empty answer');
      return data;
    } on DioException catch (e) {
      final until = OtaService.githubRetryAt(e.response?.statusCode, e.response?.headers, DateTime.now());
      if (until == null) rethrow;
      _retryAt = until;
      throw GithubRateLimited(until);
    }
  }

  Future<Uint8List> _fetchBytes(String url, int maxBytes) async {
    final out = BytesBuilder(copy: false);
    await _stream(url, maxBytes, out.add);
    return out.takeBytes();
  }

  Future<void> _stream(
    String url,
    int maxBytes,
    void Function(List<int>) onChunk, {
    void Function(int received, int total)? onProgress,
  }) async {
    final resp = await _dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {'User-Agent': _userAgent, 'Accept': 'application/octet-stream'},
        responseType: ResponseType.stream,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    if (resp.realUri.scheme != 'https') {
      throw ReleaseRefused('refused: a download link left https');
    }
    final body = resp.data!;
    final declared = int.tryParse(body.headers['content-length']?.first ?? '') ?? -1;
    if (declared > maxBytes) {
      throw ReleaseRefused('refused: the download is larger than its signed size');
    }
    var received = 0;
    await for (final chunk in body.stream) {
      received += chunk.length;
      if (received > maxBytes) {
        throw ReleaseRefused('refused: the download is larger than its signed size');
      }
      onChunk(chunk);
      onProgress?.call(received, maxBytes);
    }
  }
}
