import '../../models/project.dart';
import '../../utils/clock.dart';
import '../../utils/dates.dart';
import '../../utils/id.dart';
import '../../utils/streams.dart';
import '../in_memory_store.dart';
import '../repositories.dart';

/// In-memory [ProjectRepository] seeded with one project, three phases, and
/// eight work item rows (seven tasks plus one separator).
class MockProjectRepository implements ProjectRepository {
  MockProjectRepository._(this._projects, this._phases, this._workItems);

  /// Creates a repository seeded relative to today.
  factory MockProjectRepository.seeded() {
    final seed = _seedProject();
    return MockProjectRepository._(
      InMemoryStore<Project>([seed.project]),
      InMemoryStore<ProjectPhase>(seed.phases),
      InMemoryStore<WorkItem>(seed.workItems),
    );
  }

  final InMemoryStore<Project> _projects;
  final InMemoryStore<ProjectPhase> _phases;
  final InMemoryStore<WorkItem> _workItems;

  // -- Projects ---------------------------------------------------------------

  @override
  Stream<List<Project>> watchProjects() =>
      _projects.watch().map((items) => _sortByPosition(items, (p) => p.position));

  @override
  Future<Project?> getProject(String id) async {
    for (final project in _projects.snapshot) {
      if (project.id == id) return project;
    }
    return null;
  }

  @override
  Future<Project> createProject({
    required String name,
    required String startDate,
    int weekCount = 12,
  }) async {
    final now = nowIso();
    final project = Project(
      id: newId(),
      name: name,
      startDate: startDate,
      weekCount: weekCount,
      position: _projects.snapshot.length,
      createdAt: now,
      updatedAt: now,
    );
    _projects.mutate((items) => items.add(project));
    return project;
  }

  @override
  Future<void> updateProject(Project project) async {
    _projects.mutate((items) {
      final index = items.indexWhere((p) => p.id == project.id);
      if (index == -1) return;
      items[index] = project.copyWith(
        createdAt: items[index].createdAt,
        updatedAt: nowIso(),
      );
    });
  }

  @override
  Future<void> deleteProject(String id) async {
    _projects.mutate((items) => items.removeWhere((p) => p.id == id));
    _phases.mutate((items) => items.removeWhere((p) => p.projectId == id));
    _workItems.mutate((items) => items.removeWhere((w) => w.projectId == id));
  }

  @override
  Future<void> reorderProjects(List<String> orderedIds) async {
    final now = nowIso();
    _projects.mutate((items) {
      for (var i = 0; i < orderedIds.length; i++) {
        final index = items.indexWhere((p) => p.id == orderedIds[i]);
        if (index != -1) {
          items[index] = items[index].copyWith(position: i, updatedAt: now);
        }
      }
    });
  }

  // -- Phases -----------------------------------------------------------------

  @override
  Stream<List<ProjectPhase>> watchPhases(String projectId) => _phases.watch().map(
    (items) => _sortByPosition(
      items.where((phase) => phase.projectId == projectId),
      (phase) => phase.position,
    ),
  );

  @override
  Future<List<ProjectPhase>> getPhases(String projectId) async => _sortByPosition(
    _phases.snapshot.where((phase) => phase.projectId == projectId),
    (phase) => phase.position,
  );

  @override
  Future<ProjectPhase> createPhase(
    String projectId, {
    required String name,
    required String color,
    int? position,
  }) async {
    final phase = ProjectPhase(
      id: newId(),
      projectId: projectId,
      name: name,
      color: color,
      position:
          position ??
          _phases.snapshot.where((p) => p.projectId == projectId).length,
      createdAt: nowIso(),
    );
    _phases.mutate((items) => items.add(phase));
    return phase;
  }

  @override
  Future<void> updatePhase(ProjectPhase phase) async {
    _phases.mutate((items) {
      final index = items.indexWhere((p) => p.id == phase.id);
      if (index != -1) items[index] = phase;
    });
  }

  @override
  Future<void> deletePhase(String id) async {
    _phases.mutate((items) => items.removeWhere((p) => p.id == id));
  }

  // -- Work items -------------------------------------------------------------

  @override
  Stream<List<WorkItemWithPhase>> watchWorkItems(String projectId) =>
      combineLatest2(
        _workItems.watch(),
        _phases.watch(),
        (items, phases) => _join(projectId, items, phases),
      );

