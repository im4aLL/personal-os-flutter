import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';
import '../providers/todo_providers.dart';
import 'todo_status_list.dart';

/// The three status tabs: Todo / In Progress / Done.
///
/// Each label carries the live count for its status (matching the reference
/// column headers); the count reacts to the shared search query because it
/// comes from the same filtered provider the list uses.
class TodoStatusTabs extends ConsumerWidget {
  const TodoStatusTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The whole tabs block (bar + content) sits in the 16px content gutter.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FTabs(
        expands: true,
        children: [
          FTabEntry(
            label: _TabLabel(
              'Todo',
              count: ref
                  .watch(todosByStatusProvider(TodoStatus.todo))
                  .value
                  ?.length,
            ),
            child: const TodoStatusList(status: TodoStatus.todo),
          ),
          FTabEntry(
            label: _TabLabel(
              'In Progress',
              count: ref
                  .watch(todosByStatusProvider(TodoStatus.inProgress))
                  .value
                  ?.length,
            ),
            child: const TodoStatusList(status: TodoStatus.inProgress),
          ),
          FTabEntry(
            label: _TabLabel(
              'Done',
              count: ref
                  .watch(todosByStatusProvider(TodoStatus.completed))
                  .value
                  ?.length,
            ),
            child: const TodoStatusList(status: TodoStatus.completed),
          ),
        ],
      ),
    );
  }
}

/// A status tab label with a trailing count.
///
/// The count is omitted while the list is still loading ([count] is null), and
/// the label scales down if a long name plus a large count would otherwise
/// overflow the equal-width tab slot.
class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: context.theme.typography.body.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ],
    ),
  );
}
