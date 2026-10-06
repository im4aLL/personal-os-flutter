import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../providers/todo_providers.dart';
import 'todo_archived_list.dart';
import 'todo_status_tabs.dart';

/// Todo tab: per-status lists with search and an archived view.
///
/// The search query and archived visibility live in [todoFilterProvider], so
/// they survive bottom-tab switches (the shell keeps this page alive in an
/// [IndexedStack], and the filter outlives even that). List data is
/// stream-based, so mutations update every list instantly.
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArchived = ref.watch(
      todoFilterProvider.select((filter) => filter.showArchived),
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
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FTextField(
              control: FTextFieldControl.managed(
                onChange: (value) =>
                    ref.read(todoFilterProvider.notifier).setQuery(value.text),
              ),
              hint: 'Search todos',
              // Forui paints its own clear button when the predicate holds;
              // clearing routes back through [onChange], so the filter resets.
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
    );
  }
}
