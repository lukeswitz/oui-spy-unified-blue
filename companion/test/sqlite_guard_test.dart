import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/sqlite_guard.dart';

void main() {
  test('guarded sqlite3 drops drift Dart SQL builtins and keeps queries working', () async {
    final raw = guardedSqlite3().openInMemory();
    final db = DatabaseConnection(NativeDatabase.opened(raw));
    final exec = db.executor;
    await exec.ensureOpen(_NoUser());
    expect((await exec.runSelect('SELECT 1 + 1 AS v', const [])).single['v'], 2);
    await expectLater(exec.runSelect('SELECT current_time_millis() AS v', const []), throwsA(anything));
    final plain = DatabaseConnection(NativeDatabase.memory()).executor;
    await plain.ensureOpen(_NoUser());
    expect((await plain.runSelect('SELECT current_time_millis() AS v', const [])).single['v'], isA<int>());
    await plain.close();
    await exec.runCustom('CREATE TABLE t (a TEXT)');
    await exec.runInsert('INSERT INTO t VALUES (?)', ['x']);
    expect((await exec.runSelect('SELECT count(*) AS n FROM t', const [])).single['n'], 1);
    await exec.close();
  });
}

class _NoUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
