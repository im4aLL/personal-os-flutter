import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/todo_providers.dart';
import 'todo_card.dart';

/// One status tab: the filtered todo cards.
///
/// New todos are created from the page-level floating add button, so this list
/// is read-only and simply reflects the stream for its status.
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
      data: (items) => ListView(
        // Horizontal inset comes from the outer tabs wrapper; keep vertical
        // only. Extra bottom padding clears the floating add button.
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
        children: [
          if (items.isEmpty)
            AppEmptyState(_emptyMessage(status, query))
          else
            for (final todo in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TodoCard(todo: todo),
              ),
        ],
      ),
    );
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
