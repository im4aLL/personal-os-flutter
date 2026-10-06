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
      header: const FHeader(title: Text('Settings')),
      child: FTileGroup(
        label: const Text('Appearance'),
        children: [
          _themeTile(
            ref,
            ThemeMode.system,
            Icons.brightness_auto_outlined,
            'System',
          ),
          _themeTile(ref, ThemeMode.light, Icons.light_mode_outlined, 'Light'),
          _themeTile(ref, ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
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
