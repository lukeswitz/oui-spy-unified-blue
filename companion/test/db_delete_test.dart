// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/db/app_database.dart';

void main() {
  test('deleteFiles removes the database and its WAL and SHM files', () async {
    final dir = await Directory.systemTemp.createTemp('ouispy_del');
    addTearDown(() => dir.delete(recursive: true));
    final db = '${dir.path}/oui_spy.db';
    for (final ext in ['', '-wal', '-shm']) {
      await File('$db$ext').writeAsString('x');
    }
    await File('${dir.path}/keep.txt').writeAsString('x');
    await AppDatabase.deleteFiles(db);
    for (final ext in ['', '-wal', '-shm']) {
      expect(File('$db$ext').existsSync(), isFalse, reason: ext);
    }
    expect(File('${dir.path}/keep.txt').existsSync(), isTrue);
  });

  test('deleteFiles with nothing on disk does not throw', () async {
    final dir = await Directory.systemTemp.createTemp('ouispy_del');
    addTearDown(() => dir.delete(recursive: true));
    await AppDatabase.deleteFiles('${dir.path}/oui_spy.db');
  });
}
