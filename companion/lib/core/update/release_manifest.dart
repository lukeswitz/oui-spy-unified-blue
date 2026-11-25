// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:oui_spy/core/ota/ota_service.dart';
import 'package:oui_spy/core/ota/ota_signature.dart';

class ReleaseRefused implements Exception {
  ReleaseRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

class ManifestFile {
  const ManifestFile({required this.name, required this.size, required this.sha256});
  final String name;
  final int size;
  final String sha256;
}

class AppVersion {
  const AppVersion(this.parts);
  final List<int> parts;

  static AppVersion? tryParse(String version, String build) {
    final v = _versionRe.firstMatch(version);
    final b = int.tryParse(build);
    if (v == null || b == null || b < 0) return null;
    return AppVersion([int.parse(v[1]!), int.parse(v[2]!), int.parse(v[3]!), b]);
  }

  int compareTo(AppVersion other) => OtaService.compareVersion(parts, other.parts);

  @override
  String toString() => '${parts[0]}.${parts[1]}.${parts[2]}+${parts[3]}';
}

final RegExp _versionRe = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$');
final RegExp _nameRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$');
final RegExp _sha256Re = RegExp(r'^[0-9a-f]{64}$');

class ReleaseManifest {
  const ReleaseManifest({
    required this.tag,
    required this.version,
    required this.files,
  });

  static const int format = 1;
  static const String app = 'oui-spy';
  static const String manifestAsset = 'release.json';
  static const String signatureAsset = 'release.json.sig';
  static const int maxManifestBytes = 64 * 1024;
  static final Uint8List signatureContext = Uint8List.fromList(utf8.encode('OSR1\n'));

  final String tag;
  final AppVersion version;
  final List<ManifestFile> files;

  static bool signatureValid(Uint8List manifest, Uint8List signature, {List<int>? key}) {
    final message = Uint8List(signatureContext.length + manifest.length)
      ..setAll(0, signatureContext)
      ..setAll(signatureContext.length, manifest);
    return OtaSignature.verifyDetached(message, signature,
        key: key ?? OtaSignature.publicKey);
  }

  static ReleaseManifest parseVerified(Uint8List manifest, Uint8List signature,
      {List<int>? key}) {
    if (manifest.length > maxManifestBytes) {
      throw ReleaseRefused('refused: release.json is too large');
    }
    if (!signatureValid(manifest, signature, key: key)) {
      throw ReleaseRefused('refused: release.json is not signed with the release key');
    }
    return parse(manifest);
  }

  static ReleaseManifest parse(Uint8List manifest) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(manifest));
    } on FormatException {
      throw ReleaseRefused('refused: release.json is not valid JSON');
    }
    if (json is! Map<String, dynamic>) {
      throw ReleaseRefused('refused: release.json is not an object');
    }
    if (json['format'] != format) {
      throw ReleaseRefused('refused: release.json format ${json['format']} is not supported');
    }
    if (json['app'] != app) {
      throw ReleaseRefused('refused: release.json is for ${json['app']}, not $app');
    }
    final tag = json['tag'];
    if (tag is! String || !_nameRe.hasMatch(tag)) {
      throw ReleaseRefused('refused: release.json has no proper tag');
    }
    final version = json['version'];
    final build = json['build'];
    final parsed = version is String && build is int
        ? AppVersion.tryParse(version, build.toString())
        : null;
    if (parsed == null) {
      throw ReleaseRefused('refused: release.json has no proper version and build');
    }
    final list = json['files'];
    if (list is! List || list.isEmpty) {
      throw ReleaseRefused('refused: release.json lists no files');
    }
    final files = <ManifestFile>[];
    final seen = <String>{};
    for (final entry in list) {
      if (entry is! Map<String, dynamic>) {
        throw ReleaseRefused('refused: release.json has a bad file entry');
      }
      final name = entry['name'];
      final size = entry['size'];
      final sha = entry['sha256'];
      if (name is! String || !_nameRe.hasMatch(name)) {
        throw ReleaseRefused('refused: release.json has a file with no proper name');
      }
      if (name == manifestAsset || name == signatureAsset) {
        throw ReleaseRefused('refused: release.json lists $name');
      }
      if (!seen.add(name)) throw ReleaseRefused('refused: release.json lists $name twice');
      if (size is! int || size <= 0) {
        throw ReleaseRefused('refused: $name has no proper size');
      }
      if (sha is! String || !_sha256Re.hasMatch(sha)) {
        throw ReleaseRefused('refused: $name has no proper sha256');
      }
      files.add(ManifestFile(name: name, size: size, sha256: sha));
    }
    return ReleaseManifest(tag: tag, version: parsed, files: files);
  }
}
