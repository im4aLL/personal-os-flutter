import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// The app's local SQLite database.
///
/// The syncable schema is owned by the desktop app and is frozen from this
/// app's perspective (see `tables.dart` and the Turso compatibility contract in
/// `PLAN.md`). The one local-only addition is the `pending_writes` outbound
/// queue (schema version 3), created via raw SQL in the migration so it never
/// appears in the frozen schema or the conformance guard.
@DriftDatabase(
  tables: [
    Todos,
    AppSettings,
    Notes,
    NoteTags,
    Links,
    LinkTags,
    WorkLogs,
    WorkLogTags,
    Projects,
    ProjectPhases,
    WorkItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens (lazily) the on-device database file.
  AppDatabase() : super(_openConnection());

  /// Creates a database over a caller-supplied [executor], for tooling and
  /// previews.
  AppDatabase.forTesting(super.executor);

  /// Schema version 3 replaced the local-only `pending_deletes` table (v2)
  /// with the local-only `pending_writes` outbound queue.
  ///
  /// Fresh installs create it in [MigrationStrategy.onCreate]; an existing
  /// database creates it in [MigrationStrategy.onUpgrade].
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPendingWritesTable();
    },
    onUpgrade: (m, from, to) async {
      await _createPendingWritesTable();
      // A dev device may have run the intermediate version-2 build with the
      // narrower `pending_deletes` queue; drop it so only `pending_writes`
      // remains. Nothing has shipped, so the queued deletes are discarded.
      await customStatement('DROP TABLE IF EXISTS pending_deletes');
    },
    beforeOpen: (details) async {
      // SQLite has foreign keys off by default; the reference schema relies on
      // `ON DELETE CASCADE`, so enable enforcement for every connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Creates the local-only `pending_writes` queue table via raw SQL.
  ///
  /// This table is deliberately NOT declared in `tables.dart` (so it never
  /// reaches `database.g.dart` or the remote schema): it is device-local state
  /// that queues outbound writes for the sync engine. It must never be created
  /// on the remote, and the schema conformance guard must never see it.
  ///
  /// One row is one latest intent per `(table_name, row_id)`; `statements` is a
  /// JSON array of `{"sql", "args"}` generated from internal fixed SQL.
  Future<void> _createPendingWritesTable() => customStatement(
    'CREATE TABLE IF NOT EXISTS pending_writes ('
    'seq INTEGER PRIMARY KEY AUTOINCREMENT, '
    'kind TEXT NOT NULL, '
    'table_name TEXT NOT NULL, '
    'row_id TEXT NOT NULL, '
    'statements TEXT NOT NULL, '
    'UNIQUE (table_name, row_id))',
  );
}

/// The file name of the on-device database.
const String databaseFileName = 'personal_os.sqlite';

/// Opens the database lazily against a stable application-support directory.
///
/// Lazy so the async `path_provider` lookup and file open happen on first use
/// rather than during provider construction.
QueryExecutor _openConnection() => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  final file = File(p.join(directory.path, databaseFileName));
  return NativeDatabase.createInBackground(file);
});

/// The shared [AppDatabase], constructed lazily and closed on scope disposal.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});
