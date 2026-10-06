import 'sentinel.dart';

/// Work item status. Wire values match the remote `work_items.status` CHECK
/// domain exactly (`pending` | `in_progress` | `done`).
enum WorkItemStatus {
  /// Not started.
  pending('pending'),

  /// Actively being worked on.
  inProgress('in_progress'),

  /// Finished.
  done('done');

  const WorkItemStatus(this.wire);

  /// The value stored in the shared Turso database.
  final String wire;

  /// Parses a [wire] value into a [WorkItemStatus].
  static WorkItemStatus fromWire(String value) => switch (value) {
    'pending' => WorkItemStatus.pending,
    'in_progress' => WorkItemStatus.inProgress,
    'done' => WorkItemStatus.done,
    _ => throw ArgumentError.value(value, 'value', 'Unknown WorkItemStatus'),
  };
}

/// A project, mirroring the remote `projects` table column-for-column.
class Project {
  /// Creates a [Project].
  const Project({
    required this.id,
    required this.name,
    required this.startDate,
    this.weekCount = 12,
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID primary key.
  final String id;

  /// Project name.
  final String name;

  /// Start date as `YYYY-MM-DD`.
  final String startDate;

  /// Number of weeks in the Gantt (`week_count INTEGER NOT NULL DEFAULT 12`).
  final int weekCount;

  /// Sort position.
  final int position;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  Project copyWith({
    String? id,
    String? name,
    String? startDate,
    int? weekCount,
    int? position,
    String? createdAt,
    String? updatedAt,
  }) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    weekCount: weekCount ?? this.weekCount,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A project phase, mirroring the remote `project_phases` table.
///
/// Note: this table has no `updated_at` column in the frozen schema.
class ProjectPhase {
  /// Creates a [ProjectPhase].
  const ProjectPhase({
    required this.id,
    required this.projectId,
    required this.name,
    required this.color,
    this.position = 0,
    required this.createdAt,
  });

  /// UUID primary key.
  final String id;

  /// Owning project id (`project_id TEXT NOT NULL REFERENCES projects(id)`).
  final String projectId;

  /// Phase name.
  final String name;

  /// Hex color, e.g. `#93C5FD`.
  final String color;

  /// Sort position.
  final int position;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Returns a copy with the given fields replaced.
  ProjectPhase copyWith({
    String? id,
    String? projectId,
    String? name,
    String? color,
    int? position,
    String? createdAt,
  }) => ProjectPhase(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    color: color ?? this.color,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
  );
}

/// A work item row in a project Gantt, mirroring the remote `work_items` table.
class WorkItem {
  /// Creates a [WorkItem].
  const WorkItem({
    required this.id,
    required this.projectId,
    this.phaseId,
    this.title = '',
    this.person,
    this.comment,
    this.jiraTicket,
    this.status = WorkItemStatus.pending,
    this.startWeek = 1,
    this.endWeek = 1,
    this.position = 0,
    this.isSeparator = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID primary key.
  final String id;

  /// Owning project id.
  final String projectId;

  /// Optional owning phase id (`phase_id TEXT`, nullable).
  final String? phaseId;

  /// Title (`title TEXT NOT NULL DEFAULT ''`).
  final String title;

  /// Optional assignee (`person TEXT`, nullable).
  final String? person;

  /// Optional comment (`comment TEXT`, nullable).
  final String? comment;

  /// Optional Jira ticket (`jira_ticket TEXT`, nullable).
  final String? jiraTicket;

  /// Status.
  final WorkItemStatus status;

  /// First week of the Gantt bar.
  final int startWeek;

  /// Last week of the Gantt bar.
  final int endWeek;

  /// Sort position.
  final int position;

  /// Separator row flag, stored as 0/1 at the data boundary.
  final bool isSeparator;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// [phaseId], [person], [comment] and [jiraTicket] use [unset] so an explicit
  /// `null` clears them.
  WorkItem copyWith({
    String? id,
    String? projectId,
    Object? phaseId = unset,
    String? title,
    Object? person = unset,
    Object? comment = unset,
    Object? jiraTicket = unset,
    WorkItemStatus? status,
    int? startWeek,
    int? endWeek,
    int? position,
    bool? isSeparator,
    String? createdAt,
    String? updatedAt,
  }) => WorkItem(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    phaseId: phaseId == unset ? this.phaseId : phaseId as String?,
    title: title ?? this.title,
    person: person == unset ? this.person : person as String?,
    comment: comment == unset ? this.comment : comment as String?,
    jiraTicket: jiraTicket == unset ? this.jiraTicket : jiraTicket as String?,
    status: status ?? this.status,
    startWeek: startWeek ?? this.startWeek,
    endWeek: endWeek ?? this.endWeek,
    position: position ?? this.position,
    isSeparator: isSeparator ?? this.isSeparator,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A work item together with its resolved phase, matching the reference
/// `WorkItemWithPhase`.
class WorkItemWithPhase {
  /// Creates a [WorkItemWithPhase].
  const WorkItemWithPhase({required this.item, this.phase});

  /// The work item row.
  final WorkItem item;

  /// The resolved phase, or `null` when [WorkItem.phaseId] is null or dangling.
  final ProjectPhase? phase;

  /// The work item id.
  String get id => item.id;

  /// The owning project id.
  String get projectId => item.projectId;

  /// The optional phase id.
  String? get phaseId => item.phaseId;

  /// The title.
  String get title => item.title;

  /// The optional assignee.
  String? get person => item.person;

  /// The optional comment.
  String? get comment => item.comment;

  /// The optional Jira ticket.
  String? get jiraTicket => item.jiraTicket;

  /// The status.
  WorkItemStatus get status => item.status;

  /// Creation timestamp.
  String get createdAt => item.createdAt;

  /// Last-write timestamp.
  String get updatedAt => item.updatedAt;

  /// First week of the bar.
  int get startWeek => item.startWeek;

  /// Last week of the bar.
  int get endWeek => item.endWeek;

  /// Sort position.
  int get position => item.position;

  /// Whether this is a separator row.
  bool get isSeparator => item.isSeparator;

  /// Returns a copy with the given fields replaced.
  WorkItemWithPhase copyWith({WorkItem? item, ProjectPhase? phase}) =>
      WorkItemWithPhase(item: item ?? this.item, phase: phase ?? this.phase);
}
