import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/todo.dart';

/// Watches the todo with [id], re-emitting whenever the underlying store
/// changes.
///
/// Emits `null` when no such todo exists, e.g. it was deleted while its detail
/// page was open. The Home dashboard and the detail page share the same
/// [todoRepositoryProvider] instance, so a status change made on one is
/// reflected on the other without a refresh.
final todoByIdProvider = StreamProvider.family<Todo?, String>((ref, id) {
  return ref.watch(todoRepositoryProvider).watchAll().map((todos) {
    for (final todo in todos) {
      if (todo.id == id) return todo;
    }
    return null;
  });
});

/// Filter state for the Todo tab.
///
/// Held in a [Notifier] (rather than widget-local state) so the search query,
/// its visibility, and the archived view survive tab switches: the app shell
/// keeps [TodoPage] alive in an [IndexedStack], and the filter outlives even
/// that. List data itself stays stream-based ([todosByStatusProvider],
/// [archivedTodosProvider]) so repository mutations update every tab instantly.
class TodoFilter {
  /// Creates a [TodoFilter].
  const TodoFilter({
    this.query = '',
    this.showArchived = false,
    this.showSearch = false,
  });

  /// Text matched (case-insensitively) against title and description.
  final String query;

  /// Whether the archived list replaces the status tabs.
  final bool showArchived;

  /// Whether the search field is visible in the header.
  final bool showSearch;

  /// Returns a copy with the given fields replaced.
  TodoFilter copyWith({String? query, bool? showArchived, bool? showSearch}) =>
      TodoFilter(
        query: query ?? this.query,
        showArchived: showArchived ?? this.showArchived,
        showSearch: showSearch ?? this.showSearch,
      );
}

/// Owns the [TodoFilter] for the Todo tab.
class TodoNotifier extends Notifier<TodoFilter> {
  @override
  TodoFilter build() => const TodoFilter();

  /// Replaces the search query shared across all tabs.
  void setQuery(String query) {
    if (query != state.query) state = state.copyWith(query: query);
  }

  /// Shows the archived list (`true`) or the status tabs (`false`).
  void setShowArchived(bool value) {
    if (value != state.showArchived) {
      state = state.copyWith(showArchived: value);
    }
  }

  /// Shows (`true`) or hides (`false`) the search field.
  ///
  /// Hiding the field also clears [TodoFilter.query]; otherwise the list would
  /// stay filtered with no visible control explaining why.
  void setShowSearch(bool value) {
    if (value == state.showSearch) return;
    state = state.copyWith(showSearch: value, query: value ? state.query : '');
  }
}

/// The [TodoFilter] for the Todo tab.
final todoFilterProvider = NotifierProvider<TodoNotifier, TodoFilter>(
  TodoNotifier.new,
);

/// Whether [todo] matches [query] (case-insensitive title/description match).
bool _matchesQuery(Todo todo, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  if (todo.title.toLowerCase().contains(needle)) return true;
  final description = todo.description;
  return description != null && description.toLowerCase().contains(needle);
}

/// Non-archived todos with [status], narrowed by the shared search query.
///
/// Stream-based: a create/edit/move/archive/delete re-emits and the tab list
/// updates without a refresh.
final todosByStatusProvider = StreamProvider.family<List<Todo>, TodoStatus>((
  ref,
  status,
) {
  final query = ref.watch(todoFilterProvider.select((filter) => filter.query));
  return ref
      .watch(todoRepositoryProvider)
      .watchByStatus(status)
      .map(
        (todos) => [
          for (final todo in todos)
            if (_matchesQuery(todo, query)) todo,
        ],
      );
});

/// Archived todos, narrowed by the shared search query.
final archivedTodosProvider = StreamProvider<List<Todo>>((ref) {
  final query = ref.watch(todoFilterProvider.select((filter) => filter.query));
  return ref
      .watch(todoRepositoryProvider)
      .watchArchived()
      .map(
        (todos) => [
          for (final todo in todos)
            if (_matchesQuery(todo, query)) todo,
        ],
      );
});
