import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/models/todo.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/delete_confirm_dialog.dart';
import '../../../core/widgets/padded_card.dart';
import 'todo_actions_sheet.dart';
import 'todo_edit_sheet.dart';
import 'todo_presentation.dart';

/// One todo card: title, description, priority badge, due date, and an action
/// menu.
///
/// A tap opens the read-only detail page for a live todo; an archived card has
/// no detail page, so tapping it opens the restore/delete menu instead. The
/// trailing menu offers edit, move status, archive/restore, delete, and Add to
/// work log.
class TodoCard extends ConsumerWidget {
  const TodoCard({super.key, required this.todo, this.archived = false});

  final Todo todo;
  final bool archived;

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final action = await showFSheet<TodoAction>(
      context: context,
      side: FLayout.btt,
      builder: (_) => TodoActionsSheet(todo: todo, archived: archived),
    );
    if (action == null || !context.mounted) return;

    final todoRepository = ref.read(todoRepositoryProvider);
    switch (action) {
      case TodoAction.edit:
        final saved = await showTodoEditSheet(
          context: context,
          todo: todo,
          initialStatus: todo.status,
        );
        if (saved && context.mounted) {
          showFToast(context: context, title: const Text('Todo updated'));
        }
      case TodoAction.moveToTodo:
        try {
          await todoRepository.setStatus(todo.id, TodoStatus.todo);
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not update todo'),
            );
          }
        }
      case TodoAction.moveToInProgress:
        try {
          await todoRepository.setStatus(todo.id, TodoStatus.inProgress);
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not update todo'),
            );
          }
        }
      case TodoAction.moveToCompleted:
        try {
          await todoRepository.setStatus(todo.id, TodoStatus.completed);
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not update todo'),
            );
          }
        }
      case TodoAction.addToWorkLog:
        try {
          final today = todayDate();
          await ref
              .read(workLogRepositoryProvider)
              .create(
                title: todo.title,
                description: todo.description,
                startDate: today,
                endDate: today,
              );
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Added to work log'),
            );
          }
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not add to work log'),
            );
          }
        }
      case TodoAction.archive:
        try {
          await todoRepository.archive(todo.id);
          if (context.mounted) {
            showFToast(context: context, title: const Text('Todo archived'));
          }
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not archive todo'),
            );
          }
        }
      case TodoAction.restore:
        try {
          await todoRepository.restore(todo.id);
          if (context.mounted) {
            showFToast(context: context, title: const Text('Todo restored'));
          }
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not restore todo'),
            );
          }
        }
      case TodoAction.delete:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: 'Delete todo?',
          body: '"${todo.title}" will be permanently deleted.',
        );
        if (!confirmed) return;
        try {
          await todoRepository.delete(todo.id);
          if (context.mounted) {
            showFToast(context: context, title: const Text('Todo deleted'));
          }
        } catch (_) {
          if (context.mounted) {
            showFToast(
              context: context,
              title: const Text('Could not delete todo'),
            );
          }
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final priority = todo.priority;
    final completed = todo.status == TodoStatus.completed;
    final dueDate = todo.dueDate;
    final description = todo.description?.trim();
    // "Overdue" only makes sense while a todo is still on the board; an
    // archived item is done with and should not shout in error red.
    final overdue =
        !archived &&
        !completed &&
        dueDate != null &&
        dueDate.compareTo(todayDate()) < 0;

    return FTappable(
      // The detail page streams only live todos, so an archived card has no
      // page to open; its tap target opens the restore/delete menu instead.
      onPress: archived
          ? () => _openMenu(context, ref)
          : () => Navigator.of(context).push(AppRoutes.todoDetail(todo.id)),
      child: FCard(
        // Tighter than the default 16 so the cards read as compact list items.
        style: const .delta(
          padding: .value(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        builder: paddedCardBuilder,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: context.theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: context.theme.typography.body.xs.copyWith(
                        color: colors.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (archived || priority != null || dueDate != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (archived)
                          FBadge(
                            variant: statusVariant(todo.status),
                            child: Text(statusLabel(todo.status)),
                          ),
                        if (priority != null)
                          FBadge(
                            variant: priorityVariant(priority),
                            child: Text(priorityLabel(priority)),
                          ),
                        if (dueDate != null)
                          Text(
                            formatDateShort(dueDate),
                            style: context.theme.typography.body.xs.copyWith(
                              color: overdue
                                  ? colors.error
                                  : colors.mutedForeground,
                              fontWeight: overdue ? FontWeight.w600 : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Transform.translate(
              // Tighten the ghost icon button so its optical edge sits near the
              // card content's top-right: the md touch icon button is a 44px box
              // with all(13) padding, so without this the 18px icon sits
              // 13px inside the button (25/23 from the card border given the
              // card's 12/10 padding). The delta below keeps a 40px tap target
              // with symmetric all(11) padding, and this shift pulls the whole
              // 40px box 8px up/right, leaving the hover background 4px/2px
              // inside the card border.
              offset: const Offset(8, -8),
              child: FButton.icon(
                variant: .ghost,
                style: const .delta(
                  iconContentStyle: .delta(
                    padding: .value(EdgeInsets.all(11)),
                    constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),
                onPress: () => _openMenu(context, ref),
                child: const Icon(Icons.more_vert),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
