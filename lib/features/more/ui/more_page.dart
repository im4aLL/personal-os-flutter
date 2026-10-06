import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';

/// More tab: entry points to the feature pages that are not bottom tabs.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: const FHeader(title: Text('More')),
      child: FTileGroup(
        label: const Text('Features'),
        children: [
          FTile(
            prefix: const Icon(Icons.link),
            title: const Text('Links'),
            subtitle: const Text('Saved links and tags'),
            suffix: const Icon(Icons.chevron_right),
            onPress: () => Navigator.of(context).pushNamed(AppRoutes.links),
          ),
          FTile(
            prefix: const Icon(Icons.work_outline),
            title: const Text('Work Log'),
            subtitle: const Text('Entries grouped by ISO week'),
            suffix: const Icon(Icons.chevron_right),
            onPress: () => Navigator.of(context).pushNamed(AppRoutes.workLog),
          ),
          FTile(
            prefix: const Icon(Icons.folder_outlined),
            title: const Text('Projects'),
            subtitle: const Text('Week-based Gantt planner'),
            suffix: const Icon(Icons.chevron_right),
            onPress: () => Navigator.of(context).pushNamed(AppRoutes.projects),
          ),
        ],
      ),
    );
  }
}
