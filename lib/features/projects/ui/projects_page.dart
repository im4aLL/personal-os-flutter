import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/project_providers.dart';
import 'project_card.dart';
import 'project_edit_sheet.dart';

/// Projects page, pushed over the shell from the More tab.
///
/// Shows the list of projects; tapping one opens its detail page
/// ([ProjectDetailPage] via [AppRoutes.projectDetail]), which owns the week
/// Gantt, phases, and work items. List data is stream-based, so
/// add/edit/delete update the list instantly.
class ProjectsPage extends ConsumerStatefulWidget {
  /// Creates a [ProjectsPage].
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  /// Opens the add-project sheet and confirms a successful save.
  Future<void> _createProject() async {
    final saved = await showProjectEditSheet(context: context);
    if (saved && mounted) {
      showFToast(context: context, title: const Text('Project saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);

    return FScaffold(
      // The list owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      header: FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        title: const Text('Projects'),
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.add),
            semanticsLabel: 'New project',
            onPress: _createProject,
          ),
        ],
      ),
      child: projectsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: FCircularProgress()),
        error: (_, _) => const CenteredMessage('Could not load projects.'),
        data: (projects) {
          if (projects.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
              children: const [
                AppEmptyState('No projects yet. Tap + to add one.'),
              ],
            );
          }
          return ListView.builder(
            // Extra bottom padding clears the floating add button.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
            itemCount: projects.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ProjectCard(project: projects[index]),
            ),
          );
        },
      ),
    );
  }
}
