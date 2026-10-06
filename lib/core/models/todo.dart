import 'sentinel.dart';

/// Todo status. Wire values match the remote `todos.status` CHECK domain
/// exactly (`todo` | `in_progress` | `completed`).
enum TodoStatus {
  /// Not started.
  todo('todo'),

  /// Actively being worked on.
  inProgress('in_progress'),

  /// Finished.
  completed('completed');

  const TodoStatus(this.wire);

  /// The value stored in the shared Turso database.
  final String wire;

  /// Parses a [wire] value into a [TodoStatus].
  static TodoStatus fromWire(String value) => switch (value) {
    'todo' => TodoStatus.todo,
    'in_progress' => TodoStatus.inProgress,
    'completed' => TodoStatus.completed,
    _ => throw ArgumentError.value(value, 'value', 'Unknown TodoStatus'),
  };
}

/// Todo priority. Wire values match the remote `todos.priority` CHECK domain
/// exactly (`low` | `medium` | `high`).
enum TodoPriority {
  /// Low priority.
  low('low'),

  /// Medium priority.
  medium('medium'),

  /// High priority.
  high('high');

  const TodoPriority(this.wire);

  /// The value stored in the shared Turso database.
  final String wire;

  /// Parses a [wire] value into a [TodoPriority].
  static TodoPriority fromWire(String value) => switch (value) {
    'low' => TodoPriority.low,
    'medium' => TodoPriority.medium,
    'high' => TodoPriority.high,
    _ => throw ArgumentError.value(value, 'value', 'Unknown TodoPriority'),
  };
}

/// A todo, mirroring the remote `todos` table column-for-column.
class Todo {
  /// Creates a [Todo].
  const Todo({
    required this.id,
    required this.title,
    this.description,
    this.status = TodoStatus.todo,
    this.priority,
    this.dueDate,
    this.position = 0,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UUID primary key.
  final String id;

  /// Required title (`title TEXT NOT NULL`).
  final String title;

  /// Optional long-form description (`description TEXT`, nullable).
  final String? description;

  /// Status; defaults to [TodoStatus.todo] like the column default.
  final TodoStatus status;

  /// Optional priority (`priority TEXT`, nullable).
  final TodoPriority? priority;

  /// Optional due date as `YYYY-MM-DD` (`due_date TEXT`, nullable).
  final String? dueDate;

  /// Sort position (`position INTEGER NOT NULL DEFAULT 0`).
  final int position;

  /// Soft-delete flag, stored as 0/1 at the data boundary.
  final bool archived;

  /// Millisecond-precision UTC ISO-8601 creation timestamp.
  final String createdAt;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields ([description], [priority], [dueDate]) use [unset] so an
  /// explicit `null` clears them.
  Todo copyWith({
    String? id,
    String? title,
    Object? description = unset,
    TodoStatus? status,
    Object? priority = unset,
    Object? dueDate = unset,
    int? position,
    bool? archived,
    String? createdAt,
    String? updatedAt,
  }) => Todo(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description == unset ? this.description : description as String?,
    status: status ?? this.status,
    priority: priority == unset ? this.priority : priority as TodoPriority?,
    dueDate: dueDate == unset ? this.dueDate : dueDate as String?,
    position: position ?? this.position,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          status == other.status &&
          priority == other.priority &&
          dueDate == other.dueDate &&
          position == other.position &&
          archived == other.archived &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    status,
    priority,
    dueDate,
    position,
    archived,
    createdAt,
    updatedAt,
  );
}
