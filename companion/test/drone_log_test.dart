// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/drone_flights.dart';
import 'package:oui_spy/core/drone_log.dart';

DroneReport _r(DateTime ts, {String id = 'SERIAL1', double lat = 10.0}) =>
    DroneReport(ts: ts, id: id, mac: 'AA:BB:CC:DD:EE:FF', lat: lat, lon: 20.0, height: 30);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dronelog'));
  tearDown(() => dir.deleteSync(recursive: true));

  DroneLog make({DateTime? now, int keepDays = 90}) => DroneLog(
        dir: () async => dir,
        now: () => now ?? DateTime(2026, 1, 10, 12),
        flushDelay: const Duration(hours: 1),
        keepDays: keepDays,
      );

  test('reports are written per day and read back in time order', () async {
    final log = make();
    log.add(_r(DateTime(2026, 1, 9, 23, 59, 50)));
    log.add(_r(DateTime(2026, 1, 10, 0, 0, 10), lat: 10.1));
    await log.flush();
    expect(dir.listSync().map((f) => f.path.split('/').last).toSet(),
        {'2026-01-09.jsonl', '2026-01-10.jsonl'});
    final rows = await make().query();
    expect(rows.map((r) => r.lat), [10.0, 10.1]);
    log.dispose();
  });

  test('a drone reporting faster than the minimum gap is logged once', () async {
    final log = make();
    final t = DateTime(2026, 1, 10, 8);
    log.add(_r(t));
    log.add(_r(t.add(const Duration(milliseconds: 500))));
    log.add(_r(t.add(const Duration(seconds: 3))));
    log.add(_r(t.add(const Duration(milliseconds: 500)), id: 'OTHER'));
    expect((await log.query()).length, 3);
    log.dispose();
  });

  test('query bounds filter by time, including inside a day', () async {
    final log = make();
    for (var h = 8; h < 12; h++) {
      log.add(_r(DateTime(2026, 1, 10, h)));
    }
    final rows = await log.query(from: DateTime(2026, 1, 10, 9, 30), to: DateTime(2026, 1, 10, 10, 30));
    expect(rows.map((r) => r.ts.hour), [10]);
    log.dispose();
  });

  test('days older than the retention are deleted on the first flush', () async {
    File('${dir.path}/2025-01-01.jsonl').writeAsStringSync('{"ts":1,"id":"A","mac":"M"}\n');
    final log = make(keepDays: 30);
    log.add(_r(DateTime(2026, 1, 10, 8)));
    await log.flush();
    expect(File('${dir.path}/2025-01-01.jsonl').existsSync(), isFalse);
    expect(File('${dir.path}/2026-01-10.jsonl').existsSync(), isTrue);
    log.dispose();
  });

  test('an unreadable line is skipped and the rest are read', () async {
    File('${dir.path}/2026-01-10.jsonl').writeAsStringSync(
        'not json\n${jsonEncode(_r(DateTime(2026, 1, 10, 8)).toJson())}\n');
    final log = make();
    log.add(_r(DateTime(2026, 1, 10, 9)));
    final rows = await log.query();
    expect(rows.map((r) => r.ts.hour), [8, 9]);
    log.dispose();
  });
}