  @override
  Future<List<WorkItemWithPhase>> getWorkItems(String projectId) async =>
      _join(projectId, _workItems.snapshot, _phases.snapshot);

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
      position:
          position ??
          _workItems.snapshot.where((w) => w.projectId == projectId).length,
      isSeparator: isSeparator,
      createdAt: now,
      updatedAt: now,
    );
    _workItems.mutate((items) => items.add(item));
    return _join(projectId, [item], _phases.snapshot).single;
  }

  @override
  Future<void> updateWorkItem(WorkItem item) async {
    _workItems.mutate((items) {
      final index = items.indexWhere((w) => w.id == item.id);
      if (index == -1) return;
      items[index] = item.copyWith(
        createdAt: items[index].createdAt,
        updatedAt: nowIso(),
      );
    });
  }

  @override
  Future<void> deleteWorkItem(String id) async {
    _workItems.mutate((items) => items.removeWhere((w) => w.id == id));
  }

  @override
  Future<void> reorderWorkItems(String projectId, List<String> orderedIds) async {
    final now = nowIso();
    _workItems.mutate((items) {
      for (var i = 0; i < orderedIds.length; i++) {
        final index = items.indexWhere((w) => w.id == orderedIds[i]);
        if (index != -1) {
          items[index] = items[index].copyWith(position: i, updatedAt: now);
        }
      }
    });
  }

  static List<WorkItemWithPhase> _join(
    String projectId,
    Iterable<WorkItem> items,
    Iterable<ProjectPhase> phases,
  ) {
    final byId = {for (final phase in phases) phase.id: phase};
    final scoped = _sortByPosition(
      items.where((item) => item.projectId == projectId),
      (item) => item.position,
    );
    return [
      for (final item in scoped)
        WorkItemWithPhase(
          item: item,
          phase: item.phaseId == null ? null : byId[item.phaseId],
        ),
    ];
  }
}

List<T> _sortByPosition<T>(Iterable<T> items, int Function(T) position) {
  final sorted = List<T>.of(items);
  sorted.sort((a, b) => position(a).compareTo(position(b)));
  return sorted;
}

typedef _ProjectSeed = ({
  Project project,
  List<ProjectPhase> phases,
  List<WorkItem> workItems,
});

/// One project starting two weeks ago, with three phases and eight work item
/// rows (seven tasks plus one separator).
_ProjectSeed _seedProject() {
  final now = DateTime.now();
  final today = dateOnly(now);
  final thisMonday = mondayOf(formatDate(today));
  final startDate =
      formatDate(DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 14));
  String ts(int hoursAgo) =>
      isoFromDateTime(now.subtract(Duration(hours: hoursAgo)));

  const projectId = 'e0000000-0000-4000-8000-000000000001';
  const discoveryId = 'f0000000-0000-4000-8000-000000000001';
  const buildId = 'f0000000-0000-4000-8000-000000000002';
  const launchId = 'f0000000-0000-4000-8000-000000000003';

  return (
    project: Project(
      id: projectId,
      name: 'Personal OS Mobile',
      startDate: startDate,
      weekCount: 12,
      position: 0,
      createdAt: ts(360),
      updatedAt: ts(24),
    ),
    phases: [
      ProjectPhase(
        id: discoveryId,
        projectId: projectId,
        name: 'Discovery',
        color: '#93C5FD',
        position: 0,
        createdAt: ts(360),
      ),
      ProjectPhase(
        id: buildId,
        projectId: projectId,
        name: 'Build',
        color: '#86EFAC',
        position: 1,
        createdAt: ts(360),
      ),
      ProjectPhase(
        id: launchId,
        projectId: projectId,
        name: 'Launch',
        color: '#FCA5A5',
        position: 2,
        createdAt: ts(360),
      ),
    ],
    workItems: [
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000001',
        projectId: projectId,
        phaseId: discoveryId,
        title: 'Requirements',
        status: WorkItemStatus.done,
        startWeek: 1,
        endWeek: 1,
        position: 0,
        createdAt: ts(350),
        updatedAt: ts(200),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000002',
        projectId: projectId,
        phaseId: discoveryId,
        title: 'Design system',
        person: 'Hadi',
        status: WorkItemStatus.done,
        startWeek: 1,
        endWeek: 2,
        position: 1,
        createdAt: ts(340),
        updatedAt: ts(180),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000003',
        projectId: projectId,
        title: 'Build',
        status: WorkItemStatus.pending,
        startWeek: 1,
        endWeek: 1,
        position: 2,
        isSeparator: true,
        createdAt: ts(330),
        updatedAt: ts(330),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000004',
        projectId: projectId,
        phaseId: buildId,
        title: 'Core models',
        person: 'Hadi',
        status: WorkItemStatus.done,
        startWeek: 3,
        endWeek: 4,
        position: 3,
        createdAt: ts(300),
        updatedAt: ts(30),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000005',
        projectId: projectId,
        phaseId: buildId,
        title: 'Mock repositories',
        person: 'Hadi',
        status: WorkItemStatus.inProgress,
        startWeek: 4,
        endWeek: 5,
        position: 4,
        jiraTicket: 'POS-12',
        createdAt: ts(240),
        updatedAt: ts(12),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000006',
        projectId: projectId,
        phaseId: buildId,
        title: 'Home dashboard',
        person: 'Hadi',
        status: WorkItemStatus.inProgress,
        startWeek: 5,
        endWeek: 6,
        position: 5,
        createdAt: ts(200),
        updatedAt: ts(6),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000007',
        projectId: projectId,
        phaseId: launchId,
        title: 'Sync engine',
        person: 'Hadi',
        status: WorkItemStatus.pending,
        startWeek: 7,
        endWeek: 9,
        position: 6,
        jiraTicket: 'POS-20',
        createdAt: ts(160),
        updatedAt: ts(160),
      ),
      WorkItem(
        id: 'a1000000-0000-4000-8000-000000000008',
        projectId: projectId,
        phaseId: launchId,
        title: 'Release APK',
        status: WorkItemStatus.pending,
        startWeek: 10,
        endWeek: 12,
        position: 7,
        createdAt: ts(120),
        updatedAt: ts(120),
      ),
    ],
  );
}
