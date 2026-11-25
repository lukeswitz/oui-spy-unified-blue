// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ota/firmware_image.dart';
import 'package:oui_spy/core/ota/mesh_firmware.dart';
import 'package:oui_spy/core/ota/mesh_fw_protocol.dart';
import 'package:oui_spy/core/ota/ota_service.dart';

Uint8List fakeImage({int chip = chipIdEsp32S3, String version = '0.7.0', int size = 70000, bool desc = true, int magic = 0xE9}) {
  final b = Uint8List(size);
  b[0] = magic;
  b[12] = chip & 0xFF;
  b[13] = chip >> 8;
  if (desc) {
    ByteData.sublistView(b).setUint32(32, 0xABCD5432, Endian.little);
    b.setRange(48, 48 + version.length, version.codeUnits);
    const project = 'oui-spy';
    b.setRange(80, 80 + project.length, project.codeUnits);
  }
  return b;
}

FirmwareImage image({String name = 'oui-spy-node-xiao_s3-v0.7.0.bin', int chip = chipIdEsp32S3, int size = 70000}) =>
    inspectImageStructure(fakeImage(chip: chip, size: size), name: name).image!;

Uint8List ev(int kind, {int idx = 0, int count = 1, String id = 'A1B2', int aux = 0, int recv = 0, int total = 0}) {
  final b = ByteData(13);
  b.setUint8(0, MeshFwProtocol.opcode);
  b.setUint8(1, kind);
  b.setUint8(2, idx);
  b.setUint8(3, count);
  for (var i = 0; i < 4; i++) {
    b.setUint8(4 + i, id.codeUnitAt(i));
  }
  b.setUint8(8, aux);
  b.setUint16(9, recv, Endian.little);
  b.setUint16(11, total, Endian.little);
  return b.buffer.asUint8List();
}

class FakeLink implements MeshFwLink {
  final events$ = StreamController<MeshFwEvent>.broadcast();
  final stage$ = StreamController<OtaProgress>.broadcast();
  bool stageOk = true;
  Completer<bool>? stageGate;
  List<String>? sentIds;
  int? sentVersion;
  bool stopped = false;
  bool aborted = false;

  @override
  Stream<MeshFwEvent> get events => events$.stream;
  @override
  Stream<OtaProgress> get stageProgress => stage$.stream;
  @override
  Future<bool> stage(Uint8List image) => stageGate?.future ?? Future.value(stageOk);
  @override
  Future<void> send(int version, List<String> ids) async {
    sentIds = ids;
    sentVersion = version;
  }

  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> abortStage() async => aborted = true;
  @override
  String? get stageError => 'refused';

  void emit(Uint8List raw) => events$.add(MeshFwEvent.decode(raw)!);
}

