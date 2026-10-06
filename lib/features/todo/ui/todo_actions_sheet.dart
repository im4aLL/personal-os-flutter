import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';

/// The actions offered for a todo in its bottom-sheet menu.
enum TodoAction {
  /// Opens the edit sheet.
  edit,

  /// Moves the todo to [TodoStatus.todo].
  moveToTodo,

  /// Moves the todo to [TodoStatus.inProgress].
  moveToInProgress,

  /// Moves the todo to [TodoStatus.completed].
  moveToCompleted,

  /// Creates a work log entry from the todo.
  addToWorkLog,

  /// Soft-deletes the todo.
  archive,

  /// Restores an archived todo.
  restore,

  /// Hard-deletes the todo.
  delete,
}

/// Bottom-sheet menu for one todo; returns the chosen [TodoAction].
class TodoActionsSheet extends StatelessWidget {
  const TodoActionsSheet({
    super.key,
    required this.todo,
    required this.archived,
  });

  final Todo todo;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    void pop(TodoAction action) => Navigator.of(context).pop(action);

    FTile tile({
      required IconData icon,
      required String label,
      required TodoAction action,
    }) => FTile(
      prefix: Icon(icon),
      title: Text(label),
      onPress: () => pop(action),
    );

    // showFSheet does not paint any background behind the builder content,
    // so the sheet paints the theme surface itself (with the usual top
    // rounded corners) to stay opaque in light and dark themes.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        borderRadius: context.theme.style.borderRadius.lg.copyWith(
          bottomLeft: Radius.zero,
          bottomRight: Radius.zero,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              todo.title,
              style: context.theme.typography.body.lg.copyWith(
                color: context.theme.colors.foreground,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (archived)
              FTileGroup(
                children: [
                  tile(
                    icon: Icons.unarchive_outlined,
                    label: 'Restore',
                    action: TodoAction.restore,
                  ),
                  tile(
                    icon: Icons.delete_outline,
                    label: 'Delete permanently',
                    action: TodoAction.delete,
                  ),
                ],
              )
            else
              FTileGroup(
                children: [
                  tile(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    action: TodoAction.edit,
                  ),
                  if (todo.status != TodoStatus.todo)
                    tile(
                      icon: Icons.radio_button_unchecked,
                      label: 'Move to Todo',
                      action: TodoAction.moveToTodo,
                    ),
                  if (todo.status != TodoStatus.inProgress)
                    tile(
                      icon: Icons.timelapse_outlined,
                      label: 'Move to In Progress',
                      action: TodoAction.moveToInProgress,
                    ),
                  if (todo.status != TodoStatus.completed)
                    tile(
                      icon: Icons.check_circle_outline,
                      label: 'Move to Done',
                      action: TodoAction.moveToCompleted,
                    ),
                  tile(
                    icon: Icons.work_outline,
                    label: 'Add to work log',
                    action: TodoAction.addToWorkLog,
                  ),
                  tile(
                    icon: Icons.archive_outlined,
                    label: 'Archive',
                    action: TodoAction.archive,
                  ),
                  tile(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    action: TodoAction.delete,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
