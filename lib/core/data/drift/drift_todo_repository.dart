import 'package:drift/drift.dart';

import '../../models/todo.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../remote_write_sink.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';
import 'write_mirror.dart';

/// Drift-backed [TodoRepository].
///
/// Mirrors `MockTodoRepository`: watch order is position then creation time,
/// every write stamps `updated_at` from [nowIso] (never a DB default), and
/// `archived` crosses the boundary as 0/1.
class DriftTodoRepository implements TodoRepository {
  /// Creates a repository over [database].
  ///
  /// [writeSink] mirrors every write to the remote store; it is always
  /// installed at runtime and no-ops while sync is unconfigured.
  DriftTodoRepository(this._database, {this.writeSink});

  final AppDatabase _database;

  /// Mirrors writes to the remote store; always installed at runtime, no-op
  /// while sync is unconfigured.
  final RemoteWriteSink? writeSink;

  @override
  Stream<List<Todo>> watchAll() => _watch(
    _database.select(_database.todos)
      ..where((t) => t.archived.equals(0))
      ..orderBy(_order),
  );

  @override
  Stream<List<Todo>> watchByStatus(TodoStatus status) => _watch(
    _database.select(_database.todos)
      ..where((t) => t.archived.equals(0) & t.status.equals(status.wire))
      ..orderBy(_order),
  );

  @override
  Stream<List<Todo>> watchArchived() => _watch(
    _database.select(_database.todos)
      ..where((t) => t.archived.equals(1))
      ..orderBy(_order),
  );

  @override
  Future<Todo?> getById(String id) async {
    final row = await (_database.select(
      _database.todos,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : todoFromRow(row);
  }

  @override
  Future<Todo> create({
    required String title,
    String? description,
    TodoStatus status = TodoStatus.todo,
    TodoPriority? priority,
    String? dueDate,
    int position = 0,
  }) async {
    final now = nowIso();
    final todo = Todo(
      id: newId(),
      title: title,
      description: description,
      status: status,
      priority: priority,
      dueDate: dueDate,
      position: position,
      createdAt: now,
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.todos)
          .insert(
            TodosCompanion(
              id: Value(todo.id),
              title: Value(todo.title),
              description: Value(todo.description),
              status: Value(todo.status.wire),
              priority: Value(todo.priority?.wire),
              dueDate: Value(todo.dueDate),
              position: Value(todo.position),
              archived: Value(flagToInt(todo.archived)),
              createdAt: Value(todo.createdAt),
              updatedAt: Value(todo.updatedAt),
            ),
          );
      // Mirror the create at mutation time so it reaches the cloud without
      // waiting for a sync. Enqueued in the same transaction so the queued
      // intent commits atomically with the local insert.
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.todos,
        id: todo.id,
      );
    });
    return todo;
  }

  @override
  Future<void> update(Todo todo) async {
    // `created_at` is intentionally absent so the stored value is preserved,
    // matching the mock (which reuses the existing createdAt).
    await _database.transaction(() async {
      await (_database.update(
        _database.todos,
      )..where((t) => t.id.equals(todo.id))).write(
        TodosCompanion(
          title: Value(todo.title),
          description: Value(todo.description),
          status: Value(todo.status.wire),
          priority: Value(todo.priority?.wire),
          dueDate: Value(todo.dueDate),
          position: Value(todo.position),
          archived: Value(flagToInt(todo.archived)),
          updatedAt: Value(nowIso()),
        ),
      );
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.todos,
        id: todo.id,
      );
    });
  }

  @override
  Future<void> setStatus(String id, TodoStatus status) =>
      _touch(id, TodosCompanion(status: Value(status.wire)));

  @override
  Future<void> archive(String id) =>
      _touch(id, TodosCompanion(archived: const Value(1)));

  @override
  Future<void> restore(String id) =>
      _touch(id, TodosCompanion(archived: const Value(0)));

  @override
  Future<void> delete(String id) async {
    // Enqueue the mirror inside the transaction so the queued delete commits
    // atomically with the local delete: a sync pull that runs after the local
    // change is visible also sees the queued intent and suppresses the row.
    await _database.transaction(() async {
      await (_database.delete(
        _database.todos,
      )..where((t) => t.id.equals(id))).go();
      await writeSink?.recordDelete(RemoteTables.todos, id);
    });
  }

  @override
  Future<void> updatePositions(
    List<({String id, int position})> updates,
  ) async {
    await _database.transaction(() async {
      final now = nowIso();
      for (final update in updates) {
        await (_database.update(
          _database.todos,
        )..where((t) => t.id.equals(update.id))).write(
          TodosCompanion(
            position: Value(update.position),
            updatedAt: Value(now),
          ),
        );
        await mirrorUpsert(
          _database,
          writeSink,
          table: RemoteTables.todos,
          id: update.id,
        );
      }
    });
  }

  Future<void> _touch(String id, TodosCompanion companion) async {
    await _database.transaction(() async {
      await (_database.update(_database.todos)..where((t) => t.id.equals(id)))
          .write(companion.copyWith(updatedAt: Value(nowIso())));
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.todos,
        id: id,
      );
    });
  }

  Stream<List<Todo>> _watch(
    SimpleSelectStatement<$TodosTable, TodoRow> query,
  ) => query.watch().map((rows) => [for (final row in rows) todoFromRow(row)]);

  static List<OrderingTerm Function($TodosTable)> get _order => [
    (t) => OrderingTerm.asc(t.position),
    (t) => OrderingTerm.asc(t.createdAt),
  ];
}
