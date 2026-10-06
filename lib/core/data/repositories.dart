import '../models/app_setting.dart';
import '../models/link.dart';
import '../models/note.dart';
import '../models/project.dart';
import '../models/todo.dart';
import '../models/work_log.dart';

/// Read/write access to todos.
///
/// Watch methods return streams so the mock store and drift's `.watch()` drop
/// in interchangeably. CRUD methods return futures. Implementations are the
/// single place that stamps ids and `created_at`/`updated_at`.
abstract interface class TodoRepository {
  /// Watches all non-archived todos, ordered by position then creation.
  Stream<List<Todo>> watchAll();

  /// Watches non-archived todos with [status].
  Stream<List<Todo>> watchByStatus(TodoStatus status);

  /// Watches archived todos.
  Stream<List<Todo>> watchArchived();

  /// Returns the todo with [id], or `null`.
  Future<Todo?> getById(String id);

  /// Creates a todo with a new id and timestamps.
  Future<Todo> create({
    required String title,
    String? description,
    TodoStatus status = TodoStatus.todo,
    TodoPriority? priority,
    String? dueDate,
    int position = 0,
  });

  /// Replaces [todo] by id and stamps `updated_at`.
  Future<void> update(Todo todo);

  /// Sets the status of the todo with [id].
  Future<void> setStatus(String id, TodoStatus status);

  /// Soft-deletes (archives) the todo with [id].
  Future<void> archive(String id);

  /// Restores the archived todo with [id].
  Future<void> restore(String id);

  /// Hard-deletes the todo with [id].
  Future<void> delete(String id);

  /// Applies [updates] positions in one pass.
  Future<void> updatePositions(List<({String id, int position})> updates);
}

/// Read/write access to notes and their tags.
abstract interface class NoteRepository {
  /// Watches all notes with their tags, pinned first then most recently
  /// updated.
  Stream<List<NoteWithTags>> watchAll();

  /// Returns the note with [id] and its tags, or `null`.
  Future<NoteWithTags?> getById(String id);

  /// Creates a note with a new id and timestamps.
  Future<Note> create({String? title, String content = ''});

  /// Replaces [note] by id and stamps `updated_at`.
  Future<void> update(Note note);

  /// Sets the pinned flag of the note with [id].
  Future<void> setPinned(String id, bool pinned);

  /// Replaces the tag names of the note with [id].
  ///
  /// Tag replacement does NOT advance the note's `updated_at`, matching the
  /// reference `setTagsForNote`: only content/title/pin edits advance it. This
  /// keeps tag-only edits from winning last-write-wins against a concurrent
  /// content edit on another client.
  Future<void> setTags(String id, List<String> tags);

  /// Deletes the note with [id] and its tags.
  Future<void> delete(String id);
}

/// Read/write access to links and their tags.
abstract interface class LinkRepository {
  /// Watches all links with their tags, most recently created first.
  Stream<List<LinkWithTags>> watchAll();

  /// Returns the link with [id] and its tags, or `null`.
  Future<LinkWithTags?> getById(String id);

  /// Creates a link with a new id and timestamps.
  Future<LinkWithTags> create({
    required String url,
    required String title,
    String? faviconUrl,
    List<String> tags = const [],
  });

  /// Replaces [link] by id and stamps `updated_at`.
  Future<void> update(Link link);

  /// Replaces the tag names of the link with [id].
  ///
  /// Tag replacement does NOT advance the link's `updated_at`, matching the
  /// reference `setTagsForLink`: only content/title edits advance it.
  Future<void> setTags(String id, List<String> tags);

  /// Returns whether a link with [url] already exists (the remote column is
  /// UNIQUE).
  Future<bool> urlExists(String url);

  /// Deletes the link with [id] and its tags.
  Future<void> delete(String id);
}

