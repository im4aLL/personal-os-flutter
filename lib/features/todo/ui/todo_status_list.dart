import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';
import '../providers/todo_providers.dart';
import 'todo_card.dart';
import 'todo_edit_sheet.dart';
import 'todo_empty_list.dart';

/// One status tab: per-status add button plus the filtered todo cards.
class TodoStatusList extends ConsumerWidget {
  const TodoStatusList({
    super.key,
    required this.status,
    required this.addLabel,
  });

  final TodoStatus status;
  final String addLabel;

  Future<void> _openAdd(BuildContext context, TodoStatus status) async {
    final saved = await showTodoEditSheet(
      context: context,
      initialStatus: status,
    );
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Todo created'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosByStatusProvider(status));
    final query = ref.watch(
      todoFilterProvider.select((filter) => filter.query),
    );

    return todos.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: FCircularProgress()),
      error: (_, _) => const Center(child: Text('Could not load todos.')),
      data: (items) => ListView(
        // Horizontal inset comes from the outer tabs wrapper; keep vertical only.
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
        children: [
          FButton(
            variant: .outline,
            prefix: const Icon(Icons.add),
            onPress: () => _openAdd(context, status),
            child: Text(addLabel),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            TodoEmptyList(_emptyMessage(status, query))
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
      TodoStatus.todo => 'No todos. Add one above.',
      TodoStatus.inProgress => 'Nothing in progress.',
      TodoStatus.completed => 'Nothing done yet.',
    };
  }
}
