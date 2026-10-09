import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/models/project.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/padded_card.dart';
import '../providers/project_providers.dart';
import 'project_gantt.dart';

/// One project row in the Projects list: name, start/week summary, and the
/// current-week badge when today falls inside the project's range.
///
/// Tapping opens the project detail page. The list owns no project state
/// beyond the shared repository stream, so create/edit/delete update it
/// instantly.
class ProjectCard extends ConsumerWidget {
  /// Creates a [ProjectCard].
  const ProjectCard({super.key, required this.project});

  /// The project to display.
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final now = ref.watch(projectsNowProvider);
    final currentWeek = currentWeekFor(project, now: now);

    return FTappable(
      onPress: () =>
          Navigator.of(context).push(AppRoutes.projectDetail(project.id)),
      child: FCard(
        // Tighter than the default 16 so the cards read as compact list items.
        style: const .delta(
          padding: .value(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        builder: paddedCardBuilder,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.name,
                    style: context.theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metaLine(project),
                    style: context.theme.typography.body.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (currentWeek != null) ...[
              const SizedBox(width: 8),
              FBadge(variant: .primary, child: Text('W$currentWeek')),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: colors.mutedForeground),
          ],
        ),
      ),
    );
  }

  /// The muted meta line under the project name: start date and week count.
  ///
  /// A malformed start date from the shared DB falls back to a placeholder
  /// instead of throwing during build.
  String _metaLine(Project project) {
    String start;
    try {
      start = formatDateShort(project.startDate);
    } catch (_) {
      start = 'unknown date';
    }
    return 'Starts $start - ${project.weekCount} weeks';
  }
}
