import 'package:drift/drift.dart';

import '../../models/project.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../remote_write_sink.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';
import 'write_mirror.dart';

/// Drift-backed [ProjectRepository].
///
/// Mirrors `MockProjectRepository`: position-ordered watches, timestamp stamping
/// from [nowIso], and `deletePhase` clearing referencing `work_items.phase_id`
/// in the same transaction (the frozen schema declares that foreign key with no
/// cascade, so deleting a referenced phase would otherwise be rejected). Work
/// items survive unphased. Phase writes are mirrored to the remote at mutation
/// time because `project_phases` has no `updated_at` and the sync treats it as
/// insert-only.
class DriftProjectRepository implements ProjectRepository {
  /// Creates a repository over [database].
  ///
  /// [writeSink] mirrors every write to the remote store; it is always
  /// installed at runtime and no-ops while sync is unconfigured.
  DriftProjectRepository(this._database, {this.writeSink});

  final AppDatabase _database;

  /// Mirrors writes to the remote store; always installed at runtime, no-op
  /// while sync is unconfigured.
  final RemoteWriteSink? writeSink;

  // -- Projects ---------------------------------------------------------------

  @override
  Stream<List<Project>> watchProjects() {
    final query = _database.select(_database.projects)
      ..orderBy([(p) => OrderingTerm.asc(p.position)]);
    return query.watch().map(
      (rows) => [for (final row in rows) projectFromRow(row)],
    );
  }

