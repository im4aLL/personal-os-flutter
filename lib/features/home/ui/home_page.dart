import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/shell_state.dart';
import '../../../core/models/todo.dart';
import '../providers/home_providers.dart';
import 'count_card_data.dart';
import 'count_grid.dart';
import 'recent_activity_list.dart';
import 'section_title.dart';
import 'summary_line.dart';
import 'todo_section.dart';

/// Home dashboard: greeting, due/overdue todos, feature counts, recent activity.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueToday = ref.watch(dueTodayTodosProvider);
    final overdue = ref.watch(overdueTodosProvider);
    final recent = ref.watch(recentActivityProvider);

    void open(Todo todo) =>
        Navigator.of(context).push(AppRoutes.todoDetail(todo.id));

    final cards = <CountCardData>[
      CountCardData(
        id: 'todo',
        label: 'Todo',
        count: ref.watch(openTodoCountProvider),
        icon: Icons.check_circle_outline,
        onPress: () =>
            ref.read(selectedTabProvider.notifier).select(AppTab.todo),
      ),
      CountCardData(
        id: 'notes',
        label: 'Notes',
        count: ref.watch(noteCountProvider),
        icon: Icons.sticky_note_2_outlined,
        onPress: () =>
            ref.read(selectedTabProvider.notifier).select(AppTab.notes),
      ),
      CountCardData(
        id: 'links',
        label: 'Links',
        count: ref.watch(linkCountProvider),
        icon: Icons.link,
        onPress: () => Navigator.of(context).pushNamed(AppRoutes.links),
      ),
      CountCardData(
        id: 'work-log',
        label: 'Work Log',
        count: ref.watch(workLogCountProvider),
        icon: Icons.work_outline,
        onPress: () => Navigator.of(context).pushNamed(AppRoutes.workLog),
      ),
      CountCardData(
        id: 'projects',
        label: 'Projects',
        count: ref.watch(projectCountProvider),
        icon: Icons.folder_outlined,
        onPress: () => Navigator.of(context).pushNamed(AppRoutes.projects),
      ),
    ];

    return FScaffold(
      // The ListView owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      header: FHeader(
        // Align the header with the content, which is padded 16 horizontally.
        style: const .delta(
          padding: .value(EdgeInsets.fromLTRB(16, 8, 16, 10)),
        ),
        title: Text(_greeting(DateTime.now())),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SummaryLine(overdue: overdue.length, dueToday: dueToday.length),
          const SizedBox(height: 20),
          TodoSection(
            title: 'Due today',
            emptyLabel: 'Nothing due today.',
            todos: dueToday,
            onOpen: open,
          ),
          const SizedBox(height: 20),
          TodoSection(
            title: 'Overdue',
            emptyLabel: 'Nothing overdue.',
            todos: overdue,
            overdue: true,
            onOpen: open,
          ),
          const SizedBox(height: 24),
          SectionTitle('Overview'),
          const SizedBox(height: 12),
          CountGrid(cards: cards),
          const SizedBox(height: 24),
          SectionTitle('Recent activity'),
          const SizedBox(height: 12),
          RecentActivityList(items: recent),
        ],
      ),
    );
  }
}

/// Returns a time-of-day greeting.
String _greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}
