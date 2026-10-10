import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/sync/sync_config.dart';
import '../../../core/sync/sync_providers.dart';

/// Settings tab: a list of setting groups; tapping one opens its detail page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final sync = ref.watch(syncControllerProvider);

    return FScaffold(
      // The list owns the content padding, so the scaffold must not add its
      // own page padding on top (which would use a smaller 12 inset than the
      // other tab pages' 16).
      childPad: false,
      // Nested (not root) so the title font matches the other tab pages;
      // `centerStart` keeps the title left-aligned.
      header: const FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        title: Text('Settings'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FTileGroup(
            label: const Text('Preferences'),
            children: [
              FTile(
                prefix: const Icon(Icons.brightness_auto_outlined),
                title: const Text('Appearance'),
                details: Text(themeModeLabel(themeMode)),
                suffix: const Icon(Icons.chevron_right),
                onPress: () => Navigator.of(
                  context,
                ).pushNamed(AppRoutes.appearanceSettings),
              ),
              FTile(
                prefix: const Icon(Icons.sync),
                title: const Text('Sync'),
                details: Text(_syncModeLabel(sync.mode)),
                suffix: const Icon(Icons.chevron_right),
                onPress: () =>
                    Navigator.of(context).pushNamed(AppRoutes.syncSettings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The summary label for the sync entry's current mode.
  String _syncModeLabel(SyncMode mode) =>
      mode == SyncMode.cloud ? 'Cloud' : 'Local';
}
