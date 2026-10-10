import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/drift/database.dart';

/// The `kind` values stored in `pending_writes`.
///
/// A row holds one latest intent: a delete supersedes a queued upsert or tag
/// replacement for the same `(table_name, row_id)`.
abstract final class PendingWriteKind {
  /// A hard delete of an aggregate row.
  static const String delete = 'delete';

  /// A full tag replacement for a parent row.
  static const String tags = 'tags';

  /// An upsert of a table with no `updated_at` (currently `project_phases`).
  static const String upsert = 'upsert';
}

/// One SQL statement queued for the remote, with its bound arguments.
///
/// [sql] is generated only from internal, fixed SQL; it is never built from
/// user input.
class QueuedStatement {
  /// Creates a [QueuedStatement].
  const QueuedStatement(this.sql, this.args);

  /// The SQL text to execute against the remote.
  final String sql;

  /// The bound arguments, in order.
  final List<Object?> args;
}

/// A durable outbound write: one latest intent per `(table, row)`.
class PendingWrite {
  /// Creates a [PendingWrite] from already-encoded [statementsJson].
  const PendingWrite({
    required this.kind,
    required this.table,
    required this.rowId,
    required this.statementsJson,
  });

  /// Creates a [PendingWrite], encoding [statements] to JSON.
  factory PendingWrite.of({
    required String kind,
    required String table,
    required String rowId,
    required List<QueuedStatement> statements,
  }) => PendingWrite(
    kind: kind,
    table: table,
    rowId: rowId,
    statementsJson: _encodeStatements(statements),
  );

  /// One of the [PendingWriteKind] values.
  final String kind;

  /// The table the intent targets (for tags, the parent table).
  final String table;

  /// The primary key of the affected row (for tags, the parent id).
  final String rowId;

  /// The queued statements as JSON, exactly as stored.
  ///
  /// Kept verbatim so a flush can remove the group only if it is still the one
  /// it executed (`DELETE ... AND statements = ?`), never clobbering a newer
  /// intent that replaced it in the meantime.
  final String statementsJson;

  /// The queued statements, decoded from [statementsJson].
  List<QueuedStatement> get statements => _decodeStatements(statementsJson);
}

/// A `(table, row)` key, used for suppression lookups.
class PendingWriteKey {
  /// Creates a [PendingWriteKey].
  const PendingWriteKey(this.table, this.rowId);

  /// The table name.
  final String table;

  /// The row id.
  final String rowId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingWriteKey && table == other.table && rowId == other.rowId;

  @override
  int get hashCode => Object.hash(table, rowId);

  @override
  String toString() => 'PendingWriteKey($table, $rowId)';
}

/// The queued writes that suppress pulled rows so they cannot resurrect.
class PendingWriteKeys {
  /// Creates a [PendingWriteKeys].
  const PendingWriteKeys({
    required this.deletes,
    required this.tags,
    required this.total,
  });

  /// `(table, row)` pairs with a queued hard delete.
  final Set<PendingWriteKey> deletes;

  /// `(parent table, parent id)` pairs with a queued tag replacement.
  final Set<PendingWriteKey> tags;

  /// The total number of queued writes of every kind.
  final int total;

  /// Whether an entity row [id] of [table] has a queued delete and must not be
  /// pulled back.
  bool suppressesEntity(String table, Object? id) =>
      id is String && deletes.contains(PendingWriteKey(table, id));

  /// Whether the children of [parentId] of [parentTable] must not be pulled
  /// back, because the parent has a queued delete or a queued tag replacement.
  bool suppressesChildren(String parentTable, Object? parentId) =>
      parentId is String &&
      (deletes.contains(PendingWriteKey(parentTable, parentId)) ||
          tags.contains(PendingWriteKey(parentTable, parentId)));
}

/// Local-only access to the `pending_writes` outbound queue.
///
/// The table is created by [AppDatabase]'s migration (raw SQL, never part of the
/// frozen remote schema). This store is the only writer; it uses raw SQL over
/// the shared [AppDatabase].
class PendingWriteStore {
  /// Creates a store over [database].
  PendingWriteStore(this._database);

  final AppDatabase _database;

  /// Queues [write], replacing any earlier intent for the same `(table, row)`.
  Future<void> enqueue(PendingWrite write) => _database.customStatement(
    'INSERT INTO pending_writes (kind, table_name, row_id, statements) '
    'VALUES (?, ?, ?, ?) '
    'ON CONFLICT(table_name, row_id) DO UPDATE SET '
    'kind = excluded.kind, statements = excluded.statements',
    [write.kind, write.table, write.rowId, write.statementsJson],
  );

  /// Removes the queued write for `(table, rowId)` only if its statements still
  /// equal [statementsJson].
  ///
  /// The guard keeps a flush from deleting a newer intent that replaced the one
  /// it executed while the remote call was in flight.
  Future<void> removeIfUnchanged(
    String table,
    String rowId,
    String statementsJson,
  ) => _database.customStatement(
    'DELETE FROM pending_writes '
    'WHERE table_name = ? AND row_id = ? AND statements = ?',
    [table, rowId, statementsJson],
  );

  /// Removes every queued write.
  ///
  /// Used when the configured remote target changes: the queue carries no
  /// database identity, so writes queued against the previous remote must not
  /// be flushed into the new one.
  Future<void> clear() =>
      _database.customStatement('DELETE FROM pending_writes');

  /// Returns the queued write for `(table, rowId)`, or `null` if none is
  /// queued.
  Future<PendingWrite?> entry(String table, String rowId) async {
    final row = await _database
        .customSelect(
          'SELECT kind, table_name, row_id, statements FROM pending_writes '
          'WHERE table_name = ? AND row_id = ?',
          variables: [Variable.withString(table), Variable.withString(rowId)],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Returns every queued write in insertion order, for flushing.
  Future<List<PendingWrite>> allEntries() async {
    final rows = await _database
        .customSelect(
          'SELECT kind, table_name, row_id, statements FROM pending_writes '
          'ORDER BY seq',
        )
        .get();
    return [for (final row in rows) _fromRow(row)];
  }

  /// Returns the queued deletes and tag replacements, for resurrection
  /// suppression and for reporting how much remains queued.
  Future<PendingWriteKeys> keys() async {
    final rows = await _database
        .customSelect('SELECT kind, table_name, row_id FROM pending_writes')
        .get();
    final deletes = <PendingWriteKey>{};
    final tags = <PendingWriteKey>{};
    for (final row in rows) {
      final key = PendingWriteKey(
        row.read<String>('table_name'),
        row.read<String>('row_id'),
      );
      switch (row.read<String>('kind')) {
        case PendingWriteKind.delete:
          deletes.add(key);
        case PendingWriteKind.tags:
          tags.add(key);
      }
    }
    return PendingWriteKeys(deletes: deletes, tags: tags, total: rows.length);
  }

  PendingWrite _fromRow(QueryRow row) => PendingWrite(
    kind: row.read<String>('kind'),
    table: row.read<String>('table_name'),
    rowId: row.read<String>('row_id'),
    statementsJson: row.read<String>('statements'),
  );
}

String _encodeStatements(List<QueuedStatement> statements) => jsonEncode([
  for (final statement in statements)
    {'sql': statement.sql, 'args': statement.args},
]);

List<QueuedStatement> _decodeStatements(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is Map)
        QueuedStatement(
          (item['sql'] as String?) ?? '',
          ((item['args'] as List?) ?? const []).cast<Object?>(),
        ),
  ];
}
