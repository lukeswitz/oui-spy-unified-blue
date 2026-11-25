// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/ota/firmware_image.dart';
import 'package:oui_spy/core/ota/mesh_fw_protocol.dart';
import 'package:oui_spy/core/ota/ota_service.dart';

enum NodeFit {
  current('Current'),
  older('Older'),
  otherBoard('Other board'),
  unknownBuild('Build unknown');

  const NodeFit(this.label);
  final String label;
}

class NodeFitResult {
  const NodeFitResult(this.fit, this.why);
  final NodeFit fit;
  final String why;
  bool get canSend => fit != NodeFit.otherBoard;
}

/// Current when the node already runs this image's build, Older when it runs any other build (even a newer
/// one), Other board when the image cannot go on it, Build unknown when the node or the image names no build.
NodeFitResult nodeFit(FirmwareImage image, {required String? board, required String? fwVersion}) {
  if (image.role == 'mgr') {
    return const NodeFitResult(NodeFit.otherBoard, 'this is a manager build');
  }
  final chip = nodeChipId(board);
  if (chip != null && chip != image.chipId) {
    return NodeFitResult(NodeFit.otherBoard, 'the image is for an ${image.chip}, the node is ${chipName(chip)}');
  }
  final imageBoard = image.board;
  if (imageBoard != null && board != null && board.isNotEmpty && imageBoard != board) {
    return NodeFitResult(NodeFit.otherBoard, 'the image is built for $imageBoard, the node is $board');
  }
  final slot = nodeSlotBytes(board);
  if (slot != null && image.size > slot) {
    return NodeFitResult(NodeFit.otherBoard, '${image.size} bytes is more than its app slot ($slot)');
  }
  if (board == null || board.isEmpty || chip == null) {
    return const NodeFitResult(NodeFit.unknownBuild, 'the node has not said which board it is');
  }
  final have = parseImageVersion(fwVersion);
  final want = image.version;
  if (have == null || want == null) {
    return const NodeFitResult(NodeFit.unknownBuild, 'the node or the image names no build');
  }
  final same = have.length == want.length && [for (var i = 0; i < have.length; i++) have[i] == want[i]].every((e) => e);
  return same
      ? const NodeFitResult(NodeFit.current, 'it already runs this build')
      : const NodeFitResult(NodeFit.older, 'it runs another build');
}

enum MeshFwStep { idle, staging, sending, finished }

enum NodeRunState { waiting, sending, done, unconfirmed, failed, stopped }

class NodeRun {
  NodeRun(this.id);
  final String id;
  NodeRunState state = NodeRunState.waiting;
  int recv = 0;
  int total = 0;
  String reason = '';
  DateTime? beganAt;
  DateTime? firstDataAt;
  DateTime? lastDataAt;

  double get fraction => total == 0 ? 0 : (recv / total).clamp(0.0, 1.0);

  /// Kilobits a second over the air since the first chunk arrived.
  double? kbps(int imageSize, DateTime now) {
    final first = firstDataAt;
    if (first == null || recv == 0) return null;
    final secs = (lastDataAt ?? now).difference(first).inMilliseconds / 1000;
    if (secs <= 0.5) return null;
    return math.min(recv * MeshFwProtocol.chunkBytes, imageSize) * 8 / 1000 / secs;
  }

  Duration? timeLeft(int imageSize, DateTime now) {
    final rate = kbps(imageSize, now);
    if (rate == null || rate <= 0 || total == 0) return null;
    final leftBytes = math.max(0, imageSize - recv * MeshFwProtocol.chunkBytes);
    return Duration(seconds: (leftBytes * 8 / 1000 / rate).ceil());
  }
}

abstract class MeshFwLink {
  Stream<MeshFwEvent> get events;
  Stream<OtaProgress> get stageProgress;
  Future<bool> stage(Uint8List image);
  Future<void> send(int version, List<String> ids);
  Future<void> stop();
  Future<void> abortStage();
  String? get stageError;
}

class BleMeshFwLink implements MeshFwLink {
  BleMeshFwLink(this._ble, this._ota);
  final BleManager _ble;
  final OtaService _ota;
  String? _lastError;

  @override
  Stream<MeshFwEvent> get events => _ble.meshFwEvents;
  @override
  Stream<OtaProgress> get stageProgress => _ota.progress.map((p) {
        if (p.phase == OtaPhase.error) _lastError = p.error;
        return p;
      });
  @override
  Future<bool> stage(Uint8List image) {
    _lastError = null;
    return _ota.stageForMesh(image);
  }

  @override
  Future<void> send(int version, List<String> ids) => _ble.meshFwSend(version, ids);
  @override
  Future<void> stop() => _ble.meshFwStop();
  @override
  Future<void> abortStage() => _ota.abort();
  @override
  String? get stageError => _lastError;
}

class MeshFirmwareController extends ChangeNotifier {
  MeshFirmwareController(this._link, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _events = _link.events.listen(_onEvent);
    _stage = _link.stageProgress.listen(_onStage);
  }

  static const Duration stallAfter = Duration(seconds: 60);

  final MeshFwLink _link;
  final DateTime Function() _clock;
  late final StreamSubscription<MeshFwEvent> _events;
  late final StreamSubscription<OtaProgress> _stage;
  Timer? _watch;

  FirmwareImage? image;
  String? imageError;
  final Set<String> picked = {};
  MeshFwStep step = MeshFwStep.idle;
  double stageFraction = 0;
  String stageNote = '';
  String? runError;
  List<NodeRun> runs = const [];
  DateTime? _lastEventAt;
  bool _disposed = false;

  bool get busy => step == MeshFwStep.staging || step == MeshFwStep.sending;
  DateTime get now => _clock();

