import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/note_providers.dart';
import 'note_card.dart';

/// Notes tab: a searchable, pinned-first list of note cards.
///
/// The search query and its visibility live in [noteFilterProvider], so they
/// survive bottom-tab switches (the shell keeps this page alive in an
/// [IndexedStack]). List data is stream-based, so create/edit/pin/tag/delete
/// update the list instantly.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  /// Owns the search field's text so it can be cleared alongside the filter.
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Creates a blank note and opens its editor.
  Future<void> _createNote() async {
    try {
      // No title (null, matching the reference) and empty content on create.
      final note = await ref.read(noteRepositoryProvider).create();
      if (!mounted) return;
      // Clear an active search so the new (blank) note is not filtered out
      // when the user returns from the editor. The controller is cleared too,
      // so the visible field matches the now-unfiltered list.
      ref.read(noteFilterProvider.notifier).setQuery('');
      _searchController.clear();
      await Navigator.of(context).push(AppRoutes.noteEditor(note.id));
    } catch (_) {
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('Could not create note'),
        );
      }
    }
  }

  /// Toggles the search field.
  ///
  /// Hiding also clears the field's text so reopening starts empty; the shared
  /// query is cleared by [NoteNotifier.setShowSearch] at the same time.
  void _toggleSearch() {
    final showSearch = !ref.read(noteFilterProvider).showSearch;
    ref.read(noteFilterProvider.notifier).setShowSearch(showSearch);
    if (!showSearch) _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(filteredNotesProvider);
    final query = ref.watch(
      noteFilterProvider.select((filter) => filter.query),
    );
    final showSearch = ref.watch(
      noteFilterProvider.select((filter) => filter.showSearch),
    );

    return FScaffold(
      // The column owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      // Nested (not root) so the title font and the action icon size match the
      // Todo screen's header; `centerStart` keeps the title left-aligned.
      header: FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        title: const Text('Notes'),
        suffixes: [
          FHeaderAction(
            // The icon doubles as the toggle: an open field shows a close icon
            // so tapping it again reads as "dismiss search".
            icon: Icon(showSearch ? Icons.close : Icons.search),
            semanticsLabel: showSearch ? 'Hide search' : 'Search notes',
            onPress: _toggleSearch,
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              if (showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: _searchController,
                      onChange: (value) => ref
                          .read(noteFilterProvider.notifier)
                          .setQuery(value.text),
                    ),
                    hint: 'Search notes',
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
              Expanded(
                child: notes.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: FCircularProgress()),
                  error: (_, _) =>
                      const CenteredMessage('Could not load notes.'),
                  data: (items) => ListView(
                    // Extra bottom padding clears the floating add button.
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    children: [
                      if (items.isEmpty)
                        AppEmptyState(_emptyMessage(query))
                      else
                        for (final note in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: NoteCard(note: note),
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
              onPress: _createNote,
              semanticsLabel: 'New note',
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  /// The empty message for the list, distinguishing "nothing here" from
  /// "nothing matches the search".
  String _emptyMessage(String query) {
    final needle = query.trim();
    if (needle.isNotEmpty) return 'No notes match "$needle".';
    return 'No notes yet. Tap + to add one.';
  }
}
