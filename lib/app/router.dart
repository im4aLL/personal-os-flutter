import 'package:material_ui/material_ui.dart';

import '../features/links/ui/links_page.dart';
import '../features/notes/ui/note_editor_page.dart';
import '../features/projects/ui/project_detail_page.dart';
import '../features/projects/ui/projects_page.dart';
import '../features/settings/ui/appearance_settings_page.dart';
import '../features/settings/ui/sync_settings_page.dart';
import '../features/todo/ui/todo_detail_page.dart';
import '../features/worklog/ui/work_log_page.dart';

/// Named routes for pages pushed over the tab stack.
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

  /// Appearance settings detail.
  static const appearanceSettings = '/settings/appearance';

  /// Sync settings detail.
  static const syncSettings = '/settings/sync';

  /// Builds the route for the single-todo detail page of [id].
  ///
  /// Parameterized detail routes are built as [Route]s rather than entries in
  /// [routes] because the id travels as a constructor argument.
  static Route<void> todoDetail(String id) =>
      MaterialPageRoute<void>(builder: (_) => TodoDetailPage(todoId: id));

  /// Builds the route for the note editor of [id].
  ///
  /// Parameterized detail routes are built as [Route]s rather than entries in
  /// [routes] because the id travels as a constructor argument.
  static Route<void> noteEditor(String id) =>
      MaterialPageRoute<void>(builder: (_) => NoteEditorPage(noteId: id));

  /// Builds the route for the project detail page of [id].
  ///
  /// Parameterized detail routes are built as [Route]s rather than entries in
  /// [routes] because the id travels as a constructor argument.
  static Route<void> projectDetail(String id) =>
      MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: id));

  /// The route table registered on the [MaterialApp].
  static final Map<String, WidgetBuilder> routes = {
    links: (_) => const LinksPage(),
    workLog: (_) => const WorkLogPage(),
    projects: (_) => const ProjectsPage(),
    appearanceSettings: (_) => const AppearanceSettingsPage(),
    syncSettings: (_) => const SyncSettingsPage(),
  };
}
