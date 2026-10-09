import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';

/// Settings tab.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            label: const Text('Appearance'),
            children: [
              _themeTile(
                ref,
                ThemeMode.system,
                Icons.brightness_auto_outlined,
                'System',
              ),
              _themeTile(
                ref,
                ThemeMode.light,
                Icons.light_mode_outlined,
                'Light',
              ),
              _themeTile(ref, ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds one selectable theme mode row.
  FTile _themeTile(WidgetRef ref, ThemeMode mode, IconData icon, String label) {
    final selected = ref.watch(themeModeProvider) == mode;

    return FTile(
      prefix: Icon(icon),
      title: Text(label),
      suffix: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onPress: () => ref.read(themeModeProvider.notifier).select(mode),
    );
  }
}
