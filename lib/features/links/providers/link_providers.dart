import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/link.dart';
import '../../../core/models/sentinel.dart';

/// All links with tags, most recently created first.
final linksWithTagsProvider = StreamProvider<List<LinkWithTags>>(
  (ref) => ref.watch(linkRepositoryProvider).watchAll(),
);

/// Distinct tag names across all links, sorted case-insensitively.
///
/// Tags are deduped case-insensitively, preserving the first casing seen, so
/// the filter pills show one entry per logical tag.
final allLinkTagsProvider = Provider.autoDispose<List<String>>((ref) {
  final links = ref.watch(linksWithTagsProvider).value ?? const [];
  final byLowercase = <String, String>{};
  for (final link in links) {
    for (final tag in link.tags) {
      byLowercase.putIfAbsent(tag.toLowerCase(), () => tag);
    }
  }

  final tags = byLowercase.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return tags;
});

/// Filter state for the Links page.
///
/// Held in an auto-dispose [Notifier] so the search query and active tag reset
/// when the pushed Links page closes, unlike the bottom-tab feature filters.
/// Search and the tag filter are mutually exclusive, mirroring the reference
/// link list: typing a query clears the active tag and tapping a tag clears the
/// query.
class LinkFilter {
  /// Creates a [LinkFilter].
  const LinkFilter({this.query = '', this.activeTag, this.showSearch = false});

  /// Text matched (case-insensitively) against title and url.
  final String query;

  /// The selected tag, or `null` when no tag filter is active.
  final String? activeTag;

  /// Whether the search field is visible in the header.
  final bool showSearch;

  /// Returns a copy with the given fields replaced.
  ///
  /// [activeTag] uses [unset] so an explicit `null` clears it.
  LinkFilter copyWith({
    String? query,
    Object? activeTag = unset,
    bool? showSearch,
  }) => LinkFilter(
    query: query ?? this.query,
    activeTag: activeTag == unset ? this.activeTag : activeTag as String?,
    showSearch: showSearch ?? this.showSearch,
  );
}

/// Owns the [LinkFilter] for the Links page.
class LinkNotifier extends Notifier<LinkFilter> {
  @override
  LinkFilter build() => const LinkFilter();

  /// Replaces the shared search query, clearing any active tag filter.
  void setQuery(String query) {
    if (query == state.query && state.activeTag == null) return;
    state = state.copyWith(query: query, activeTag: null);
  }

  /// Sets the active tag ([tag]) or clears it (`null`), clearing the query.
  void setActiveTag(String? tag) {
    if (tag == state.activeTag && state.query.isEmpty) return;
    state = state.copyWith(activeTag: tag, query: '');
  }

  /// Shows (`true`) or hides (`false`) the search field.
  ///
  /// Hiding the field clears [LinkFilter.query] but keeps the active tag, so a
  /// tag filter stays visible through the pills.
  void setShowSearch(bool value) {
    if (value == state.showSearch) return;
    state = state.copyWith(showSearch: value, query: value ? state.query : '');
  }
}

/// The [LinkFilter] for the Links page.
final linkFilterProvider =
    NotifierProvider.autoDispose<LinkNotifier, LinkFilter>(LinkNotifier.new);

/// Whether [link] matches [tag] case-insensitively.
bool _matchesTag(LinkWithTags link, String tag) {
  final needle = tag.toLowerCase();
  return link.tags.any((name) => name.toLowerCase() == needle);
}

/// Whether [link] matches [query] (case-insensitive title/url substring match).
bool _matchesQuery(LinkWithTags link, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return link.title.toLowerCase().contains(needle) ||
      link.url.toLowerCase().contains(needle);
}

/// Links with tags narrowed by the active tag filter or search query.
///
/// Derives from [linksWithTagsProvider] so the filter narrows the existing
/// stream instead of opening a second repository subscription, and preserves
/// its order (most recently created first).
final filteredLinksProvider =
    Provider.autoDispose<AsyncValue<List<LinkWithTags>>>((ref) {
      final (activeTag, query) = ref.watch(
        linkFilterProvider.select((filter) => (filter.activeTag, filter.query)),
      );
      return ref
          .watch(linksWithTagsProvider)
          .whenData(
            (links) => [
              for (final link in links)
                if (activeTag != null
                    ? _matchesTag(link, activeTag)
                    : _matchesQuery(link, query))
                  link,
            ],
          );
    });
