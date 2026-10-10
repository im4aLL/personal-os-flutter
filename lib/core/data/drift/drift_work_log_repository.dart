import 'package:drift/drift.dart';

import '../../models/work_log.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../remote_write_sink.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';
import 'write_mirror.dart';

/// Drift-backed [WorkLogRepository].
///
/// Mirrors `MockWorkLogRepository`: newest start date first (then newest
/// creation), and tag replacement deletes and re-inserts without advancing the
/// work log's `updated_at`.
class DriftWorkLogRepository implements WorkLogRepository {
  /// Creates a repository over [database].
  ///
  /// [writeSink] mirrors every write to the remote store; it is always
  /// installed at runtime and no-ops while sync is unconfigured.
  DriftWorkLogRepository(this._database, {this.writeSink});

  final AppDatabase _database;

  /// Mirrors writes to the remote store; always installed at runtime, no-op
  /// while sync is unconfigured.
  final RemoteWriteSink? writeSink;

  @override
  Stream<List<WorkLogWithTags>> watchAll() {
    final query =
        _database.select(_database.workLogs).join([
          leftOuterJoin(
            _database.workLogTags,
            _database.workLogTags.workLogId.equalsExp(_database.workLogs.id),
          ),
        ])..orderBy([
          OrderingTerm.desc(_database.workLogs.startDate),
          OrderingTerm.desc(_database.workLogs.createdAt),
          OrderingTerm.asc(_database.workLogTags.createdAt),
          OrderingTerm.asc(_workLogTagsRowId),
        ]);
    return query.watch().map(_group);
  }

  @override
  Future<WorkLogWithTags?> getById(String id) async {
    final row = await (_database.select(
      _database.workLogs,
    )..where((w) => w.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return WorkLogWithTags(
      workLog: workLogFromRow(row),
      tags: await _tagsFor(id),
    );
  }

  @override
  Future<WorkLogWithTags> create({
    required String title,
    String? description,
    required String startDate,
    required String endDate,
    List<String> tags = const [],
  }) async {
    final now = nowIso();
    final workLog = WorkLog(
      id: newId(),
      title: title,
      description: description,
      startDate: startDate,
      endDate: endDate,
      createdAt: now,
      updatedAt: now,
    );
    final tagRows = [
      for (final name in tags)
        RemoteTagRow(id: newId(), name: name, createdAt: now),
    ];
    await _database.transaction(() async {
      await _database
          .into(_database.workLogs)
          .insert(
            WorkLogsCompanion(
              id: Value(workLog.id),
              title: Value(workLog.title),
              description: Value(workLog.description),
              startDate: Value(workLog.startDate),
              endDate: Value(workLog.endDate),
              createdAt: Value(workLog.createdAt),
              updatedAt: Value(workLog.updatedAt),
            ),
          );
      await _insertTags(workLog.id, tagRows);
      // Mirror the create (entity + tags) at mutation time so it reaches the
      // cloud without waiting for a sync. Enqueued in the same transaction so
      // the queued intents commit atomically with the local insert.
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.workLogs,
        id: workLog.id,
      );
      await writeSink?.recordTags(
        parentTable: RemoteTables.workLogs,
        parentId: workLog.id,
        childTable: 'work_log_tags',
        parentColumn: 'work_log_id',
        rows: tagRows,
      );
    });
    return WorkLogWithTags(workLog: workLog, tags: List.unmodifiable(tags));
  }

  @override
  Future<void> update(WorkLog workLog) async {
    // `created_at` is intentionally absent so the stored value is preserved.
    await _database.transaction(() async {
      await (_database.update(
        _database.workLogs,
      )..where((w) => w.id.equals(workLog.id))).write(
        WorkLogsCompanion(
          title: Value(workLog.title),
          description: Value(workLog.description),
          startDate: Value(workLog.startDate),
          endDate: Value(workLog.endDate),
          updatedAt: Value(nowIso()),
        ),
      );
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.workLogs,
        id: workLog.id,
      );
    });
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Touches only work_log_tags; the work log's updated_at is deliberately
    // untouched, matching the reference setTagsForWorkLog (LWW safety).
    final now = nowIso();
    final rows = [
      for (final name in tags)
        RemoteTagRow(id: newId(), name: name, createdAt: now),
    ];
    await _database.transaction(() async {
      await (_database.delete(
        _database.workLogTags,
      )..where((t) => t.workLogId.equals(id))).go();
      await _insertTags(id, rows);
      // Mirror the replacement to the remote so a removed tag is removed
      // remotely too, instead of being pulled straight back by the insert-only
      // sync. Enqueued in the same transaction so the queued intent commits
      // atomically with the local replacement.
      await writeSink?.recordTags(
        parentTable: RemoteTables.workLogs,
        parentId: id,
        childTable: 'work_log_tags',
        parentColumn: 'work_log_id',
        rows: rows,
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.workLogTags,
      )..where((t) => t.workLogId.equals(id))).go();
      await (_database.delete(
        _database.workLogs,
      )..where((w) => w.id.equals(id))).go();
      // Enqueue inside the transaction so the queued delete commits atomically
      // with the local delete (see the todo repository).
      await writeSink?.recordDelete(RemoteTables.workLogs, id);
    });
  }

  Future<void> _insertTags(String workLogId, List<RemoteTagRow> rows) async {
    for (final row in rows) {
      await _database
          .into(_database.workLogTags)
          .insert(
            WorkLogTagsCompanion(
              id: Value(row.id),
              workLogId: Value(workLogId),
              name: Value(row.name),
              createdAt: Value(row.createdAt),
            ),
          );
    }
  }

  Future<List<String>> _tagsFor(String workLogId) async {
    final rows =
        await (_database.select(_database.workLogTags)
              ..where((t) => t.workLogId.equals(workLogId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(_workLogTagsRowId),
              ]))
            .get();
    return List.unmodifiable([for (final row in rows) row.name]);
  }

  List<WorkLogWithTags> _group(List<TypedResult> rows) {
    final order = <String>[];
    final workLogs = <String, WorkLog>{};
    final tags = <String, List<String>>{};
    for (final row in rows) {
      final workLogRow = row.readTable(_database.workLogs);
      final tagRow = row.readTableOrNull(_database.workLogTags);
      if (!workLogs.containsKey(workLogRow.id)) {
        workLogs[workLogRow.id] = workLogFromRow(workLogRow);
        tags[workLogRow.id] = <String>[];
        order.add(workLogRow.id);
      }
      if (tagRow != null) tags[workLogRow.id]!.add(tagRow.name);
    }
    return [
      for (final id in order)
        WorkLogWithTags(
          workLog: workLogs[id]!,
          tags: List.unmodifiable(tags[id]!),
        ),
    ];
  }
}

/// Ordering tiebreaker for `work_log_tags` rows inserted together (see the note
/// repository for the rationale).
final Expression<int> _workLogTagsRowId = CustomExpression<int>(
  'work_log_tags.rowid',
);
