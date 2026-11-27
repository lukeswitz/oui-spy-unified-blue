// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/melody_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('firmware ops: indexed SYNC layout, silent has zero notes', () async {
    final s = MelodyState();
    await Future<void>.delayed(Duration.zero);
    final axon = kAlertSlots.firstWhere((e) => e.engine == 0 && e.method == 8);
    final flock = kAlertSlots.firstWhere((e) => e.engine == 1);
    await s.assign(axon, 'lubdub');
    await s.assign(flock, melodySilent);

    final ops = s.serializeForFirmware();
    final n = kAlertSlots.length;
    expect(ops.length, n);
    expect(ops[kAlertSlots.indexOf(axon)], [melodyOpSync, kAlertSlots.indexOf(axon), n, 0, 8, 2, 72, 6, 4, 67, 11, 3]);
    expect(ops[kAlertSlots.indexOf(flock)], [melodyOpSync, kAlertSlots.indexOf(flock), n, 1, melodyAny, 0]);
    expect(ops[0], [melodyOpSync, 0, n, melodyAny, melodyAny, 3, 88, 4, 2, 92, 4, 2, 95, 4, 2]);
    expect(ops.every((o) => o.length <= 32), isTrue);
    expect(n <= 24, isTrue);
  });

  test('preview op caps at 8 notes and encodes 10ms units', () {
    final notes = List.generate(10, (i) => const MelodyNote(69, 250, 30));
    final op = MelodyState.previewOp(notes);
    expect(op[0], melodyOpPreview);
    expect(op[1], melodyMaxNotes);
    expect(op.length, 2 + melodyMaxNotes * 3);
    expect(op.sublist(2, 5), [69, 25, 3]);
  });

  test('Default resolves like the board: All other alerts, then the board sound', () async {
    final s = MelodyState();
    await Future<void>.delayed(Duration.zero);
    AlertSlot slot(int e, int m) => kAlertSlots.firstWhere((x) => x.engine == e && x.method == m);
    final other = slot(melodyAny, melodyAny);
    final flipper = slot(0, 3);
    final heartbeat = slot(melodyEngineAxon, 1);

    expect(s.defaultFor(flipper).name, 'Chime');
    expect(s.defaultFor(flipper).notes.map((n) => n.midi), [88, 92, 95]);
    expect(s.defaultFor(slot(0, 8)).name, 'Siren');
    expect(s.defaultFor(heartbeat).name, 'Lub-dub');

    await s.assign(other, 'siren');
    expect(s.defaultFor(flipper).name, 'Siren');
    expect(s.defaultFor(slot(1, melodyAny)).name, 'Siren');
    expect(s.defaultFor(heartbeat).name, 'Lub-dub');
    expect(s.defaultFor(other).name, 'Chime');

    await s.assign(other, melodySilent);
    expect(s.defaultFor(flipper).notes, isEmpty);
  });

  test('deleting a melody drops its assignments', () async {
    final s = MelodyState();
    await Future<void>.delayed(Duration.zero);
    await s.saveMelody(Melody(id: 'u1', name: 'x', notes: const [MelodyNote(60, 100, 0)]));
    await s.assign(kAlertSlots.first, 'u1');
    await s.deleteMelody('u1');
    expect(s.assignmentFor(kAlertSlots.first), isNull);
    expect(s.serializeForFirmware().first, [melodyOpSync, 0, kAlertSlots.length, melodyAny, melodyAny, 3, 88, 4, 2, 92, 4, 2, 95, 4, 2]);
  });
}
