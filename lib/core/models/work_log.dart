import 'sentinel.dart';

/// A date-ranged work log entry, mirroring the remote `work_logs` table.
class WorkLog {
  /// Creates a [WorkLog].
  const WorkLog({
    required this.id,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID primary key.
  final String id;

  /// Required title.
  final String title;

  /// Optional description (`description TEXT`, nullable).
  final String? description;

  /// Start date as `YYYY-MM-DD`.
  final String startDate;

  /// End date as `YYYY-MM-DD`.
  final String endDate;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// [description] uses [unset] so an explicit `null` clears it.
  WorkLog copyWith({
    String? id,
    String? title,
    Object? description = unset,
    String? startDate,
    String? endDate,
    String? createdAt,
    String? updatedAt,
  }) => WorkLog(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description == unset ? this.description : description as String?,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A work log tag row, mirroring the remote `work_log_tags` table.
class WorkLogTag {
  /// Creates a [WorkLogTag].
  const WorkLogTag({
    required this.id,
    required this.workLogId,
    required this.name,
    required this.createdAt,
  });

  /// UUID primary key.
  final String id;

  /// Owning work log id (`work_log_id TEXT NOT NULL REFERENCES work_logs(id)`).
  final String workLogId;

  /// Tag name.
  final String name;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;
}

/// A work log together with its tag names.
class WorkLogWithTags {
  /// Creates a [WorkLogWithTags].
  const WorkLogWithTags({required this.workLog, this.tags = const []});

  /// The work log row.
  final WorkLog workLog;

  /// Tag names in insertion order.
  final List<String> tags;

  /// The work log id.
  String get id => workLog.id;

  /// The title.
  String get title => workLog.title;

  /// The optional description.
  String? get description => workLog.description;

  /// Start date as `YYYY-MM-DD`.
  String get startDate => workLog.startDate;

  /// End date as `YYYY-MM-DD`.
  String get endDate => workLog.endDate;

  /// Creation timestamp.
  String get createdAt => workLog.createdAt;

  /// Last-write timestamp.
  String get updatedAt => workLog.updatedAt;

  /// Returns a copy with the given fields replaced.
  WorkLogWithTags copyWith({WorkLog? workLog, List<String>? tags}) =>
      WorkLogWithTags(workLog: workLog ?? this.workLog, tags: tags ?? this.tags);
}
