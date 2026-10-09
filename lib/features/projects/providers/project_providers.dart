import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/project.dart';

/// All projects ordered by position.
///
/// Auto-disposed because the Projects pages are pushed over the shell: the
/// subscription lives only while a page is open.
final projectsProvider = StreamProvider.autoDispose<List<Project>>(
  (ref) => ref.watch(projectRepositoryProvider).watchProjects(),
);

/// The project with [id], or `null` when it no longer exists.
///
/// Derived from [projectsProvider] so the detail page updates instantly on
/// add/edit/delete without a second repository subscription. Auto-disposed
/// with the page.
final projectByIdProvider = Provider.autoDispose
    .family<AsyncValue<Project?>, String>(
      (ref, id) => ref.watch(projectsProvider).whenData((projects) {
        for (final project in projects) {
          if (project.id == id) return project;
        }
        return null;
      }),
    );

/// The single instant shared by the project meta lines and the Gantt
/// current-week highlight.
///
/// Both read this instead of calling `DateTime.now()` directly, so the
/// "current week Wn" text and the highlighted column cannot desync when a
/// build spans a day/week boundary. The value is created once per page
/// session (provider lifetime, not per build) and is not refreshed: there is
/// no timer or auto-refresh, matching the rest of the repo, so a page left
/// open across midnight keeps its original now until reopened.
final projectsNowProvider = Provider.autoDispose<DateTime>(
  (ref) => DateTime.now(),
);

/// The phases of the project with the given id, ordered by position.
final phasesProvider = StreamProvider.autoDispose
    .family<List<ProjectPhase>, String>(
      (ref, projectId) =>
          ref.watch(projectRepositoryProvider).watchPhases(projectId),
    );

/// The work items of the project with the given id with resolved phases,
/// ordered by position.
final workItemsProvider = StreamProvider.autoDispose
    .family<List<WorkItemWithPhase>, String>(
      (ref, projectId) =>
          ref.watch(projectRepositoryProvider).watchWorkItems(projectId),
    );
