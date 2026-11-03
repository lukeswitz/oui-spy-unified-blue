import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/capture_recorder.dart';
import 'package:oui_spy/core/db/app_database.dart' hide Detection;
import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

Detection _det(String mac, int ms, {Engine engine = Engine.wardrive, String method = 'ble_adv'}) => Detection(
      id: '$mac-$ms',
      sessionId: '',
      nodeId: 'n1',
      macAddress: mac,
      engine: engine,
      method: method,
      rssi: -60,
      channel: 6,
      deviceTimestampMs: ms,
      appTimestamp: DateTime.fromMillisecondsSinceEpoch(ms),
    );

void main() {
  late AppDatabase db;
  late StreamController<Detection> feed;
  var elsewhere = false;
  var suppress = <String>{};

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    feed = StreamController<Detection>.broadcast(sync: true);
    elsewhere = false;
    suppress = {};
  });

  tearDown(() async {
    await feed.close();
    await db.close();
  });

  CaptureRecorder make() => CaptureRecorder(db, feed.stream,
      recordingElsewhere: () => elsewhere, suppressed: (d) => suppress.contains(d.macAddress));

  test('every device seen outside a session is stored in a capture session', () async {
    final r = make();
    for (var i = 0; i < 1500; i++) {
      feed.add(_det('02:00:00:00:${(i >> 8).toRadixString(16).padLeft(2, '0')}:${(i & 0xff).toRadixString(16).padLeft(2, '0')}', 1000 + i));
    }
    await r.flush();
    final s = await db.getSessionById(r.sessionId!);
    expect(s!.isWardrive, isFalse);
    expect(s.detectionCount, 1500);
    expect(s.uniqueMacCount, 1500);
    expect(s.name, startsWith('Capture '));
    expect((await db.getDetectionsForSession(r.sessionId!)).length, 1500);
    await r.dispose();
  });

  test('repeat sightings relog once per minute per device and engine', () async {
    final r = make();
    feed.add(_det('02:00:00:00:00:01', 0));
    feed.add(_det('02:00:00:00:00:01', 30000));
    feed.add(_det('02:00:00:00:00:01', 30000, engine: Engine.detector, method: 'tracker'));
    feed.add(_det('02:00:00:00:00:01', CaptureRecorder.relogEvery.inMilliseconds));
    await r.flush();
    expect((await db.getDetectionsForSession(r.sessionId!)).length, 3);
    await r.dispose();
  });

  test('nothing is written while a wardrive session records, or for suppressed devices', () async {
    final r = make();
    elsewhere = true;
    feed.add(_det('02:00:00:00:00:01', 0));
    elsewhere = false;
    suppress = {'02:00:00:00:00:02'};
    feed.add(_det('02:00:00:00:00:02', 0));
    feed.add(_det('02:00:00:00:00:03', 0));
    await r.flush();
    final rows = await db.getDetectionsForSession(r.sessionId!);
    expect(rows.map((d) => d.macAddress), ['02:00:00:00:00:03']);
    await r.dispose();
  });

  test('deleting the live capture session starts a fresh one with correct counts', () async {
    final r = make();
    feed.add(_det('02:00:00:00:00:01', 0));
    await r.flush();
    final first = r.sessionId!;
    await db.deleteSessions([first]);
    feed.add(_det('02:00:00:00:00:02', 1000));
    await r.flush();
    expect(r.sessionId, isNot(first));
    final s = await db.getSessionById(r.sessionId!);
    expect(s!.detectionCount, 1);
    expect(s.uniqueMacCount, 1);
    expect((await db.getDetectionsForSession(r.sessionId!)).map((d) => d.macAddress), ['02:00:00:00:00:02']);
    await r.dispose();
  });

  test('rows survive a failed flush and are written on the next one', () async {
    final flaky = _FailOnceDb();
    final r = CaptureRecorder(flaky, feed.stream, recordingElsewhere: () => false, suppressed: (_) => false);
    feed.add(_det('02:00:00:00:00:01', 0));
    await r.flush();
    expect(r.pending, 1);
    expect(r.rows, 0);
    await r.flush();
    expect(r.pending, 0);
    expect((await flaky.getDetectionsForSession(r.sessionId!)).length, 1);
    await r.dispose();
    await flaky.close();
  });
}

class _FailOnceDb extends AppDatabase {
  _FailOnceDb() : super.forTesting(NativeDatabase.memory());
  var _failed = false;

  @override
  Future<void> batchInsertDetections(List<DetectionsCompanion> batch) {
    if (!_failed) {
      _failed = true;
      throw StateError('disk full');
    }
    return super.batchInsertDetections(batch);
  }
}
