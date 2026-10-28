import 'dart:ffi';

import 'package:sqlite3/sqlite3.dart';

const driftBuiltinFunctions = {
  'power', 'pow', 'sqrt', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan',
  'regexp', 'regexp_moor_ffi', 'moor_contains', 'current_time_millis',
};

Sqlite3 guardedSqlite3() => _GuardedSqlite3(sqlite3);

final class _GuardedSqlite3 implements Sqlite3 {
  _GuardedSqlite3(this._s);
  final Sqlite3 _s;

  @override
  Version get version => _s.version;

  @override
  String? get tempDirectory => _s.tempDirectory;

  @override
  set tempDirectory(String? v) => _s.tempDirectory = v;

  @override
  Database open(String filename,
          {String? vfs, OpenMode mode = OpenMode.readWriteCreate, bool uri = false, bool? mutex}) =>
      GuardedDatabase(_s.open(filename, vfs: vfs, mode: mode, uri: uri, mutex: mutex));

  @override
  Database openInMemory({String? vfs}) => GuardedDatabase(_s.openInMemory(vfs: vfs));

  @override
  Database fromPointer(Pointer<void> database) => GuardedDatabase(_s.fromPointer(database));

  @override
  Database copyIntoMemory(Database restoreFrom) => GuardedDatabase(_s.copyIntoMemory(restoreFrom));

  @override
  void ensureExtensionLoaded(SqliteExtension extension) => _s.ensureExtensionLoaded(extension);

  @override
  void registerVirtualFileSystem(VirtualFileSystem vfs, {bool makeDefault = false}) =>
      _s.registerVirtualFileSystem(vfs, makeDefault: makeDefault);

  @override
  void unregisterVirtualFileSystem(VirtualFileSystem vfs) => _s.unregisterVirtualFileSystem(vfs);
}

final class GuardedDatabase implements Database {
  GuardedDatabase(this._d);
  final Database _d;

  @override
  void createFunction({
    required String functionName,
    required ScalarFunction function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  }) {
    if (driftBuiltinFunctions.contains(functionName)) return;
    _d.createFunction(
      functionName: functionName,
      function: function,
      argumentCount: argumentCount,
      deterministic: deterministic,
      directOnly: directOnly,
      subtype: subtype,
    );
  }

  @override
  void createAggregateFunction<V>({
    required String functionName,
    required AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
    bool subtype = false,
  }) =>
      _d.createAggregateFunction<V>(
        functionName: functionName,
        function: function,
        argumentCount: argumentCount,
        deterministic: deterministic,
        directOnly: directOnly,
        subtype: subtype,
      );

  @override
  void createCollation({required String name, required CollatingFunction function}) =>
      _d.createCollation(name: name, function: function);

  @override
  Pointer<void> get handle => _d.handle;

  @override
  DatabaseConfig get config => _d.config;

  @override
  int get userVersion => _d.userVersion;

  @override
  set userVersion(int v) => _d.userVersion = v;

  @override
  int get lastInsertRowId => _d.lastInsertRowId;

  @override
  int get updatedRows => _d.updatedRows;

  @override
  // ignore: deprecated_member_use
  int getUpdatedRows() => _d.getUpdatedRows();

  @override
  Stream<SqliteUpdate> get updates => _d.updates;

  @override
  Stream<SqliteUpdate> get updatesSync => _d.updatesSync;

  @override
  VoidPredicate? get commitFilter => _d.commitFilter;

  @override
  set commitFilter(VoidPredicate? f) => _d.commitFilter = f;

  @override
  Stream<void> get commits => _d.commits;

  @override
  Stream<void> get rollbacks => _d.rollbacks;

  @override
  void execute(String sql, [List<Object?> parameters = const []]) => _d.execute(sql, parameters);

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) => _d.select(sql, parameters);

  @override
  PreparedStatement prepare(String sql, {bool persistent = false, bool vtab = true, bool checkNoTail = false}) =>
      _d.prepare(sql, persistent: persistent, vtab: vtab, checkNoTail: checkNoTail);

  @override
  List<PreparedStatement> prepareMultiple(String sql, {bool persistent = false, bool vtab = true}) =>
      _d.prepareMultiple(sql, persistent: persistent, vtab: vtab);

  @override
  Stream<double> backup(Database toDatabase, {int nPage = 5}) => _d.backup(toDatabase, nPage: nPage);

  @override
  bool get autocommit => _d.autocommit;

  @override
  void dispose() => _d.dispose();
}
