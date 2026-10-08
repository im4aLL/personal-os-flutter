import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/note.dart';

/// All notes with tags, pinned first then most recently updated.
///
/// Distinct from Home's `notesProvider` so the Notes tab can narrow to a search
/// query without touching the dashboard's counts or recent activity.
final notesWithTagsProvider = StreamProvider<List<NoteWithTags>>(
  (ref) => ref.watch(noteRepositoryProvider).watchAll(),
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

  /// Text matched (case-insensitively) against title, content, and tags.
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

/// Whether [note] matches [query] (case-insensitive title/content/tag match).
bool _matchesQuery(NoteWithTags note, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final title = note.note.title;
  if (title != null && title.toLowerCase().contains(needle)) return true;
  if (note.content.toLowerCase().contains(needle)) return true;
  for (final tag in note.tags) {
    if (tag.toLowerCase().contains(needle)) return true;
  }
  return false;
}

/// Notes with tags narrowed by the shared search query.
///
/// Derives from [notesWithTagsProvider] so the query narrows the existing
/// stream instead of opening a second repository subscription, and preserves
/// its order: the repository already sorts pinned-first then
/// most-recently-updated, so a create/edit/pin/tag/delete updates the list
/// without a refresh.
final filteredNotesProvider = Provider<AsyncValue<List<NoteWithTags>>>((ref) {
  final query = ref.watch(noteFilterProvider.select((filter) => filter.query));
  return ref
      .watch(notesWithTagsProvider)
      .whenData(
        (notes) => [
          for (final note in notes)
            if (_matchesQuery(note, query)) note,
        ],
      );
});
