import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/link_providers.dart';
import 'link_card.dart';
import 'link_edit_sheet.dart';

/// Links page, pushed over the shell from the More tab.
///
/// The search query and active tag live in [linkFilterProvider], which is
/// auto-disposed, so the filter resets when this pushed page closes. List data
/// is stream-based, so add/edit/delete update the list instantly.
class LinksPage extends ConsumerStatefulWidget {
  const LinksPage({super.key});

  @override
  ConsumerState<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends ConsumerState<LinksPage> {
  /// Owns the search field's text so it can be cleared whenever the shared
  /// filter clears the query (hiding search, or selecting a tag).
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Toggles the search field.
  ///
  /// Hiding also clears the field's text; the shared query is cleared by
  /// [LinkNotifier.setShowSearch] at the same time.
  void _toggleSearch() {
    final showSearch = !ref.read(linkFilterProvider).showSearch;
    ref.read(linkFilterProvider.notifier).setShowSearch(showSearch);
    if (!showSearch) _searchController.clear();
  }

  /// Narrows the list to [tag], or clears the tag filter when it is already
  /// active. Clears the search field, since the tag filter replaces the query.
  void _toggleTag(String tag) {
    final activeTag = ref.read(linkFilterProvider).activeTag;
    // Case-insensitive so a casing drift between `activeTag` and the pill
    // label still toggles the filter off on the first tap.
    final isActive =
        activeTag != null && activeTag.toLowerCase() == tag.toLowerCase();
    ref.read(linkFilterProvider.notifier).setActiveTag(isActive ? null : tag);
    _searchController.clear();
  }

  /// Opens the add-link sheet and confirms a successful save.
  Future<void> _createLink() async {
    final saved = await showLinkEditSheet(context: context);
    if (saved && mounted) {
      showFToast(context: context, title: const Text('Link saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = ref.watch(filteredLinksProvider);
    final tags = ref.watch(allLinkTagsProvider);
    final filter = ref.watch(linkFilterProvider);
    final activeTag = filter.activeTag;
    // Keep the active tag's pill visible even after its last link disappears,
    // so the filter always has a tap-to-clear affordance.
    final pills = [
      ...tags,
      // Case-insensitive: allLinkTagsProvider dedupes case-insensitively while
      // preserving first casing, so an exact-match test could append a
      // differently-cased duplicate of an existing pill.
      if (activeTag != null &&
          !tags.any((t) => t.toLowerCase() == activeTag.toLowerCase()))
        activeTag,
    ];

    return FScaffold(
      // The column owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      header: FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        title: const Text('Links'),
        suffixes: [
          FHeaderAction(
            // The icon doubles as the toggle: an open field shows a close icon
            // so tapping it again reads as "dismiss search".
            icon: Icon(filter.showSearch ? Icons.close : Icons.search),
            semanticsLabel: filter.showSearch ? 'Hide search' : 'Search links',
            onPress: _toggleSearch,
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              if (filter.showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: _searchController,
                      // Ignore notifications whose text already matches the
                      // filter (programmatic clears, caret/focus changes);
                      // otherwise a tag tap's controller clear would echo
                      // through and wipe the tag that was just selected.
                      onChange: (value) {
                        if (value.text != ref.read(linkFilterProvider).query) {
                          ref
                              .read(linkFilterProvider.notifier)
                              .setQuery(value.text);
                        }
                      },
                    ),
                    hint: 'Search links',
                    autofocus: true,
                    // Forui paints its own clear button when the predicate
                    // holds; clearing routes back through [onChange], so the
                    // filter resets.
                    clearable: (value) => value.text.isNotEmpty,
                    prefixBuilder: (context, style, variants) =>
                        FTextField.prefixIconBuilder(
                          context,
                          style,
                          variants,
                          const Icon(Icons.search),
                        ),
                  ),
                ),
              if (pills.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _tagPills(pills, activeTag),
                ),
              Expanded(
                child: links.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: FCircularProgress()),
                  error: (_, _) =>
                      const CenteredMessage('Could not load links.'),
                  data: (items) => ListView(
                    // Extra bottom padding clears the floating add button.
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    children: [
                      if (items.isEmpty)
                        AppEmptyState(
                          _emptyMessage(filter.query, filter.activeTag),
                        )
                      else
                        for (final link in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: LinkCard(link: link),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FButton.icon(
              variant: .primary,
              size: .lg,
              onPress: _createLink,
              semanticsLabel: 'New link',
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  /// A horizontally scrollable row of tag filter pills.
  ///
  /// The active tag is filled (`.primary`); tapping it again clears the filter.
  Widget _tagPills(List<String> tags, String? activeTag) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final tag in tags)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FTappable(
                onPress: () => _toggleTag(tag),
                child: FBadge(
                  variant:
                      activeTag != null &&
                          activeTag.toLowerCase() == tag.toLowerCase()
                      ? .primary
                      : .outline,
                  child: Text(tag),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The empty message for the list, distinguishing a filtered result from an
  /// empty list.
  String _emptyMessage(String query, String? activeTag) {
    if (activeTag != null) return 'No links tagged "$activeTag".';
    final needle = query.trim();
    if (needle.isNotEmpty) return 'No links match "$needle".';
    return 'No links yet. Tap + to add one.';
  }
}