  @override
  Future<Project?> getProject(String id) async {
    final row = await (_database.select(
      _database.projects,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return row == null ? null : projectFromRow(row);
  }

  @override
  Future<Project> createProject({
    required String name,
    required String startDate,
    int weekCount = 12,
  }) async {
    final now = nowIso();
    final position = await _database.projects.count().getSingle();
    final project = Project(
      id: newId(),
      name: name,
      startDate: startDate,
      weekCount: weekCount,
      position: position,
      createdAt: now,
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.projects)
          .insert(
            ProjectsCompanion(
              id: Value(project.id),
              name: Value(project.name),
              startDate: Value(project.startDate),
              weekCount: Value(project.weekCount),
              position: Value(project.position),
              createdAt: Value(project.createdAt),
              updatedAt: Value(project.updatedAt),
            ),
          );
      // Mirror the create at mutation time so it reaches the cloud without
      // waiting for a sync. Enqueued in the same transaction so the queued
      // intent commits atomically with the local insert.
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.projects,
        id: project.id,
      );
    });
    return project;
  }

  @override
  Future<void> updateProject(Project project) async {
    // `created_at` is intentionally absent so the stored value is preserved.
    await _database.transaction(() async {
      await (_database.update(
        _database.projects,
      )..where((p) => p.id.equals(project.id))).write(
        ProjectsCompanion(
          name: Value(project.name),
          startDate: Value(project.startDate),
          weekCount: Value(project.weekCount),
          position: Value(project.position),
          updatedAt: Value(nowIso()),
        ),
      );
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.projects,
        id: project.id,
      );
    });
  }

  @override
  Future<void> deleteProject(String id) async {
    await _database.transaction(() async {
      // Delete children explicitly in dependency order (work_items reference
      // phases without a cascade), so the outcome does not depend on the
      // connection's foreign-key setting.
      await (_database.delete(
        _database.workItems,
      )..where((w) => w.projectId.equals(id))).go();
      await (_database.delete(
        _database.projectPhases,
      )..where((p) => p.projectId.equals(id))).go();
      await (_database.delete(
        _database.projects,
      )..where((p) => p.id.equals(id))).go();
      // Enqueue inside the transaction so the queued delete commits atomically
      // with the local delete (see the todo repository).
      await writeSink?.recordDelete(RemoteTables.projects, id);
    });
  }

  @override
  Future<void> reorderProjects(List<String> orderedIds) async {
    await _database.transaction(() async {
      final now = nowIso();
      for (var i = 0; i < orderedIds.length; i++) {
        await (_database.update(
          _database.projects,
        )..where((p) => p.id.equals(orderedIds[i]))).write(
          ProjectsCompanion(position: Value(i), updatedAt: Value(now)),
        );
        await mirrorUpsert(
          _database,
          writeSink,
          table: RemoteTables.projects,
          id: orderedIds[i],
        );
      }
    });
  }

  // -- Phases -----------------------------------------------------------------

  @override
  Stream<List<ProjectPhase>> watchPhases(String projectId) {
    final query = _database.select(_database.projectPhases)
      ..where((p) => p.projectId.equals(projectId))
      ..orderBy([(p) => OrderingTerm.asc(p.position)]);
    return query.watch().map(
      (rows) => [for (final row in rows) projectPhaseFromRow(row)],
    );
  }

  @override
  Future<List<ProjectPhase>> getPhases(String projectId) async {
    final rows =
        await (_database.select(_database.projectPhases)
              ..where((p) => p.projectId.equals(projectId))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get();
    return [for (final row in rows) projectPhaseFromRow(row)];
  }

  @override
  Future<ProjectPhase> createPhase(
    String projectId, {
    required String name,
    required String color,
    int? position,
  }) async {
    final resolvedPosition =
        position ??
        await _database.projectPhases
            .count(where: (p) => p.projectId.equals(projectId))
            .getSingle();
    final phase = ProjectPhase(
      id: newId(),
      projectId: projectId,
      name: name,
      color: color,
      position: resolvedPosition,
      createdAt: nowIso(),
    );
    await _database.transaction(() async {
      await _database
          .into(_database.projectPhases)
          .insert(
            ProjectPhasesCompanion(
              id: Value(phase.id),
              projectId: Value(phase.projectId),
              name: Value(phase.name),
              color: Value(phase.color),
              position: Value(phase.position),
              createdAt: Value(phase.createdAt),
            ),
          );
      // `project_phases` has no `updated_at`, so the sync treats it as
      // insert-only and would never propagate the phase. Mirror the create at
      // mutation time, enqueued in the same transaction so the queued intent
      // commits atomically with the local insert.
      await writeSink?.recordUpsert(
        RemoteTables.projectPhases,
        _phaseRow(phase),
      );
    });
    return phase;
  }

  @override
  Future<void> updatePhase(ProjectPhase phase) async {
    // The reference has no updated_at on phases; the mock replaces the row
    // wholesale, so every column is written.
    await _database.transaction(() async {
      await (_database.update(
        _database.projectPhases,
      )..where((p) => p.id.equals(phase.id))).write(
        ProjectPhasesCompanion(
          projectId: Value(phase.projectId),
          name: Value(phase.name),
          color: Value(phase.color),
          position: Value(phase.position),
          createdAt: Value(phase.createdAt),
        ),
      );
      // Mirror the update at mutation time; without it a rename/color/position
      // change would never reach the remote. Enqueued in the same transaction
      // so the queued intent commits atomically with the local update.
      await writeSink?.recordUpsert(
        RemoteTables.projectPhases,
        _phaseRow(phase),
      );
    });
  }

  @override
  Future<void> deletePhase(String id) async {
    await _database.transaction(() async {
      // Unphase referencing items first (no cascade on this FK), preserving the
      // reference outcome: items survive with a null phase. `updated_at` is
      // deliberately NOT advanced: the desktop leaves work_items untouched when
      // it deletes a phase, so stamping it here would push phase_id=null to the
      // shared remote on the next sync.
      await (_database.update(_database.workItems)
            ..where((w) => w.phaseId.equals(id)))
          .write(WorkItemsCompanion(phaseId: Value(null)));
      await (_database.delete(
        _database.projectPhases,
      )..where((p) => p.id.equals(id))).go();
      // Enqueue inside the transaction so the queued delete commits atomically
      // with the local delete (see the todo repository).
      await writeSink?.recordDelete(RemoteTables.projectPhases, id);
    });
  }

  /// The remote `project_phases` row for [phase], in the schema's column order.
  Map<String, Object?> _phaseRow(ProjectPhase phase) => {
    'id': phase.id,
    'project_id': phase.projectId,
    'name': phase.name,
    'color': phase.color,
    'position': phase.position,
    'created_at': phase.createdAt,
  };

  // -- Work items -------------------------------------------------------------

  @override
  Stream<List<WorkItemWithPhase>> watchWorkItems(String projectId) {
    final query = _workItemsQuery(projectId);
    return query.watch().map(_join);
  }

  @override
  Future<List<WorkItemWithPhase>> getWorkItems(String projectId) async {
    final rows = await _workItemsQuery(projectId).get();
    return _join(rows);
  }

  @override
  Future<WorkItemWithPhase> createWorkItem(
    String projectId, {
    String? phaseId,
    required String title,
    String? person,
    String? comment,
    String? jiraTicket,
    WorkItemStatus status = WorkItemStatus.pending,
    int startWeek = 1,
    int endWeek = 1,
    int? position,
    bool isSeparator = false,
  }) async {
    final now = nowIso();
    final resolvedPosition =
        position ??
        await _database.workItems
            .count(where: (w) => w.projectId.equals(projectId))
            .getSingle();
    final item = WorkItem(
      id: newId(),
      projectId: projectId,
      phaseId: phaseId,
      title: title,
      person: person,
      comment: comment,
      jiraTicket: jiraTicket,
      status: status,
      startWeek: startWeek,
      endWeek: endWeek,
      position: resolvedPosition,
      isSeparator: isSeparator,
      createdAt: now,
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.workItems)
          .insert(
            WorkItemsCompanion(
              id: Value(item.id),
              projectId: Value(item.projectId),
              phaseId: Value(item.phaseId),
              title: Value(item.title),
              person: Value(item.person),
              comment: Value(item.comment),
              jiraTicket: Value(item.jiraTicket),
              status: Value(item.status.wire),
              startWeek: Value(item.startWeek),
              endWeek: Value(item.endWeek),
              position: Value(item.position),
              isSeparator: Value(flagToInt(item.isSeparator)),
              createdAt: Value(item.createdAt),
              updatedAt: Value(item.updatedAt),
            ),
          );
      // Mirror the create at mutation time so it reaches the cloud without
      // waiting for a sync. Enqueued in the same transaction so the queued
      // intent commits atomically with the local insert.
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.workItems,
        id: item.id,
      );
    });
    final phase = phaseId == null ? null : await _getPhase(phaseId);
    return WorkItemWithPhase(item: item, phase: phase);
  }

  @override
  Future<void> updateWorkItem(WorkItem item) async {
    // `created_at` is intentionally absent so the stored value is preserved.
    await _database.transaction(() async {
      await (_database.update(
        _database.workItems,
      )..where((w) => w.id.equals(item.id))).write(
        WorkItemsCompanion(
          projectId: Value(item.projectId),
          phaseId: Value(item.phaseId),
          title: Value(item.title),
          person: Value(item.person),
          comment: Value(item.comment),
          jiraTicket: Value(item.jiraTicket),
          status: Value(item.status.wire),
          startWeek: Value(item.startWeek),
          endWeek: Value(item.endWeek),
          position: Value(item.position),
          isSeparator: Value(flagToInt(item.isSeparator)),
          updatedAt: Value(nowIso()),
        ),
      );
      await mirrorUpsert(
        _database,
        writeSink,
        table: RemoteTables.workItems,
        id: item.id,
      );
    });
  }

  @override
  Future<void> deleteWorkItem(String id) async {
    // Enqueue the mirror inside the transaction so the queued delete commits
    // atomically with the local delete (see the todo repository).
    await _database.transaction(() async {
      await (_database.delete(
        _database.workItems,
      )..where((w) => w.id.equals(id))).go();
      await writeSink?.recordDelete(RemoteTables.workItems, id);
    });
  }

  @override
  Future<void> reorderWorkItems(
    String projectId,
    List<String> orderedIds,
  ) async {
    await _database.transaction(() async {
      final now = nowIso();
      for (var i = 0; i < orderedIds.length; i++) {
        await (_database.update(
          _database.workItems,
        )..where((w) => w.id.equals(orderedIds[i]))).write(
          WorkItemsCompanion(position: Value(i), updatedAt: Value(now)),
        );
        await mirrorUpsert(
          _database,
          writeSink,
          table: RemoteTables.workItems,
          id: orderedIds[i],
        );
      }
    });
  }

  JoinedSelectStatement _workItemsQuery(String projectId) {
    return _database.select(_database.workItems).join([
        leftOuterJoin(
          _database.projectPhases,
          _database.projectPhases.id.equalsExp(_database.workItems.phaseId),
        ),
      ])
      ..where(_database.workItems.projectId.equals(projectId))
      ..orderBy([OrderingTerm.asc(_database.workItems.position)]);
  }

  List<WorkItemWithPhase> _join(List<TypedResult> rows) {
    return [
      for (final row in rows)
        WorkItemWithPhase(
          item: workItemFromRow(row.readTable(_database.workItems)),
          phase: _phaseFromResult(row),
        ),
    ];
  }

  ProjectPhase? _phaseFromResult(TypedResult row) {
    final phaseRow = row.readTableOrNull(_database.projectPhases);
    return phaseRow == null ? null : projectPhaseFromRow(phaseRow);
  }

  Future<ProjectPhase?> _getPhase(String id) async {
    final row = await (_database.select(
      _database.projectPhases,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return row == null ? null : projectPhaseFromRow(row);
  }
}
