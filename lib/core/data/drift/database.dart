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
/// A fresh install creates the schema at version 1 (no legacy migrations); the
/// schema is owned by the desktop app and is frozen from this app's perspective
/// (see `tables.dart` and the Turso compatibility contract in `PLAN.md`).
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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // SQLite has foreign keys off by default; the reference schema relies on
      // `ON DELETE CASCADE`, so enable enforcement for every connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
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
