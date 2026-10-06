import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/link.dart';
import '../../../core/models/note.dart';
import '../../../core/models/project.dart';
import '../../../core/models/todo.dart';
import '../../../core/models/work_log.dart';
import '../../../core/utils/dates.dart';

/// All non-archived todos from the repository.
final allTodosProvider = StreamProvider<List<Todo>>(
  (ref) => ref.watch(todoRepositoryProvider).watchAll(),
);

/// Open todos: non-archived and not completed.
final openTodosProvider = Provider<List<Todo>>((ref) {
  final todos = ref.watch(allTodosProvider).value ?? const <Todo>[];
  return [
    for (final todo in todos)
      if (!todo.archived && todo.status != TodoStatus.completed) todo,
  ];
});

/// Open todos due today.
final dueTodayTodosProvider = Provider<List<Todo>>((ref) {
  final today = todayDate();
  return [
    for (final todo in ref.watch(openTodosProvider))
      if (todo.dueDate == today) todo,
  ];
});

/// Open todos whose due date is before today.
final overdueTodosProvider = Provider<List<Todo>>((ref) {
  final today = todayDate();
  return [
    for (final todo in ref.watch(openTodosProvider))
      if (todo.dueDate != null && todo.dueDate!.compareTo(today) < 0) todo,
  ];
});

/// Count of open todos.
final openTodoCountProvider = Provider<int>(
  (ref) => ref.watch(openTodosProvider).length,
);

/// All notes with tags.
final notesProvider = StreamProvider<List<NoteWithTags>>(
  (ref) => ref.watch(noteRepositoryProvider).watchAll(),
);

/// All links with tags.
final linksProvider = StreamProvider<List<LinkWithTags>>(
  (ref) => ref.watch(linkRepositoryProvider).watchAll(),
);

/// All work logs with tags.
final workLogsProvider = StreamProvider<List<WorkLogWithTags>>(
  (ref) => ref.watch(workLogRepositoryProvider).watchAll(),
);

/// All projects.
final projectsProvider = StreamProvider<List<Project>>(
  (ref) => ref.watch(projectRepositoryProvider).watchProjects(),
);

/// Note count for the Home count cards.
final noteCountProvider = Provider<int>(
  (ref) => ref.watch(notesProvider).value?.length ?? 0,
);

/// Link count for the Home count cards.
final linkCountProvider = Provider<int>(
  (ref) => ref.watch(linksProvider).value?.length ?? 0,
);

/// Work log count for the Home count cards.
final workLogCountProvider = Provider<int>(
  (ref) => ref.watch(workLogsProvider).value?.length ?? 0,
);

/// Project count for the Home count cards.
final projectCountProvider = Provider<int>(
  (ref) => ref.watch(projectsProvider).value?.length ?? 0,
);

/// The kind of item in the Home recent activity list.
enum ActivityType {
  /// A note.
  note,

  /// A link.
  link,

  /// A work log entry.
  workLog,
}

/// One merged recent-activity row.
class RecentActivity {
  /// Creates a [RecentActivity].
  const RecentActivity({
    required this.type,
    required this.title,
    required this.updatedAt,
  });

  /// The item type.
  final ActivityType type;

  /// Display title.
  final String title;

  /// Millisecond-precision UTC ISO-8601 last-write timestamp.
  final String updatedAt;
}

/// The five most recently updated notes, links, and work logs, merged.
final recentActivityProvider = Provider<List<RecentActivity>>((ref) {
  final notes = ref.watch(notesProvider).value ?? const <NoteWithTags>[];
  final links = ref.watch(linksProvider).value ?? const <LinkWithTags>[];
  final logs = ref.watch(workLogsProvider).value ?? const <WorkLogWithTags>[];

  final items = <RecentActivity>[
    for (final note in notes)
      RecentActivity(
        type: ActivityType.note,
        title: noteDisplayTitle(note.note),
        updatedAt: note.updatedAt,
      ),
    for (final link in links)
      RecentActivity(
        type: ActivityType.link,
        title: link.title,
        updatedAt: link.updatedAt,
      ),
    for (final log in logs)
      RecentActivity(
        type: ActivityType.workLog,
        title: log.title,
        updatedAt: log.updatedAt,
      ),
  ];

  items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return items.take(5).toList(growable: false);
});
