import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drift/database.dart';
import 'drift/drift_link_repository.dart';
import 'drift/drift_note_repository.dart';
import 'drift/drift_project_repository.dart';
import 'drift/drift_settings_repository.dart';
import 'drift/drift_todo_repository.dart';
import 'drift/drift_work_log_repository.dart';
import 'repositories.dart';

/// Repository providers.
///
/// Phase 9 replaced the in-memory mocks with the drift implementations here;
/// this is the only place the swap happens, so UI and state code keep reading
/// the interfaces unchanged. The mock implementations remain in
/// `lib/core/data/mock/` for `ProviderScope` overrides (demos, widget previews,
/// and manual verification).
final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => DriftTodoRepository(ref.watch(appDatabaseProvider)),
);

/// Notes repository.
final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => DriftNoteRepository(ref.watch(appDatabaseProvider)),
);

/// Links repository.
final linkRepositoryProvider = Provider<LinkRepository>(
  (ref) => DriftLinkRepository(ref.watch(appDatabaseProvider)),
);

/// Work log repository.
final workLogRepositoryProvider = Provider<WorkLogRepository>(
  (ref) => DriftWorkLogRepository(ref.watch(appDatabaseProvider)),
);

/// Projects repository.
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => DriftProjectRepository(ref.watch(appDatabaseProvider)),
);

/// Shared `app_settings` repository.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(appDatabaseProvider)),
);
