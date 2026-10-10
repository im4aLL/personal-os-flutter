import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sync/sync_config.dart';
import '../../../core/sync/sync_providers.dart';

/// Sync settings detail page, pushed over the shell from Settings.
///
/// Credentials and mode live only in device-local shared_preferences (never in
/// `app_settings`), so they do not propagate to the desktop/TUI clients.
class SyncSettingsPage extends ConsumerStatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  ConsumerState<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends ConsumerState<SyncSettingsPage> {
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
        title: const Text('Sync'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FTileGroup(
            label: const Text('Mode'),
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
            ],
          ),
          if (state.isCloud) ...[
            const SizedBox(height: 16),
            FTileGroup(
              label: const Text('Connection'),
              children: [
                _fieldTile(
                  child: FTextFormField(
                    control: FTextFieldControl.managed(
                      controller: _urlController,
                    ),
                    label: const Text('Turso URL'),
                    hint: 'libsql://your-database.turso.io',
                    textInputAction: .next,
                  ),
                ),
                _fieldTile(
                  top: 0,
                  child: FTextFormField.password(
                    control: FTextFieldControl.managed(
                      controller: _tokenController,
                    ),
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
              ],
            ),
            const SizedBox(height: 16),
            FTileGroup(
              label: const Text('Status'),
              children: [
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
            ),
          ],
        ],
      ),
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
