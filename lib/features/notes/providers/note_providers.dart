import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/note.dart';

/// All notes' metadata with tags, pinned first then most recently updated.
///
/// Distinct from Home's `notesProvider` so the Notes tab can narrow to a search
/// query without touching the dashboard's counts or recent activity. Bodies are
/// intentionally absent: the editor fetches the one it opens via
/// `NoteRepository.getById`, so a list refresh never re-reads every note body.
final noteSummariesProvider = StreamProvider<List<NoteSummary>>(
  (ref) => ref.watch(noteRepositoryProvider).watchSummaries(),
);

/// Filter state for the Notes tab.
///
/// Held in a [Notifier] (rather than widget-local state) so the search query
/// and its visibility survive bottom-tab switches: the app shell keeps the
/// Notes page alive in an [IndexedStack], and the filter outlives even that.
/// List data itself stays stream-based ([filteredNotesProvider]) so repository
/// mutations update the list instantly.
class NoteFilter {
  /// Creates a [NoteFilter].
  const NoteFilter({this.query = '', this.showSearch = false});

  /// Text matched (case-insensitively) against title and tags.
  final String query;

  /// Whether the search field is visible in the header.
  final bool showSearch;

  /// Returns a copy with the given fields replaced.
  NoteFilter copyWith({String? query, bool? showSearch}) => NoteFilter(
    query: query ?? this.query,
    showSearch: showSearch ?? this.showSearch,
  );
}

/// Owns the [NoteFilter] for the Notes tab.
class NoteNotifier extends Notifier<NoteFilter> {
  @override
  NoteFilter build() => const NoteFilter();

  /// Replaces the shared search query.
  void setQuery(String query) {
    if (query != state.query) state = state.copyWith(query: query);
  }

  /// Shows (`true`) or hides (`false`) the search field.
  ///
  /// Hiding the field also clears [NoteFilter.query]; otherwise the list would
  /// stay filtered with no visible control explaining why.
  void setShowSearch(bool value) {
    if (value == state.showSearch) return;
    state = state.copyWith(showSearch: value, query: value ? state.query : '');
  }
}

/// The [NoteFilter] for the Notes tab.
final noteFilterProvider = NotifierProvider<NoteNotifier, NoteFilter>(
  NoteNotifier.new,
);

/// Whether [note]'s title or tags match [query] (case-insensitive).
///
/// Body content is not searched: it is not loaded into the list (see
/// [noteSummariesProvider]).
bool _matchesQuery(NoteSummary note, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final title = note.title;
  if (title != null && title.toLowerCase().contains(needle)) return true;
  for (final tag in note.tags) {
    if (tag.toLowerCase().contains(needle)) return true;
  }
  return false;
}

/// Note summaries narrowed by the shared search query.
///
/// Derives from [noteSummariesProvider] so the query narrows the existing
/// stream instead of opening a second repository subscription, and preserves
/// its order: the repository already sorts pinned-first then
/// most-recently-updated, so a create/edit/pin/tag/delete updates the list
/// without a refresh.
final filteredNotesProvider = Provider<AsyncValue<List<NoteSummary>>>((ref) {
  final query = ref.watch(noteFilterProvider.select((filter) => filter.query));
  return ref
      .watch(noteSummariesProvider)
      .whenData(
        (notes) => [
          for (final note in notes)
            if (_matchesQuery(note, query)) note,
        ],
      );
});
