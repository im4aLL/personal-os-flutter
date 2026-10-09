import 'package:drift/drift.dart';

import '../../models/work_log.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';

/// Drift-backed [WorkLogRepository].
///
/// Mirrors `MockWorkLogRepository`: newest start date first (then newest
/// creation), and tag replacement deletes and re-inserts without advancing the
/// work log's `updated_at`.
class DriftWorkLogRepository implements WorkLogRepository {
  /// Creates a repository over [database].
  DriftWorkLogRepository(this._database);

  final AppDatabase _database;

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
      await _insertTags(workLog.id, tags);
    });
    return WorkLogWithTags(workLog: workLog, tags: List.unmodifiable(tags));
  }

  @override
  Future<void> update(WorkLog workLog) async {
    // `created_at` is intentionally absent so the stored value is preserved.
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
  }

  @override
  Future<void> setTags(String id, List<String> tags) async {
    // Touches only work_log_tags; the work log's updated_at is deliberately
    // untouched, matching the reference setTagsForWorkLog (LWW safety).
    await _database.transaction(() async {
      await (_database.delete(
        _database.workLogTags,
      )..where((t) => t.workLogId.equals(id))).go();
      await _insertTags(id, tags);
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
    });
  }

  Future<void> _insertTags(String workLogId, List<String> tags) async {
    final now = nowIso();
    for (final name in tags) {
      await _database
          .into(_database.workLogTags)
          .insert(
            WorkLogTagsCompanion(
              id: Value(newId()),
              workLogId: Value(workLogId),
              name: Value(name),
              createdAt: Value(now),
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
