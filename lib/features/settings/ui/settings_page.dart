import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../core/sync/sync_config.dart';
import '../../../core/sync/sync_providers.dart';

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
        children: const [
          _AppearanceGroup(),
          SizedBox(height: 16),
          _SyncSettings(),
        ],
      ),
    );
  }
}

/// The light/dark/system selector.
class _AppearanceGroup extends ConsumerWidget {
  const _AppearanceGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FTileGroup(
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

/// The Sync group: local/cloud mode, Turso credentials, and sync status.
///
/// Credentials and mode live only in device-local shared_preferences (never in
/// `app_settings`), so they do not propagate to the desktop/TUI clients.
class _SyncSettings extends ConsumerStatefulWidget {
  const _SyncSettings();

  @override
  ConsumerState<_SyncSettings> createState() => _SyncSettingsState();
}

class _SyncSettingsState extends ConsumerState<_SyncSettings> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(syncControllerProvider);
    _urlController = TextEditingController(text: state.url);
    _tokenController = TextEditingController(text: state.token);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _save(SyncController controller) => controller.saveConfig(
    url: _urlController.text,
    token: _tokenController.text,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);

    return FTileGroup(
      label: const Text('Sync'),
      children: [
        _modeTile(
          controller,
          state,
          SyncMode.local,
          'Local',
          'Data stays on this device',
          Icons.phonelink_lock_outlined,
        ),
        _modeTile(
          controller,
          state,
          SyncMode.cloud,
          'Cloud',
          'Share one Turso database with desktop and TUI',
          Icons.cloud_outlined,
        ),
        if (state.isCloud) ...[
          _fieldTile(
            child: FTextFormField(
              control: FTextFieldControl.managed(controller: _urlController),
              label: const Text('Turso URL'),
              hint: 'libsql://your-database.turso.io',
              textInputAction: .next,
            ),
          ),
          _fieldTile(
            top: 0,
            child: FTextFormField.password(
              control: FTextFieldControl.managed(controller: _tokenController),
              label: const Text('Auth token'),
              textInputAction: .done,
              onSubmit: (_) => _save(controller),
            ),
          ),
          _fieldTile(
            top: 0,
            child: Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: .outline,
                    onPress: () => _save(controller),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FButton(
                    onPress: !state.isSyncing && state.canSync
                        ? () => controller.syncNow()
                        : null,
                    child: _syncButtonChild(state.isSyncing),
                  ),
                ),
              ],
            ),
          ),
          FTile(
            prefix: const Icon(Icons.schedule),
            title: const Text('Last synced'),
            details: Text(_lastSyncLabel(state.lastSyncAt)),
          ),
          if (state.skewWarning case final warning?)
            FTile(
              variant: .destructive,
              prefix: const Icon(Icons.warning_amber_outlined),
              title: Text(warning),
            ),
          if (state.lastError case final error?)
            FTile(
              variant: .destructive,
              prefix: const Icon(Icons.error_outline),
              title: Text(error),
            ),
        ],
      ],
    );
  }

  /// One selectable app-mode row.
  FTile _modeTile(
    SyncController controller,
    SyncState state,
    SyncMode mode,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = state.mode == mode;

    return FTile(
      prefix: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      suffix: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onPress: () => controller.setMode(mode),
    );
  }

  /// Wraps a non-tile control so it can live inside the tile group.
  FTile _fieldTile({required Widget child, double top = 12}) => FTile.raw(
    child: Padding(padding: EdgeInsets.fromLTRB(16, top, 16, 12), child: child),
  );

  Widget _syncButtonChild(bool syncing) {
    if (!syncing) return const Text('Sync now');

    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FCircularProgress(size: .sm),
        SizedBox(width: 8),
        Text('Syncing...'),
      ],
    );
  }

  /// Formats a stored `lastSyncAt` timestamp for display.
  String _lastSyncLabel(String? iso) {
    if (iso == null) return 'Never';
    try {
      return DateFormat.yMMMd().add_jm().format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}
