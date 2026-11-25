// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

/// Mirrors SYS_CMD_MESH_FW / SYS_OP_MESH_FW and the MESH_FW_* codes in src/protocol.h.
class MeshFwProtocol {
  const MeshFwProtocol._();

  static const int opcode = 0x15;
  static const int subSend = 0x01;
  static const int subStop = 0x02;
  static const int subStatus = 0x03;
  static const int maxTargets = 8;
  static const int chunkBytes = 192;
  static const int dfuFlagStageMesh = 0x01;
  static const int dfuStatusStaged = 0xFE;
  static const int dfuStatusStageRefused = 0x0A;

  static Uint8List _cmd(List<int> body) => Uint8List.fromList([opcode, 0xC0, 0xDE, ...body]);

  static Uint8List encodeSend(int version, List<String> ids) {
    if (ids.isEmpty || ids.length > maxTargets) throw ArgumentError('1 to $maxTargets nodes');
    for (final id in ids) {
      if (id.length != 4) throw ArgumentError('node id must be 4 characters: $id');
    }
    final v = ByteData(4)..setUint32(0, version, Endian.little);
    return _cmd([subSend, ...v.buffer.asUint8List(), ids.length, for (final id in ids) ...id.codeUnits]);
  }

  static Uint8List encodeStop() => _cmd([subStop]);
  static Uint8List encodeStatus() => _cmd([subStatus]);
}

enum MeshFwKind { staged, nodeBegin, nodeProgress, nodeDone, nodeFail, runEnd }

enum MeshFwFail {
  none,
  noImage,
  busy,
  noAnswer,
  refused,
  stalled,
  stopped,
  args;

  static MeshFwFail of(int code) => code > 0 && code < MeshFwFail.values.length ? MeshFwFail.values[code] : MeshFwFail.none;

  String get text => switch (this) {
        MeshFwFail.none => '',
        MeshFwFail.noImage => 'no image staged on the manager',
        MeshFwFail.busy => 'the manager is already sending',
        MeshFwFail.noAnswer => 'no answer from the node',
        MeshFwFail.refused => 'the node refused or rejected the image',
        MeshFwFail.stalled => 'the transfer stalled',
        MeshFwFail.stopped => 'stopped',
        MeshFwFail.args => 'the manager refused the request',
      };
}

class MeshFwEvent {
  const MeshFwEvent({
    required this.kind,
    required this.index,
    required this.count,
    required this.nodeId,
    required this.aux,
    required this.recv,
    required this.total,
    required this.imageSize,
    required this.imageCrc,
  });

  final MeshFwKind kind;
  final int index;
  final int count;
  final String nodeId;
  final int aux;
  final int recv;
  final int total;
  final int imageSize;
  final int imageCrc;

  bool get staged => kind == MeshFwKind.staged && index == 1;
  bool get running => kind == MeshFwKind.staged && count == 1;
  MeshFwFail get fail => MeshFwFail.of(aux);

  static MeshFwEvent? decode(List<int> d) {
    if (d.length < 13 || d[0] != MeshFwProtocol.opcode || d[1] >= MeshFwKind.values.length) return null;
    final bd = ByteData.sublistView(Uint8List.fromList(d));
    final kind = MeshFwKind.values[d[1]];
    return MeshFwEvent(
      kind: kind,
      index: d[2],
      count: d[3],
      nodeId: kind == MeshFwKind.staged ? '' : String.fromCharCodes(d.sublist(4, 8)).trim(),
      aux: d[8],
      recv: kind == MeshFwKind.staged ? 0 : bd.getUint16(9, Endian.little),
      total: kind == MeshFwKind.staged ? 0 : bd.getUint16(11, Endian.little),
      imageSize: kind == MeshFwKind.staged ? bd.getUint32(4, Endian.little) : 0,
      imageCrc: kind == MeshFwKind.staged ? bd.getUint32(9, Endian.little) : 0,
    );
  }
}
