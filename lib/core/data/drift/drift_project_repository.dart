import 'package:drift/drift.dart';

import '../../models/project.dart';
import '../../utils/clock.dart';
import '../../utils/id.dart';
import '../repositories.dart';
import 'database.dart';
import 'mappers.dart';

/// Drift-backed [ProjectRepository].
///
/// Mirrors `MockProjectRepository`: position-ordered watches, timestamp stamping
/// from [nowIso], and `deletePhase` clearing referencing `work_items.phase_id`
/// in the same transaction (the frozen schema declares that foreign key with no
/// cascade, so deleting a referenced phase would otherwise be rejected). Work
/// items survive unphased.
class DriftProjectRepository implements ProjectRepository {
  /// Creates a repository over [database].
  DriftProjectRepository(this._database);

  final AppDatabase _database;

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
    return project;
  }

  @override
  Future<void> updateProject(Project project) async {
    // `created_at` is intentionally absent so the stored value is preserved.
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
    return phase;
  }

  @override
  Future<void> updatePhase(ProjectPhase phase) async {
    // The reference has no updated_at on phases; the mock replaces the row
    // wholesale, so every column is written.
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
  }

  @override
  Future<void> deletePhase(String id) async {
    await _database.transaction(() async {
      final now = nowIso();
      // Unphase referencing items first (no cascade on this FK), preserving the
      // reference outcome: items survive with a null phase.
      await (_database.update(
        _database.workItems,
      )..where((w) => w.phaseId.equals(id))).write(
        WorkItemsCompanion(phaseId: const Value(null), updatedAt: Value(now)),
      );
      await (_database.delete(
        _database.projectPhases,
      )..where((p) => p.id.equals(id))).go();
    });
  }

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
    final phase = phaseId == null ? null : await _getPhase(phaseId);
    return WorkItemWithPhase(item: item, phase: phase);
  }

  @override
  Future<void> updateWorkItem(WorkItem item) async {
    // `created_at` is intentionally absent so the stored value is preserved.
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
  }

  @override
  Future<void> deleteWorkItem(String id) async {
    await (_database.delete(
      _database.workItems,
    )..where((w) => w.id.equals(id))).go();
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
