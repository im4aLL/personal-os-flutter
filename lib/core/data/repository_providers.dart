import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drift/database.dart';
import 'drift/drift_link_repository.dart';
import 'drift/drift_note_repository.dart';
import 'drift/drift_project_repository.dart';
import 'drift/drift_settings_repository.dart';
import 'drift/drift_todo_repository.dart';
import 'drift/drift_work_log_repository.dart';
import 'remote_write_sink.dart';
import 'repositories.dart';

/// Repository providers.
///
/// Phase 9 replaced the in-memory mocks with the drift implementations here;
/// this is the only place the swap happens, so UI and state code keep reading
/// the interfaces unchanged. The mock implementations remain in
/// `lib/core/data/mock/` for `ProviderScope` overrides (demos, widget previews,
/// and manual verification).
///
/// Each repository also receives the optional [RemoteWriteSink] so every write
/// (creates, updates, deletes, tag replacements, phase edits) can be mirrored
/// to the remote store at mutation time.
/// The sink provider is stable (`null` unless the sync layer overrides it in
/// `main()`), so changing sync configuration never recreates a repository or
/// restarts its watch stream.
final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => DriftTodoRepository(
    ref.watch(appDatabaseProvider),
    writeSink: ref.watch(remoteWriteSinkProvider),
  ),
);

/// Notes repository.
final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => DriftNoteRepository(
    ref.watch(appDatabaseProvider),
    writeSink: ref.watch(remoteWriteSinkProvider),
  ),
);

/// Links repository.
final linkRepositoryProvider = Provider<LinkRepository>(
  (ref) => DriftLinkRepository(
    ref.watch(appDatabaseProvider),
    writeSink: ref.watch(remoteWriteSinkProvider),
  ),
);

/// Work log repository.
final workLogRepositoryProvider = Provider<WorkLogRepository>(
  (ref) => DriftWorkLogRepository(
    ref.watch(appDatabaseProvider),
    writeSink: ref.watch(remoteWriteSinkProvider),
  ),
);

/// Projects repository.
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => DriftProjectRepository(
    ref.watch(appDatabaseProvider),
    writeSink: ref.watch(remoteWriteSinkProvider),
  ),
);

/// Shared `app_settings` repository.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(appDatabaseProvider)),
);
