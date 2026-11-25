// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:oui_spy/core/ota/ota_signature.dart';

const int chipIdEsp32 = 0x0000;
const int chipIdEsp32S3 = 0x0009;
const int chipIdEsp32C5 = 0x0017;

const int _imageMagic = 0xE9;
const int _descOffset = 32;
const int _descMagic = 0xABCD5432;
const int _minImageBytes = 64 * 1024;

String chipName(int id) => switch (id) {
      chipIdEsp32 => 'ESP32',
      0x0002 => 'ESP32-S2',
      0x0005 => 'ESP32-C3',
      chipIdEsp32S3 => 'ESP32-S3',
      0x000C => 'ESP32-C2',
      0x000D => 'ESP32-C6',
      0x0010 => 'ESP32-H2',
      0x0012 => 'ESP32-P4',
      chipIdEsp32C5 => 'ESP32-C5',
      _ => 'chip id $id',
    };

/// The chip family of each node board the app can update over the mesh (platformio.ini boards).
int? nodeChipId(String? board) => switch (board) {
      'xiao_s3' || 's3_devkitc' || 'tdongle_s3' => chipIdEsp32S3,
      'xiao_c5' || 'tdongle_c5' => chipIdEsp32C5,
      'stickc' || 'stickc_plus' || 'stickc_plus2' => chipIdEsp32,
      _ => null,
    };

/// Size of the OTA app slot per node board (partitions.csv, partitions_16mb.csv, the Arduino default.csv).
int? nodeSlotBytes(String? board) => switch (board) {
      'xiao_s3' || 's3_devkitc' || 'tdongle_s3' || 'xiao_c5' || 'tdongle_c5' => 0x300000,
      'stickc' || 'stickc_plus' || 'stickc_plus2' => 0x140000,
      _ => null,
    };

class FirmwareImage {
  const FirmwareImage({
    required this.name,
    required this.bytes,
    required this.sha256Hex,
    required this.chipId,
    required this.projectName,
    required this.descVersion,
    required this.board,
    required this.role,
    required this.nameVersion,
    required this.signed,
  });

  final String name;
  final Uint8List bytes;
  final String sha256Hex;
  final int chipId;
  final String projectName;
  final String descVersion;
  final String? board;
  final String? role;
  final String? nameVersion;
  final bool signed;

  int get size => bytes.length;
  String get chip => chipName(chipId);

  List<int>? get version => parseImageVersion(nameVersion) ?? parseImageVersion(descVersion);
  String get versionLabel =>
      nameVersion ?? (parseImageVersion(descVersion) != null ? descVersion : '');

  FirmwareImage withSigned(bool v) => FirmwareImage(
        name: name,
        bytes: bytes,
        sha256Hex: sha256Hex,
        chipId: chipId,
        projectName: projectName,
        descVersion: descVersion,
        board: board,
        role: role,
        nameVersion: nameVersion,
        signed: v,
      );
}

class ImageInspection {
  const ImageInspection.ok(FirmwareImage this.image) : error = null;
  const ImageInspection.bad(String this.error) : image = null;
  final FirmwareImage? image;
  final String? error;
}

List<int>? parseImageVersion(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^v?(\d{1,4})\.(\d{1,4})\.(\d{1,4})$').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

final RegExp _assetName = RegExp(r'^oui-spy-(node|mgr)-([a-z0-9_]+?)-v(\d+\.\d+\.\d+)(?:\.bin)?$', caseSensitive: false);

String _cstr(Uint8List b, int off, int len) {
  var end = off;
  while (end < off + len && b[end] != 0) {
    end++;
  }
  return utf8.decode(b.sublist(off, end), allowMalformed: true);
}

/// Checks that [bytes] is an ESP32 application image ("firmware.bin", not a merged or bootloader file)
/// and reads what the image says about itself. Signature is checked separately (see [inspectImage]).
ImageInspection inspectImageStructure(Uint8List bytes, {String name = ''}) {
  if (bytes.length < _minImageBytes) {
    return ImageInspection.bad('${bytes.length} bytes is not a plausible app image (64 KB or more)');
  }
  if (bytes[0] != _imageMagic) {
    return const ImageInspection.bad('not an ESP32 application image (use the firmware .bin, not a merged or bootloader file)');
  }
  final bd = ByteData.sublistView(bytes);
  final chip = bd.getUint16(12, Endian.little);
  if (bd.getUint32(_descOffset, Endian.little) != _descMagic) {
    return const ImageInspection.bad('no ESP-IDF app description in the image');
  }
  final m = _assetName.firstMatch(name.split('/').last);
  return ImageInspection.ok(FirmwareImage(
    name: name,
    bytes: bytes,
    sha256Hex: sha256.convert(bytes).toString(),
    chipId: chip,
    projectName: _cstr(bytes, _descOffset + 48, 32),
    descVersion: _cstr(bytes, _descOffset + 16, 32),
    board: m?.group(2)?.toLowerCase(),
    role: m?.group(1)?.toLowerCase(),
    nameVersion: m?.group(3),
    signed: false,
  ));
}

bool _verifySigned(Uint8List bytes) => OtaSignature.verify(bytes);

Future<ImageInspection> inspectImage(Uint8List bytes, {String name = ''}) async {
  final r = inspectImageStructure(bytes, name: name);
  final img = r.image;
  if (img == null) return r;
  final ok = await compute(_verifySigned, bytes);
  return ImageInspection.ok(img.withSigned(ok));
}