void main() {
  group('image inspection', () {
    test('reads chip, version, project, size and SHA-256', () {
      final r = inspectImageStructure(fakeImage(), name: 'oui-spy-node-xiao_s3-v0.7.0.bin');
      final img = r.image!;
      expect(img.chipId, chipIdEsp32S3);
      expect(img.chip, 'ESP32-S3');
      expect(img.descVersion, '0.7.0');
      expect(img.projectName, 'oui-spy');
      expect(img.board, 'xiao_s3');
      expect(img.role, 'node');
      expect(img.nameVersion, '0.7.0');
      expect(img.sha256Hex, hasLength(64));
      expect(img.size, 70000);
    });

    test('rejects what is not an app image', () {
      expect(inspectImageStructure(Uint8List(100)).error, contains('plausible'));
      expect(inspectImageStructure(fakeImage(magic: 0x00)).error, contains('not an ESP32 application image'));
      expect(inspectImageStructure(fakeImage(desc: false)).error, contains('app description'));
    });

    test('version falls back to the app description', () {
      final img = inspectImageStructure(fakeImage(version: '1.2.3'), name: 'firmware.bin').image!;
      expect(img.board, isNull);
      expect(img.version, [1, 2, 3]);
    });

    test('node boards map to their chip and slot', () {
      expect(nodeChipId('xiao_c5'), chipIdEsp32C5);
      expect(nodeChipId('stickc_plus2'), chipIdEsp32);
      expect(nodeChipId('nope'), isNull);
      expect(nodeSlotBytes('tdongle_s3'), 0x300000);
      expect(nodeSlotBytes('stickc'), 0x140000);
    });
  });

  group('node fit', () {
    test('current, older and unknown', () {
      final img = image();
      expect(nodeFit(img, board: 'xiao_s3', fwVersion: '0.7.0').fit, NodeFit.current);
      expect(nodeFit(img, board: 'xiao_s3', fwVersion: '0.6.9').fit, NodeFit.older);
      expect(nodeFit(img, board: 'xiao_s3', fwVersion: '9.0.0').fit, NodeFit.older);
      expect(nodeFit(img, board: 'xiao_s3', fwVersion: null).fit, NodeFit.unknownBuild);
      expect(nodeFit(img, board: null, fwVersion: '0.7.0').fit, NodeFit.unknownBuild);
    });

    test('other board by chip, by name, by size and by role', () {
      expect(nodeFit(image(chip: chipIdEsp32C5), board: 'xiao_s3', fwVersion: '0.6.0').fit, NodeFit.otherBoard);
      expect(nodeFit(image(), board: 'tdongle_s3', fwVersion: '0.6.0').fit, NodeFit.otherBoard);
      expect(nodeFit(image(name: 'oui-spy-node-stickc-v0.7.0.bin', chip: chipIdEsp32, size: 0x150000), board: 'stickc', fwVersion: '0.6.0').fit,
          NodeFit.otherBoard);
      expect(nodeFit(image(name: 'oui-spy-mgr-xiao_s3-v0.7.0.bin'), board: 'xiao_s3', fwVersion: '0.6.0').fit, NodeFit.otherBoard);
      expect(nodeFit(image(), board: 'xiao_s3', fwVersion: '0.6.0').canSend, isTrue);
      expect(nodeFit(image(chip: chipIdEsp32C5), board: 'xiao_s3', fwVersion: '0.6.0').canSend, isFalse);
    });
  });

  group('protocol', () {
    test('send command layout', () {
      final c = MeshFwProtocol.encodeSend(0x000701, ['A1B2', 'C3D4']);
      expect(c, [0x15, 0xC0, 0xDE, 0x01, 0x01, 0x07, 0x00, 0x00, 2, ...'A1B2'.codeUnits, ...'C3D4'.codeUnits]);
      expect(MeshFwProtocol.encodeStop(), [0x15, 0xC0, 0xDE, 0x02]);
      expect(() => MeshFwProtocol.encodeSend(1, []), throwsArgumentError);
      expect(() => MeshFwProtocol.encodeSend(1, ['ABC']), throwsArgumentError);
    });

    test('events decode', () {
      final p = MeshFwEvent.decode(ev(2, idx: 1, count: 3, id: 'A1B2', aux: 1, recv: 300, total: 400))!;
      expect(p.kind, MeshFwKind.nodeProgress);
      expect(p.nodeId, 'A1B2');
      expect((p.index, p.count, p.recv, p.total), (1, 3, 300, 400));
      final s = ByteData(13)
        ..setUint8(0, 0x15)
        ..setUint8(2, 1)
        ..setUint32(4, 123456, Endian.little)
        ..setUint32(9, 0xDEADBEEF, Endian.little);
      final st = MeshFwEvent.decode(s.buffer.asUint8List())!;
      expect(st.staged, isTrue);
      expect(st.imageSize, 123456);
      expect(st.imageCrc, 0xDEADBEEF);
      expect(MeshFwEvent.decode([0x15, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), isNull);
      expect(MeshFwEvent.decode([0x08, 0]), isNull);
    });
  });

  group('controller', () {
    late FakeLink link;
    late DateTime t;
    late MeshFirmwareController c;
    setUp(() {
      link = FakeLink();
      t = DateTime(2026, 1, 1);
      c = MeshFirmwareController(link, clock: () => t);
      c.image = image();
    });
    tearDown(() {
      c.dispose();
    });

    test('stages once, then sends one node at a time with rate and time left', () async {
      await c.start(['A1B2', 'C3D4']);
      expect(c.step, MeshFwStep.sending);
      expect(link.sentIds, ['A1B2', 'C3D4']);
      expect(link.sentVersion, 0x000700);
      expect(c.runs.map((r) => r.state), [NodeRunState.waiting, NodeRunState.waiting]);

      link.emit(ev(1, idx: 0, count: 2, id: 'A1B2', total: 365));
      await Future<void>.delayed(Duration.zero);
      expect(c.runs[0].state, NodeRunState.sending);
      expect(c.runs[1].state, NodeRunState.waiting);

      link.emit(ev(2, idx: 0, count: 2, id: 'A1B2', recv: 50, total: 365));
      await Future<void>.delayed(Duration.zero);
      t = t.add(const Duration(seconds: 4));
      link.emit(ev(2, idx: 0, count: 2, id: 'A1B2', recv: 150, total: 365));
      await Future<void>.delayed(Duration.zero);
      final r = c.runs[0];
      final kbps = r.kbps(c.image!.size, t)!;
      expect(kbps, closeTo(150 * 192 * 8 / 1000 / 4, 0.01));
      expect(r.timeLeft(c.image!.size, t), isNotNull);
      expect(r.fraction, closeTo(150 / 365, 0.001));

      link.emit(ev(3, idx: 0, count: 2, id: 'A1B2', total: 365, recv: 365));
      link.emit(ev(1, idx: 1, count: 2, id: 'C3D4', total: 365));
      link.emit(ev(4, idx: 1, count: 2, id: 'C3D4', aux: 3));
      link.emit(ev(5, idx: 2, count: 2, id: '    ', aux: 1, recv: 1));
      await Future<void>.delayed(Duration.zero);
      expect(c.runs[0].state, NodeRunState.done);
      expect(c.runs[1].state, NodeRunState.failed);
      expect(c.runs[1].reason, 'no answer from the node');
      expect(c.step, MeshFwStep.finished);
    });

    test('an unconfirmed finish is kept apart from done', () async {
      await c.start(['A1B2']);
      link.emit(ev(3, id: 'A1B2', aux: 1, total: 10, recv: 10));
      await Future<void>.delayed(Duration.zero);
      expect(c.runs[0].state, NodeRunState.unconfirmed);
    });

    test('a refused staging stops the run and keeps the reason', () async {
      link.stageOk = false;
      await c.start(['A1B2']);
      expect(c.step, MeshFwStep.finished);
      expect(c.runError, 'refused');
      expect(link.sentIds, isNull);
    });

    test('the manager refusing the send fails every row', () async {
      await c.start(['A1B2']);
      link.emit(ev(5, count: 0, id: '    ', aux: 1));
      await Future<void>.delayed(Duration.zero);
      expect(c.step, MeshFwStep.finished);
      expect(c.runs[0].state, NodeRunState.failed);
      expect(c.runs[0].reason, 'no image staged on the manager');
    });

    test('stop while sending asks the manager; stopped rows show stopped', () async {
      await c.start(['A1B2', 'C3D4']);
      await c.stop();
      expect(link.stopped, isTrue);
      link.emit(ev(4, idx: 0, count: 2, id: 'A1B2', aux: 6));
      link.emit(ev(4, idx: 1, count: 2, id: 'C3D4', aux: 6));
      link.emit(ev(5, idx: 2, count: 2, id: '    ', aux: 0, recv: 2));
      await Future<void>.delayed(Duration.zero);
      expect(c.runs.map((r) => r.state), [NodeRunState.stopped, NodeRunState.stopped]);
      expect(c.step, MeshFwStep.finished);
    });

    test('stop while staging aborts the upload', () async {
      link.stageGate = Completer<bool>();
      final run = c.start(['A1B2']);
      await Future<void>.delayed(Duration.zero);
      expect(c.step, MeshFwStep.staging);
      await c.stop();
      expect(link.aborted, isTrue);
      expect(c.step, MeshFwStep.finished);
      link.stageGate!.complete(false);
      await run;
      expect(link.sentIds, isNull);
    });

    test('silence from the manager fails the waiting nodes', () async {
      await c.start(['A1B2']);
      t = t.add(MeshFirmwareController.stallAfter + const Duration(seconds: 1));
      c.checkStall();
      expect(c.step, MeshFwStep.finished);
      expect(c.runs[0].state, NodeRunState.failed);
    });

    test('at most eight nodes at a time', () async {
      await c.start([for (var i = 0; i < 9; i++) 'A00$i']);
      expect(c.step, MeshFwStep.idle);
      expect(c.runError, contains('at most'));
    });
  });
}
