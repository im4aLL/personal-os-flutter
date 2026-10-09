import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/work_log.dart';
import '../../../core/utils/dates.dart';

/// All work logs with tags, newest start date first.
final workLogsWithTagsProvider = StreamProvider<List<WorkLogWithTags>>(
  (ref) => ref.watch(workLogRepositoryProvider).watchAll(),
);

/// The single instant shared by preset filtering, preset counts, and
/// week-label headers.
///
/// [filteredWorkLogsProvider], [workLogPresetCountsProvider], and the
/// [weekLabel] calls in the Work Log page all read this instead of calling
/// `DateTime.now()` directly, so filtering and headers cannot desync when a
/// build spans a day/week boundary. The value is created once per page
/// session (provider lifetime, not per build) and is not refreshed: there is
/// no timer or auto-refresh, matching the rest of the repo, so a page left
/// open across midnight keeps its original now until reopened.
final workLogNowProvider = Provider.autoDispose<DateTime>(
  (ref) => DateTime.now(),
);

/// Date preset narrowing the Work Log list by the entry start date.
enum WorkLogPreset {
  /// No date narrowing.
  all,

  /// Entries starting in the current ISO week.
  thisWeek,

  /// Entries starting in the previous ISO week.
  lastWeek,

  /// Entries starting in the current calendar month.
  thisMonth,
}

/// Filter state for the Work Log page.
///
/// Held in an auto-dispose [Notifier] so the search query, its visibility, and
/// the active preset reset when the pushed Work Log page closes, mirroring the
/// Links page filter. List data itself stays stream-based
/// ([filteredWorkLogsProvider]) so repository mutations update the list
/// instantly, including entries created from todos.
class WorkLogFilter {
  /// Creates a [WorkLogFilter].
  const WorkLogFilter({
    this.query = '',
    this.showSearch = false,
    this.preset = WorkLogPreset.all,
  });

  /// Text matched (case-insensitively) against title, description, and tags.
  final String query;

  /// Whether the search field is visible in the header.
  final bool showSearch;

  /// The active date preset.
  final WorkLogPreset preset;

  /// Returns a copy with the given fields replaced.
  WorkLogFilter copyWith({
    String? query,
    bool? showSearch,
    WorkLogPreset? preset,
  }) => WorkLogFilter(
    query: query ?? this.query,
    showSearch: showSearch ?? this.showSearch,
    preset: preset ?? this.preset,
  );
}

/// Owns the [WorkLogFilter] for the Work Log page.
class WorkLogNotifier extends Notifier<WorkLogFilter> {
  @override
  WorkLogFilter build() => const WorkLogFilter();

  /// Replaces the shared search query.
  void setQuery(String query) {
    if (query != state.query) state = state.copyWith(query: query);
  }

  /// Shows (`true`) or hides (`false`) the search field.
  ///
  /// Hiding the field also clears [WorkLogFilter.query]; otherwise the list
  /// would stay filtered with no visible control explaining why.
  void setShowSearch(bool value) {
    if (value == state.showSearch) return;
    state = state.copyWith(showSearch: value, query: value ? state.query : '');
  }

  /// Selects the active date [preset].
  void setPreset(WorkLogPreset preset) {
    if (preset != state.preset) state = state.copyWith(preset: preset);
  }
}

/// The [WorkLogFilter] for the Work Log page.
final workLogFilterProvider =
    NotifierProvider.autoDispose<WorkLogNotifier, WorkLogFilter>(
      WorkLogNotifier.new,
    );

/// Whether [log] matches [query] (case-insensitive title/description/tag
/// substring match).
bool _matchesQuery(WorkLogWithTags log, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  if (log.title.toLowerCase().contains(needle)) return true;
  final description = log.description;
  if (description != null && description.toLowerCase().contains(needle)) {
    return true;
  }
  for (final tag in log.tags) {
    if (tag.toLowerCase().contains(needle)) return true;
  }
  return false;
}

/// Whether [log] falls in [preset], comparing ISO week keys (or the `YYYY-MM`
/// prefix for [WorkLogPreset.thisMonth]) on the start date.
bool _matchesPreset(WorkLogWithTags log, WorkLogPreset preset, DateTime now) {
  switch (preset) {
    case WorkLogPreset.all:
      return true;
    case WorkLogPreset.thisWeek:
      return weekKey(log.startDate) == weekKey(todayDate(now));
    case WorkLogPreset.lastWeek:
      final today = parseDate(todayDate(now));
      final lastWeek = DateTime(today.year, today.month, today.day - 7);
      return weekKey(log.startDate) == weekKey(formatDate(lastWeek));
    case WorkLogPreset.thisMonth:
      return log.startDate.substring(0, 7) == todayDate(now).substring(0, 7);
  }
}

/// Work logs with tags narrowed by the active preset and search query.
///
/// Derives from [workLogsWithTagsProvider] so the filter narrows the existing
/// stream instead of opening a second repository subscription, and preserves
/// its order (newest start date first) so grouping headers stay chronological.
final filteredWorkLogsProvider =
    Provider.autoDispose<AsyncValue<List<WorkLogWithTags>>>((ref) {
      final (query, preset) = ref.watch(
        workLogFilterProvider.select((filter) => (filter.query, filter.preset)),
      );
      final now = ref.watch(workLogNowProvider);
      return ref
          .watch(workLogsWithTagsProvider)
          .whenData(
            (logs) => [
              for (final log in logs)
                if (_matchesPreset(log, preset, now) &&
                    _matchesQuery(log, query))
                  log,
            ],
          );
    });

/// Live per-preset counts for the preset tab labels.
///
/// Applies the shared search query (like the Todo status counts) but not the
/// active preset, so every tab shows how many entries it would display.
final workLogPresetCountsProvider = Provider.autoDispose<AsyncValue<List<int>>>(
  (ref) {
    final query = ref.watch(
      workLogFilterProvider.select((filter) => filter.query),
    );
    final now = ref.watch(workLogNowProvider);
    return ref
        .watch(workLogsWithTagsProvider)
        .whenData(
          (logs) => [
            for (final preset in WorkLogPreset.values)
              logs
                  .where(
                    (log) =>
                        _matchesPreset(log, preset, now) &&
                        _matchesQuery(log, query),
                  )
                  .length,
          ],
        );
  },
);
