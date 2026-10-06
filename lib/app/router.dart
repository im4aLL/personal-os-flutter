import 'package:flutter/widgets.dart';

import '../features/links/ui/links_page.dart';
import '../features/projects/ui/projects_page.dart';
import '../features/worklog/ui/work_log_page.dart';

/// Named routes for the full-screen feature pages hosted by the More tab.
///
/// These push onto the root navigator; the five bottom tabs are not routes.
abstract final class AppRoutes {
  /// Saved links.
  static const links = '/links';

  /// Date-ranged work log entries.
  static const workLog = '/work-log';

  /// Week-based project Gantt planner.
  static const projects = '/projects';

  /// The route table registered on the [MaterialApp].
  static Map<String, WidgetBuilder> get routes => {
    links: (_) => const LinksPage(),
    workLog: (_) => const WorkLogPage(),
    projects: (_) => const ProjectsPage(),
  };
}
