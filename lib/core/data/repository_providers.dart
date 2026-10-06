import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock/mock_link_repository.dart';
import 'mock/mock_note_repository.dart';
import 'mock/mock_project_repository.dart';
import 'mock/mock_settings_repository.dart';
import 'mock/mock_todo_repository.dart';
import 'mock/mock_work_log_repository.dart';
import 'repositories.dart';

/// Repository providers.
///
/// Phase 9 swaps each mock body for a drift implementation in exactly this
/// file; UI and state code never change. The plan shows this swap as:
///
/// ```dart
/// final todoRepositoryProvider = Provider<TodoRepository>(
///   // Phase 9: replace with DriftTodoRepository(ref.watch(appDatabaseProvider))
///   (ref) => MockTodoRepository.seeded(),
/// );
/// ```
final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => MockTodoRepository.seeded(),
);

/// Notes repository.
final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => MockNoteRepository.seeded(),
);

/// Links repository.
final linkRepositoryProvider = Provider<LinkRepository>(
  (ref) => MockLinkRepository.seeded(),
);

/// Work log repository.
final workLogRepositoryProvider = Provider<WorkLogRepository>(
  (ref) => MockWorkLogRepository.seeded(),
);

/// Projects repository.
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => MockProjectRepository.seeded(),
);

/// Shared `app_settings` repository.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => MockSettingsRepository.seeded(),
);
