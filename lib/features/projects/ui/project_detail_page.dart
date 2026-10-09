import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/project.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/delete_confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/project_providers.dart';
import 'phase_edit_sheet.dart';
import 'project_edit_sheet.dart';
import 'project_gantt.dart';
import 'work_item_dialog.dart';

/// Detail page for one project, opened from the Projects list.
///
/// Shows the project's week Gantt ([ProjectGantt]) with project, phase, and
/// work item management around it. The project is looked up by id through
/// [projectByIdProvider], so a rename/edit updates the header immediately and
/// a delete (here or from another client) surfaces the gone state.
class ProjectDetailPage extends ConsumerWidget {
  /// Creates a [ProjectDetailPage].
  const ProjectDetailPage({required this.projectId, super.key});

  /// The id of the project to display.
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectByIdProvider(projectId));

    return FScaffold(
      // The body owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      header: FHeader.nested(
        prefixes: [
          FHeaderAction(
            icon: const Icon(Icons.arrow_back),
            onPress: () => Navigator.maybePop(context),
          ),
        ],
        title: const Text('Project'),
      ),
      child: projectAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: FCircularProgress()),
        error: (_, _) => const CenteredMessage('Could not load this project.'),
        data: (project) => project == null
            ? const CenteredMessage('This project no longer exists.')
            : _ProjectDetail(project: project),
      ),
    );
  }
}

/// The loaded project: name, meta actions, phases, the Gantt grid, and the
/// floating add-work-item button.
class _ProjectDetail extends ConsumerStatefulWidget {
  /// Creates a [_ProjectDetail].
  const _ProjectDetail({required this.project});

  /// The project being displayed.
  final Project project;

  @override
  ConsumerState<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends ConsumerState<_ProjectDetail> {
  /// Whether the phases list is expanded.
  ///
  /// Collapsed by default so the timeline stays the focus; tapping the
  /// "Phases" header toggles the list.
  bool _phasesExpanded = false;

  /// The project being displayed.
  Project get project => widget.project;

  /// Opens the edit-project sheet and confirms a successful save.
  Future<void> _editProject(BuildContext context) async {
    final saved = await showProjectEditSheet(
      context: context,
      project: project,
    );
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Project saved'));
    }
  }

