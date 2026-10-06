import 'package:material_ui/material_ui.dart';

import '../features/links/ui/links_page.dart';
import '../features/projects/ui/projects_page.dart';
import '../features/todo/ui/todo_detail_page.dart';
import '../features/worklog/ui/work_log_page.dart';

/// Named routes for the feature pages hosted by the More tab.
///
/// These push onto the shell's inner navigator so the bottom navigation bar
/// stays visible; the five bottom tabs are not routes.
abstract final class AppRoutes {
  /// Saved links.
  static const links = '/links';

  /// Date-ranged work log entries.
  static const workLog = '/work-log';

  /// Week-based project Gantt planner.
  static const projects = '/projects';

  /// Builds the route for the single-todo detail page of [id].
  ///
  /// Parameterized detail routes are built as [Route]s rather than entries in
  /// [routes] because the id travels as a constructor argument.
  static Route<void> todoDetail(String id) =>
      MaterialPageRoute<void>(builder: (_) => TodoDetailPage(todoId: id));

  /// The route table registered on the [MaterialApp].
  static final Map<String, WidgetBuilder> routes = {
    links: (_) => const LinksPage(),
    workLog: (_) => const WorkLogPage(),
    projects: (_) => const ProjectsPage(),
  };
}