/// Read/write access to work log entries and their tags.
abstract interface class WorkLogRepository {
  /// Watches all work logs with their tags, newest start date first.
  Stream<List<WorkLogWithTags>> watchAll();

  /// Returns the work log with [id] and its tags, or `null`.
  Future<WorkLogWithTags?> getById(String id);

  /// Creates a work log with a new id and timestamps.
  Future<WorkLogWithTags> create({
    required String title,
    String? description,
    required String startDate,
    required String endDate,
    List<String> tags = const [],
  });

  /// Replaces [workLog] by id and stamps `updated_at`.
  Future<void> update(WorkLog workLog);

  /// Replaces the tag names of the work log with [id].
  ///
  /// Tag replacement does NOT advance the work log's `updated_at`, matching the
  /// reference `setTagsForWorkLog`: only content/title/date edits advance it.
  Future<void> setTags(String id, List<String> tags);

  /// Deletes the work log with [id] and its tags.
  Future<void> delete(String id);
}

/// Read/write access to projects, their phases, and their work items.
abstract interface class ProjectRepository {
  /// Watches all projects ordered by position.
  Stream<List<Project>> watchProjects();

  /// Returns the project with [id], or `null`.
  Future<Project?> getProject(String id);

  /// Creates a project with a new id and timestamps.
  Future<Project> createProject({
    required String name,
    required String startDate,
    int weekCount = 12,
  });

  /// Replaces [project] by id and stamps `updated_at`.
  Future<void> updateProject(Project project);

  /// Deletes the project with [id], its phases, and its work items.
  Future<void> deleteProject(String id);

  /// Applies [orderedIds] positions to projects in one pass.
  Future<void> reorderProjects(List<String> orderedIds);

  /// Watches the phases of [projectId] ordered by position.
  Stream<List<ProjectPhase>> watchPhases(String projectId);

  /// Returns the phases of [projectId] ordered by position.
  Future<List<ProjectPhase>> getPhases(String projectId);

  /// Creates a phase for [projectId] with a new id and timestamp.
  Future<ProjectPhase> createPhase(
    String projectId, {
    required String name,
    required String color,
    int? position,
  });

  /// Replaces [phase] by id.
  Future<void> updatePhase(ProjectPhase phase);

  /// Deletes the phase with [id].
  ///
  /// The frozen remote schema declares `work_items.phase_id REFERENCES
  /// project_phases(id)` with no `ON DELETE CASCADE`, so deleting a phase with
  /// work items would orphan them. The desktop leaves the `phase_id` dangling
  /// and the UI resolves it to a null phase; the Phase 9 drift implementation
  /// MUST preserve that observable outcome (items survive, unphased) while
  /// preventing a foreign-key violation, e.g. by clearing referencing
  /// `work_items.phase_id` in the same transaction. Do not reject the delete.
  Future<void> deletePhase(String id);

  /// Watches the work items of [projectId] with resolved phases.
  Stream<List<WorkItemWithPhase>> watchWorkItems(String projectId);

  /// Returns the work items of [projectId] with resolved phases.
  Future<List<WorkItemWithPhase>> getWorkItems(String projectId);

  /// Creates a work item for [projectId] with a new id and timestamps.
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
  });

  /// Replaces [item] by id and stamps `updated_at`.
  Future<void> updateWorkItem(WorkItem item);

  /// Deletes the work item with [id].
  Future<void> deleteWorkItem(String id);

  /// Applies [orderedIds] positions to work items in one pass.
  Future<void> reorderWorkItems(String projectId, List<String> orderedIds);
}

/// Read/write access to shared `app_settings`.
abstract interface class SettingsRepository {
  /// Watches all settings rows.
  Stream<List<AppSetting>> watchAll();

  /// Returns the value for [key], or `null`.
  Future<String?> get(String key);

  /// Upserts [key] with [value] and stamps `updated_at`.
  Future<void> set(String key, String value);

  /// Deletes [key].
  Future<void> delete(String key);
}