  /// Confirms the project delete, then pops back to the list.
  Future<void> _deleteProject(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete project?',
      body:
          '"${project.name}" and all its phases and work items '
          'will be permanently deleted.',
    );
    if (!confirmed) return;
    try {
      await ref.read(projectRepositoryProvider).deleteProject(project.id);
      if (context.mounted) {
        showFToast(context: context, title: const Text('Project deleted'));
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete project'),
        );
      }
    }
  }

  /// Opens the add-phase sheet and confirms a successful save.
  Future<void> _createPhase(BuildContext context) async {
    final saved = await showPhaseEditSheet(
      context: context,
      projectId: project.id,
    );
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Phase saved'));
    }
  }

  /// Opens the edit-phase sheet and confirms a successful save.
  Future<void> _editPhase(BuildContext context, ProjectPhase phase) async {
    final saved = await showPhaseEditSheet(
      context: context,
      projectId: project.id,
      phase: phase,
    );
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Phase saved'));
    }
  }

  /// Confirms and deletes a phase; its items survive as ungrouped (their
  /// `phase_id` is cleared with the delete).
  Future<void> _deletePhase(
    BuildContext context,
    WidgetRef ref,
    ProjectPhase phase,
  ) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete phase?',
      body:
          '"${phase.name}" will be deleted. '
          'Items in this phase will become ungrouped.',
    );
    if (!confirmed) return;
    try {
      await ref.read(projectRepositoryProvider).deletePhase(phase.id);
      if (context.mounted) {
        showFToast(context: context, title: const Text('Phase deleted'));
      }
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete phase'),
        );
      }
    }
  }

  /// Opens the work item sheet for a new item, guarding against phases that
  /// have not loaded yet (the sheet needs them for its phase select).
  Future<void> _createItem(BuildContext context, WidgetRef ref) async {
    final phases = ref.read(phasesProvider(project.id)).value;
    if (phases == null) {
      showFToast(context: context, title: const Text('Still loading project'));
      return;
    }
    await openWorkItemSheet(context, project, phases);
  }

  /// Opens the edit-item sheet and confirms a successful save.
  Future<void> _editItem(
    BuildContext context,
    WorkItemWithPhase item,
    List<ProjectPhase> phases,
  ) async {
    final saved = await showWorkItemEditSheet(
      context: context,
      projectId: project.id,
      phases: phases,
      weekCount: project.weekCount,
      item: item,
    );
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Work item saved'));
    }
  }

  /// Moves the dragged item from [oldIndex] to [newIndex] within the flat
  /// position-ordered list and persists the new order.
  ///
  /// Dropping a row onto the row below it lands after that row, and dropping
  /// onto the row above lands before it, so a one-step drag always swaps the
  /// pair. The grid renders the same flat order, so the result is visible
  /// immediately.
  Future<void> _reorderItems(
    BuildContext context,
    WidgetRef ref,
    int oldIndex,
    int newIndex,
  ) async {
    final items = ref.read(workItemsProvider(project.id)).value;
    if (items == null) return;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0 || newIndex >= items.length) return;
    if (oldIndex == newIndex) return;
    final ordered = List<WorkItemWithPhase>.of(items);
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    try {
      await ref.read(projectRepositoryProvider).reorderWorkItems(project.id, [
        for (final item in ordered) item.id,
      ]);
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not move work item'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phasesAsync = ref.watch(phasesProvider(project.id));
    final itemsAsync = ref.watch(workItemsProvider(project.id));
    // The single instant shared with the grid highlight, so the meta line and
    // the highlighted column cannot desync at a day/week boundary.
    final now = ref.watch(projectsNowProvider);
    final currentWeek = currentWeekFor(project, now: now);

    return Stack(
      children: [
        ListView(
          // Extra bottom padding clears the floating add button.
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: context.theme.typography.body.lg.copyWith(
                          color: context.theme.colors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _metaLine(project, currentWeek),
                        style: context.theme.typography.body.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  onPress: () => _editProject(context),
                  semanticsLabel: 'Edit project',
                  child: const Icon(Icons.edit),
                ),
                FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  onPress: () => _deleteProject(context, ref),
                  semanticsLabel: 'Delete project',
                  child: const Icon(Icons.delete),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FTappable(
                    onPress: () =>
                        setState(() => _phasesExpanded = !_phasesExpanded),
                    child: Row(
                      children: [
                        Icon(
                          _phasesExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                          color: context.theme.colors.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Phases',
                          style: context.theme.typography.body.sm.copyWith(
                            color: context.theme.colors.mutedForeground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FButton.icon(
                  variant: .ghost,
                  size: .sm,
                  onPress: () => _createPhase(context),
                  semanticsLabel: 'New phase',
                  child: const Icon(Icons.add),
                ),
              ],
            ),
            if (_phasesExpanded) ...[
              const SizedBox(height: 4),
              phasesAsync.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: FCircularProgress()),
                error: (_, _) =>
                    const CenteredMessage('Could not load phases.'),
                data: (phases) {
                  if (phases.isEmpty) {
                    return const AppEmptyState(
                      'No phases yet. Work items will show under "No phase".',
                    );
                  }
                  return Column(
                    children: [
                      for (final phase in phases)
                        _PhaseRow(
                          phase: phase,
                          onEdit: () => _editPhase(context, phase),
                          onDelete: () => _deletePhase(context, ref, phase),
                        ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Timeline',
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            itemsAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: FCircularProgress()),
              error: (_, _) =>
                  const CenteredMessage('Could not load work items.'),
              data: (items) {
                // Branch on the phases state itself: reading `.value` here
                // would strand the timeline in a spinner when phases fail to
                // load.
                return phasesAsync.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: FCircularProgress()),
                  error: (_, _) =>
                      const CenteredMessage('Could not load phases.'),
                  data: (phases) {
                    if (items.isEmpty) {
                      return const AppEmptyState(
                        'No work items yet. Tap + to add one.',
                      );
                    }
                    return ProjectGantt(
                      project: project,
                      items: items,
                      now: now,
                      onEditItem: (item) => _editItem(context, item, phases),
                      onReorder: (oldIndex, newIndex) =>
                          _reorderItems(context, ref, oldIndex, newIndex),
                    );
                  },
                );
              },
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FButton.icon(
            variant: .primary,
            size: .lg,
            onPress: () => _createItem(context, ref),
            semanticsLabel: 'New work item',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  /// The muted meta line under the project name: start date, week count, and
  /// the current week when today falls inside the project range.
  ///
  /// A malformed start date from the shared DB falls back to a placeholder
  /// instead of throwing during build.
  String _metaLine(Project project, int? currentWeek) {
    String start;
    try {
      start = formatDateShort(project.startDate);
    } catch (_) {
      start = 'unknown date';
    }
    final base = 'Starts $start - ${project.weekCount} weeks';
    if (currentWeek == null) return base;
    return '$base - current week W$currentWeek';
  }
}

/// Opens the add-item sheet for [project] and confirms a successful save.
///
/// Kept as a top-level function so the page FAB and the Gantt's trailing add
/// button share one implementation and cannot drift apart.
Future<void> openWorkItemSheet(
  BuildContext context,
  Project project,
  List<ProjectPhase> phases,
) async {
  final saved = await showWorkItemEditSheet(
    context: context,
    projectId: project.id,
    phases: phases,
    weekCount: project.weekCount,
  );
  if (saved && context.mounted) {
    showFToast(context: context, title: const Text('Work item saved'));
  }
}

/// One phase row: color dot, name, and edit/delete actions.
class _PhaseRow extends StatelessWidget {
  /// Creates a [_PhaseRow].
  const _PhaseRow({
    required this.phase,
    required this.onEdit,
    required this.onDelete,
  });

  /// The phase to display.
  final ProjectPhase phase;

  /// Called when the edit button is pressed.
  final VoidCallback onEdit;

  /// Called when the delete button is pressed.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: phaseColor(
              phase.color,
              context.theme.colors.mutedForeground,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            phase.name,
            style: context.theme.typography.body.sm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FButton.icon(
          variant: .ghost,
          size: .sm,
          onPress: onEdit,
          semanticsLabel: 'Edit ${phase.name}',
          child: const Icon(Icons.edit),
        ),
        FButton.icon(
          variant: .ghost,
          size: .sm,
          onPress: onDelete,
          semanticsLabel: 'Delete ${phase.name}',
          child: const Icon(Icons.delete),
        ),
      ],
    );
  }
}
