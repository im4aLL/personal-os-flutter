import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';

/// Appearance settings detail page, pushed over the shell from Settings.
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      // The list owns the content padding, so the scaffold must not add its
      // own page padding on top (which would use a smaller 12 inset than the
      // other pages' 16).
      childPad: false,
      // Nested (not root) so the header style matches the other pages;
      // `centerStart` keeps the title left-aligned.
      header: FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        prefixes: [
          FHeaderAction(
            icon: const Icon(Icons.arrow_back),
            onPress: () => Navigator.maybePop(context),
          ),
        ],
        title: const Text('Appearance'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FTileGroup(
            label: const Text('Theme'),
            children: [
              _themeTile(
                ref,
                ThemeMode.system,
                Icons.brightness_auto_outlined,
              ),
              _themeTile(ref, ThemeMode.light, Icons.light_mode_outlined),
              _themeTile(ref, ThemeMode.dark, Icons.dark_mode_outlined),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds one selectable theme mode row.
  FTile _themeTile(WidgetRef ref, ThemeMode mode, IconData icon) {
    final selected = ref.watch(themeModeProvider) == mode;

    return FTile(
      prefix: Icon(icon),
      title: Text(themeModeLabel(mode)),
      suffix: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onPress: () => ref.read(themeModeProvider.notifier).select(mode),
    );
  }
}
