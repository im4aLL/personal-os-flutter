import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/drift/database.dart';
import '../data/remote_write_sink.dart';
import '../prefs/shared_preferences_provider.dart';
import '../utils/clock.dart';
import 'pending_write_store.dart';
import 'sync_config.dart';
import 'sync_engine.dart';
import 'turso_client.dart';

/// Holds the device-local sync configuration and run status.
final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// The Turso client, or `null` while cloud mode is off or unconfigured.
///
/// Watching the controller means this rebuilds when the mode/credentials
/// change; the engine reads it lazily through a factory, so the engine itself
/// is stable.
final tursoClientProvider = Provider<TursoClient?>((ref) {
  final state = ref.watch(syncControllerProvider);
  if (!state.canSync) return null;
  return TursoClient(url: state.url.trim(), token: state.token.trim());
});

/// The sync engine, stable for the app's lifetime.
///
/// Depends only on the database; the client is resolved lazily at call time so
/// changing sync configuration never recreates the engine (and therefore never
/// recreates repositories or restarts their watch streams).
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return SyncEngine(
    database,
    () =>
        ref.read(tursoClientProvider) ??
        (throw const TursoNotConfiguredException()),
  );
});

/// The stable [RemoteWriteSink] the repositories mirror writes to.
final syncWriteSinkProvider = Provider<RemoteWriteSink>(
  (ref) => ref.watch(syncEngineProvider),
);

/// Loads, saves, and runs the device-local sync configuration.
class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    return SyncState(
      mode: SyncMode.fromName(preferences.getString(syncModePrefKey)),
      url: preferences.getString(syncTursoUrlPrefKey) ?? '',
      token: preferences.getString(syncTursoTokenPrefKey) ?? '',
      lastSyncAt: preferences.getString(syncLastSyncAtPrefKey),
    );
  }

  /// Persists the Turso URL/token and, when in cloud mode, syncs.
  ///
  /// When the normalized URL actually changes (a different database), the
  /// local-only queue is cleared: it carries no database identity, so writes
  /// queued against the previous remote must not be flushed into the new one
  /// (the same offline writes the desktop would simply lose). A token-only
  /// change keeps the queue, so re-entering a rotated token against the same
  /// database does not drop queued offline writes. Saving identical values is a
  /// no-op.
  Future<void> saveConfig({required String url, required String token}) async {
    final preferences = ref.read(sharedPreferencesProvider);
    final trimmedUrl = url.trim();
    final trimmedToken = token.trim();
    // Key the clear on the normalized URL only: the token rotates routinely and
    // must not discard queued writes against the same database.
    final targetChanged =
        TursoClient.normalizeTursoUrl(trimmedUrl) !=
        TursoClient.normalizeTursoUrl(state.url);

    await preferences.setString(syncTursoUrlPrefKey, trimmedUrl);
    await preferences.setString(syncTursoTokenPrefKey, trimmedToken);
    state = state.copyWith(url: trimmedUrl, token: trimmedToken);

    if (targetChanged) {
      await PendingWriteStore(ref.read(appDatabaseProvider)).clear();
    }

    await _syncWhenCloud();
  }

  /// Switches the app mode and, when switching to cloud, syncs.
  Future<void> setMode(SyncMode mode) async {
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(syncModePrefKey, mode.name);
    state = state.copyWith(mode: mode);

    await _syncWhenCloud();
  }

  /// Runs a sync only when the engine sees a possible change on either side.
  ///
  /// Used by the automatic triggers (timer, resume, background, detach) so an
  /// idle device stays quiet. Manual syncs and config/mode changes use
  /// [syncNow] unconditionally: a new remote target needs bootstrapping even
  /// with nothing local to send.
  Future<void> syncIfChanged({bool silent = true}) async {
    if (state.isSyncing || !state.canSync) return;
    if (!await ref.read(syncEngineProvider).hasChanges(state.lastSyncAt)) {
      return;
    }
    await syncNow(silent: silent);
  }

  /// Runs a sync. When [silent], failures do not overwrite [SyncState.lastError]
  /// (used for the background sync on app resume).
  Future<void> syncNow({bool silent = false}) async {
    if (state.isSyncing || !state.canSync) return;

    state = state.copyWith(isSyncing: true);
    try {
      final result = await ref.read(syncEngineProvider).sync();
      final at = nowIso();
      await ref
          .read(sharedPreferencesProvider)
          .setString(syncLastSyncAtPrefKey, at);
      state = state.copyWith(
        isSyncing: false,
        lastSyncAt: at,
        lastError: null,
        skewWarning: result.skewWarning,
      );
    } catch (error) {
      state = state.copyWith(
        isSyncing: false,
        lastError: silent ? state.lastError : describeSyncError(error),
      );
    }
  }

  Future<void> _syncWhenCloud() async {
    if (!state.canSync) return;
    await syncNow();
  }
}

/// Formats a sync failure for display, trimming the exception type prefix.
String describeSyncError(Object error) {
  const prefix = 'TursoException: ';
  final text = error.toString();
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}
