import '../models/sentinel.dart';

/// Which database the app reads and writes.
enum SyncMode {
  /// Device-local only; Turso is never contacted.
  local,

  /// Local-first, with Turso sync enabled.
  cloud;

  /// Parses a stored mode name, defaulting to [local] when absent/unknown.
  static SyncMode fromName(String? name) => name == cloud.name ? cloud : local;
}

/// Device-local shared_preferences keys for sync configuration.
///
/// These are deliberately namespaced and never written to `app_settings`: the
/// desktop keeps Turso credentials in localStorage, so they are per-device and
/// must not propagate to other clients.
const String syncModePrefKey = 'sync.mode';
const String syncTursoUrlPrefKey = 'sync.turso_url';
const String syncTursoTokenPrefKey = 'sync.turso_token';
const String syncLastSyncAtPrefKey = 'sync.last_sync_at';

/// The observable sync configuration and run status.
class SyncState {
  /// Creates a [SyncState].
  const SyncState({
    this.mode = SyncMode.local,
    this.url = '',
    this.token = '',
    this.isSyncing = false,
    this.lastSyncAt,
    this.lastError,
    this.skewWarning,
  });

  /// The current app mode.
  final SyncMode mode;

  /// The configured Turso URL (device-local).
  final String url;

  /// The configured Turso auth token (device-local).
  final String token;

  /// Whether a sync is currently running.
  final bool isSyncing;

  /// When the last successful sync finished (millisecond UTC ISO-8601).
  final String? lastSyncAt;

  /// The most recent manual sync error, or `null`.
  final String? lastError;

  /// The most recent clock-skew warning, or `null`.
  final String? skewWarning;

  /// Whether cloud mode is selected.
  bool get isCloud => mode == SyncMode.cloud;

  /// Whether a URL and token are both present.
  bool get isConfigured => url.trim().isNotEmpty && token.trim().isNotEmpty;

  /// Whether a sync can run right now.
  bool get canSync => isCloud && isConfigured;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields ([lastSyncAt], [lastError], [skewWarning]) use [unset] so
  /// an explicit `null` clears them.
  SyncState copyWith({
    SyncMode? mode,
    String? url,
    String? token,
    bool? isSyncing,
    Object? lastSyncAt = unset,
    Object? lastError = unset,
    Object? skewWarning = unset,
  }) => SyncState(
    mode: mode ?? this.mode,
    url: url ?? this.url,
    token: token ?? this.token,
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncAt: lastSyncAt == unset ? this.lastSyncAt : lastSyncAt as String?,
    lastError: lastError == unset ? this.lastError : lastError as String?,
    skewWarning: skewWarning == unset
        ? this.skewWarning
        : skewWarning as String?,
  );
}
