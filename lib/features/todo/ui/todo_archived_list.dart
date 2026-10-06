import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../providers/todo_providers.dart';
import 'todo_card.dart';
import 'todo_empty_list.dart';

/// Archived todos with restore + delete actions.
class ArchivedTodoList extends ConsumerWidget {
  const ArchivedTodoList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(archivedTodosProvider);
    final query = ref.watch(
      todoFilterProvider.select((filter) => filter.query),
    );
    final searching = query.trim().isNotEmpty;

    return todos.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: FCircularProgress()),
      error: (_, _) =>
          const Center(child: Text('Could not load archived todos.')),
      data: (items) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (items.isEmpty)
            TodoEmptyList(
              searching
                  ? 'No archived todos match "${query.trim()}".'
                  : 'No archived todos.',
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                searching
                    ? '${items.length} ${items.length == 1 ? 'result' : 'results'}'
                    : '${items.length} archived',
                style: context.theme.typography.body.xs.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
            ),
            for (final todo in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TodoCard(todo: todo, archived: true),
              ),
          ],
        ],
      ),
    );
  }
}
