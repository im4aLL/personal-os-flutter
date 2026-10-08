import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';
import '../providers/todo_providers.dart';
import 'todo_archived_list.dart';
import 'todo_edit_sheet.dart';
import 'todo_status_tabs.dart';

/// Todo tab: per-status lists with search and an archived view.
///
/// The search query, its visibility, and the archived view live in
/// [todoFilterProvider], so they survive bottom-tab switches (the shell keeps
/// this page alive in an [IndexedStack], and the filter outlives even that).
/// List data is stream-based, so mutations update every list instantly.
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  /// Creates a todo in the default [TodoStatus.todo] status.
  ///
  /// The floating button is status-agnostic, so new todos always start in the
  /// Todo column; the user moves them from there.
  Future<void> _createTodo(BuildContext context) async {
    final saved = await showTodoEditSheet(
      context: context,
      initialStatus: TodoStatus.todo,
    );
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Todo created'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArchived = ref.watch(
      todoFilterProvider.select((filter) => filter.showArchived),
    );
    final showSearch = ref.watch(
      todoFilterProvider.select((filter) => filter.showSearch),
    );

    return FScaffold(
      // The column owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      header: FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        prefixes: showArchived
            ? [
                FHeaderAction(
                  icon: const Icon(Icons.arrow_back),
                  semanticsLabel: 'Back to todos',
                  onPress: () => ref
                      .read(todoFilterProvider.notifier)
                      .setShowArchived(false),
                ),
              ]
            : [],
        title: Text(showArchived ? 'Archived' : 'Todo'),
        suffixes: [
          FHeaderAction(
            // Filled while the archived list is showing, so the action doubles
            // as a status indicator for the current view.
            icon: Icon(showArchived ? Icons.archive : Icons.archive_outlined),
            semanticsLabel: showArchived
                ? 'Back to todos'
                : 'View archived todos',
            onPress: () => ref
                .read(todoFilterProvider.notifier)
                .setShowArchived(!showArchived),
          ),
          FHeaderAction(
            // The icon doubles as the toggle: an open field shows a close icon
            // so tapping it again reads as "dismiss search".
            icon: Icon(showSearch ? Icons.close : Icons.search),
            semanticsLabel: showSearch ? 'Hide search' : 'Search todos',
            onPress: () => ref
                .read(todoFilterProvider.notifier)
                .setShowSearch(!showSearch),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              if (showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      onChange: (value) => ref
                          .read(todoFilterProvider.notifier)
                          .setQuery(value.text),
                    ),
                    hint: 'Search todos',
                    autofocus: true,
                    // Forui paints its own clear button when the predicate
                    // holds; clearing routes back through [onChange], so the
                    // filter resets.
                    clearable: (value) => value.text.isNotEmpty,
                    prefixBuilder: (context, style, variants) =>
                        FTextField.prefixIconBuilder(
                          context,
                          style,
                          variants,
                          const Icon(Icons.search),
                        ),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: showArchived ? 1 : 0,
                  children: const [TodoStatusTabs(), ArchivedTodoList()],
                ),
              ),
            ],
          ),
          // The archived view is read-only, so the add button is hidden there.
          if (!showArchived)
            Positioned(
              right: 16,
              bottom: 16,
              child: FButton.icon(
                variant: .primary,
                size: .lg,
                onPress: () => _createTodo(context),
                semanticsLabel: 'New todo',
                child: const Icon(Icons.add),
              ),
            ),
        ],
      ),
    );
  }
}
