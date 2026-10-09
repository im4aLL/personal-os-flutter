import '../../models/link.dart';
import '../../models/note.dart';
import '../../models/project.dart';
import '../../models/todo.dart';
import '../../models/work_log.dart';
import 'database.dart';

/// Row-to-domain-model conversion for the drift repositories.
///
/// The reference clients store booleans as 0/1 integers (`archived`, `pinned`,
/// `is_separator`) and status/priority as their wire strings; these helpers map
/// both directions at the data boundary so the rest of the app only sees the
/// typed domain models.

/// Converts a 0/1 flag into a [bool].
bool flagFromInt(int value) => value != 0;

/// Converts a [bool] into the 0/1 value the reference schema stores.
int flagToInt(bool value) => value ? 1 : 0;

/// Converts a `todos` row into a [Todo].
Todo todoFromRow(TodoRow row) => Todo(
  id: row.id,
  title: row.title,
  description: row.description,
  status: TodoStatus.fromWire(row.status),
  priority: row.priority == null ? null : TodoPriority.fromWire(row.priority!),
  dueDate: row.dueDate,
  position: row.position,
  archived: flagFromInt(row.archived),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

/// Converts a `notes` row into a [Note] (tags are resolved separately).
Note noteFromRow(NoteRow row) => Note(
  id: row.id,
  title: row.title,
  content: row.content,
  pinned: flagFromInt(row.pinned),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

/// Converts a `links` row into a [Link] (tags are resolved separately).
Link linkFromRow(LinkRow row) => Link(
  id: row.id,
  url: row.url,
  title: row.title,
  faviconUrl: row.faviconUrl,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

/// Converts a `work_logs` row into a [WorkLog] (tags are resolved separately).
WorkLog workLogFromRow(WorkLogRow row) => WorkLog(
  id: row.id,
  title: row.title,
  description: row.description,
  startDate: row.startDate,
  endDate: row.endDate,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

/// Converts a `projects` row into a [Project].
Project projectFromRow(ProjectRow row) => Project(
  id: row.id,
  name: row.name,
  startDate: row.startDate,
  weekCount: row.weekCount,
  position: row.position,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

/// Converts a `project_phases` row into a [ProjectPhase].
ProjectPhase projectPhaseFromRow(ProjectPhaseRow row) => ProjectPhase(
  id: row.id,
  projectId: row.projectId,
  name: row.name,
  color: row.color,
  position: row.position,
  createdAt: row.createdAt,
);

/// Converts a `work_items` row into a [WorkItem].
WorkItem workItemFromRow(WorkItemRow row) => WorkItem(
  id: row.id,
  projectId: row.projectId,
  phaseId: row.phaseId,
  title: row.title,
  person: row.person,
  comment: row.comment,
  jiraTicket: row.jiraTicket,
  status: WorkItemStatus.fromWire(row.status),
  startWeek: row.startWeek,
  endWeek: row.endWeek,
  position: row.position,
  isSeparator: flagFromInt(row.isSeparator),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);
