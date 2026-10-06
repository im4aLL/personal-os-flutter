import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/utils/dates.dart';
import '../providers/home_providers.dart';
import 'empty_state.dart';

/// Merged recent-activity list.
class RecentActivityList extends StatelessWidget {
  const RecentActivityList({super.key, required this.items});

  final List<RecentActivity> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState('No activity yet.');
    }

    return FTileGroup(
      children: [
        for (final item in items)
          FTile(
            prefix: Icon(_iconFor(item.type)),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_labelFor(item.type)),
            suffix: Text(
              formatDateTimeShort(item.updatedAt),
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ),
      ],
    );
  }
}

IconData _iconFor(ActivityType type) => switch (type) {
  ActivityType.note => Icons.sticky_note_2_outlined,
  ActivityType.link => Icons.link,
  ActivityType.workLog => Icons.work_outline,
};

String _labelFor(ActivityType type) => switch (type) {
  ActivityType.note => 'Note',
  ActivityType.link => 'Link',
  ActivityType.workLog => 'Work log',
};
