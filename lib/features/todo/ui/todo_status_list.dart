import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/todo.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/todo_providers.dart';
import 'todo_card.dart';

/// One status tab: the filtered todo cards.
///
/// New todos are created from the page-level floating add button, so this list
/// reflects the stream for its status. Long-pressing a card starts a drag that
/// reorders the tab; dropping persists the new order via the todo `position`
/// column.
///
/// Positions are scoped per status: `watchByStatus` filters before sorting, so
/// each tab is ordered independently. `watchAll` (the global position-ordered
/// stream Home reads) therefore sees a cross-status order that is not
/// meaningful and may shift when a tab is reordered.
class TodoStatusList extends ConsumerWidget {
  const TodoStatusList({super.key, required this.status});

  final TodoStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosByStatusProvider(status));
    final query = ref.watch(
      todoFilterProvider.select((filter) => filter.query),
    );

    return todos.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: FCircularProgress()),
      error: (_, _) => const CenteredMessage('Could not load todos.'),
      data: (items) {
        // Horizontal inset comes from the outer tabs wrapper; keep vertical
        // only. Extra bottom padding clears the floating add button.
        const padding = EdgeInsets.fromLTRB(0, 4, 0, 88);
        if (items.isEmpty) {
          return ListView(
            padding: padding,
            children: [AppEmptyState(_emptyMessage(status, query))],
          );
        }
        // Reordering rewrites positions from the visible order, so it is only
        // safe while no search filter hides siblings from `items`.
        final reorderable = query.trim().isEmpty;
        return ReorderableListView.builder(
          padding: padding,
          buildDefaultDragHandles: false,
          itemCount: items.length,
          // [onReorderItem] already adjusts the index for the removed item, so
          // the target index needs no correction.
          onReorderItem: (oldIndex, newIndex) =>
              unawaited(_reorder(context, ref, items, oldIndex, newIndex)),
          itemBuilder: (context, index) {
            final todo = items[index];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(todo.id),
              index: index,
              enabled: reorderable,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TodoCard(todo: todo),
              ),
            );
          },
        );
      },
    );
  }

  /// Persists the order produced by dragging the card at [oldIndex] to
  /// [newIndex] within the visible [items].
  ///
  /// Only rows whose slot actually changed are written, so a drag leaves
  /// unrelated todos untouched. The drop is not reflected optimistically: the
  /// list re-sorts from the stream once the write and its stream emission land,
  /// and a failed write leaves the previous order.
  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<Todo> items,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0 || newIndex >= items.length) return;
    try {
      final ordered = List<Todo>.of(items);
      final moved = ordered.removeAt(oldIndex);
      ordered.insert(newIndex, moved);
      // Only rows whose slot actually changed need a write (and a mirrored
      // upsert), so a drag does not touch unrelated todos.
      final updates = <({String id, int position})>[
        for (var i = 0; i < ordered.length; i++)
          if (ordered[i].position != i) (id: ordered[i].id, position: i),
      ];
      if (updates.isEmpty) return;
      await ref.read(todoRepositoryProvider).updatePositions(updates);
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not reorder todos'),
        );
      }
    }
  }

  /// The empty message for this tab, distinguishing "nothing here" from
  /// "nothing matches the search".
  String _emptyMessage(TodoStatus status, String query) {
    final needle = query.trim();
    if (needle.isNotEmpty) return 'No todos match "$needle".';
    return switch (status) {
      TodoStatus.todo => 'No todos yet. Tap + to add one.',
      TodoStatus.inProgress => 'Nothing in progress.',
      TodoStatus.completed => 'Nothing done yet.',
    };
  }
}