  Future<void> load(String name, Uint8List bytes) async {
    if (busy) return;
    final r = await inspectImage(bytes, name: name);
    if (_disposed) return;
    if (r.image != null && !r.image!.signed) {
      image = null;
      imageError = 'this firmware is not signed by OUI-SPY; the nodes would refuse it';
    } else {
      image = r.image;
      imageError = r.error;
    }
    runs = const [];
    step = MeshFwStep.idle;
    runError = null;
    notifyListeners();
  }

  void toggle(String id) {
    if (busy) return;
    if (!picked.remove(id)) picked.add(id);
    notifyListeners();
  }

  void setPicked(Iterable<String> ids) {
    if (busy) return;
    picked
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  int _versionNum(FirmwareImage img) {
    final v = img.version;
    return v == null ? 0 : ((v[0] & 0xFF) << 16) | ((v[1] & 0xFF) << 8) | (v[2] & 0xFF);
  }

  Future<void> start(List<String> ids) async {
    final img = image;
    if (img == null || busy || ids.isEmpty) return;
    if (ids.length > MeshFwProtocol.maxTargets) {
      runError = 'at most ${MeshFwProtocol.maxTargets} nodes at a time';
      notifyListeners();
      return;
    }
    runs = [for (final id in ids) NodeRun(id)];
    runError = null;
    step = MeshFwStep.staging;
    stageFraction = 0;
    stageNote = 'Sending the image to the manager';
    _lastEventAt = _clock();
    notifyListeners();
    bool ok;
    try {
      ok = await _link.stage(img.bytes);
    } on Exception catch (e) {
      ok = false;
      runError = '$e';
    }
    if (_disposed) return;
    if (step != MeshFwStep.staging) return;
    if (!ok) {
      runError ??= _link.stageError ?? 'the manager did not save the image';
      step = MeshFwStep.finished;
      notifyListeners();
      return;
    }
    step = MeshFwStep.sending;
    stageNote = 'Saved on the manager';
    _lastEventAt = _clock();
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 5), (_) => checkStall());
    notifyListeners();
    try {
      await _link.send(_versionNum(img), ids);
    } on Exception catch (e) {
      _finish(error: 'could not start the send: $e');
    }
  }

  Future<void> stop() async {
    if (step == MeshFwStep.staging) {
      await _link.abortStage();
      for (final r in runs) {
        r.state = NodeRunState.stopped;
      }
      step = MeshFwStep.finished;
      runError = 'stopped before the manager had the image';
      notifyListeners();
    } else if (step == MeshFwStep.sending) {
      try {
        await _link.stop();
      } on Exception catch (e) {
        _finish(error: 'could not stop: $e');
      }
    }
  }

  void checkStall() {
    if (step != MeshFwStep.sending) return;
    final last = _lastEventAt;
    if (last == null || _clock().difference(last) < stallAfter) return;
    for (final r in runs) {
      if (r.state == NodeRunState.waiting || r.state == NodeRunState.sending) {
        r.state = NodeRunState.failed;
        r.reason = 'no word from the manager';
      }
    }
    _finish(error: 'no word from the manager for ${stallAfter.inSeconds} s');
  }

  void _finish({String? error}) {
    _watch?.cancel();
    _watch = null;
    step = MeshFwStep.finished;
    if (error != null) runError = error;
    notifyListeners();
  }

  void _onStage(OtaProgress p) {
    if (step != MeshFwStep.staging) return;
    if (p.phase == OtaPhase.uploading || p.phase == OtaPhase.verifying) {
      stageFraction = p.fraction;
      stageNote = p.phase == OtaPhase.verifying ? 'The manager checks and saves it' : 'Sending the image to the manager';
      notifyListeners();
    }
  }

  NodeRun? _run(String id) {
    for (final r in runs) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _onEvent(MeshFwEvent e) {
    if (step != MeshFwStep.sending) return;
    _lastEventAt = _clock();
    switch (e.kind) {
      case MeshFwKind.staged:
        return;
      case MeshFwKind.nodeBegin:
        final r = _run(e.nodeId);
        if (r == null) return;
        r.state = NodeRunState.sending;
        r.total = e.total;
        r.recv = 0;
        r.beganAt = _clock();
      case MeshFwKind.nodeProgress:
        final r = _run(e.nodeId);
        if (r == null) return;
        r.state = NodeRunState.sending;
        r.total = e.total;
        if (e.recv > r.recv || r.recv == 0) {
          if (e.recv > 0) r.firstDataAt ??= _clock();
          r.recv = e.recv;
          r.lastDataAt = _clock();
        }
      case MeshFwKind.nodeDone:
        final r = _run(e.nodeId);
        if (r == null) return;
        r.state = e.aux == 1 ? NodeRunState.unconfirmed : NodeRunState.done;
        r.recv = r.total;
      case MeshFwKind.nodeFail:
        final r = _run(e.nodeId);
        if (r == null) return;
        r.state = e.fail == MeshFwFail.stopped ? NodeRunState.stopped : NodeRunState.failed;
        r.reason = e.fail.text;
      case MeshFwKind.runEnd:
        if (e.count == 0) {
          for (final r in runs) {
            r.state = NodeRunState.failed;
            r.reason = e.fail.text;
          }
          _finish(error: e.fail.text);
          return;
        }
        _finish();
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watch?.cancel();
    _events.cancel();
    _stage.cancel();
    super.dispose();
  }
}

final meshFirmwareProvider = ChangeNotifierProvider<MeshFirmwareController>((ref) {
  return MeshFirmwareController(BleMeshFwLink(ref.read(bleManagerProvider), ref.read(otaServiceProvider)));
});
