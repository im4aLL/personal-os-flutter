import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/widgets/padded_card.dart';

/// More tab: entry points to the feature pages that are not bottom tabs.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: const FHeader(title: Text('More')),
      child: Column(
        children: [
          _MoreCard(
            icon: Icons.link,
            title: 'Links',
            subtitle: 'Saved links and tags',
            onPress: () => Navigator.of(context).pushNamed(AppRoutes.links),
          ),
          const SizedBox(height: 12),
          _MoreCard(
            icon: Icons.work_outline,
            title: 'Work Log',
            subtitle: 'Entries grouped by ISO week',
            onPress: () => Navigator.of(context).pushNamed(AppRoutes.workLog),
          ),
          const SizedBox(height: 12),
          _MoreCard(
            icon: Icons.folder_outlined,
            title: 'Projects',
            subtitle: 'Week-based Gantt planner',
            onPress: () => Navigator.of(context).pushNamed(AppRoutes.projects),
          ),
        ],
      ),
    );
  }
}

/// One tappable navigation card.
class _MoreCard extends StatelessWidget {
  const _MoreCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onPress,
      child: FCard(
        builder: paddedCardBuilder,
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: context.theme.typography.body.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.mutedForeground),
          ],
        ),
      ),
    );
  }
}
