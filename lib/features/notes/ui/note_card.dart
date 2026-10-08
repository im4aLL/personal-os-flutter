import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/models/note.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/padded_card.dart';

/// One note card: display title, content snippet, tag badges, pinned indicator,
/// updated-at, and a pin toggle.
///
/// A tap opens the editor for the note; the trailing pin toggle acts without
/// leaving the list.
class NoteCard extends ConsumerWidget {
  const NoteCard({super.key, required this.note});

  final NoteWithTags note;

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(noteRepositoryProvider)
          .setPinned(note.id, !note.pinned);
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not update note'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final snippet = _snippet(note.content);

    return FTappable(
      onPress: () => Navigator.of(context).push(AppRoutes.noteEditor(note.id)),
      child: FCard(
        // Tighter than the default 16 so the cards read as compact list items.
        style: const .delta(
          padding: .value(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        builder: paddedCardBuilder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // The pin rides inline with the title's first line so it
                  // stays vertically centered regardless of type scale.
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (note.pinned)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.push_pin,
                                size: 14,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        TextSpan(text: noteDisplayTitle(note.note)),
                      ],
                    ),
                    style: context.theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FButton.icon(
                  variant: .ghost,
                  size: .xs,
                  onPress: () => _togglePin(context, ref),
                  semanticsLabel: note.pinned ? 'Unpin note' : 'Pin note',
                  child: Icon(
                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                ),
              ],
            ),
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                snippet,
                style: context.theme.typography.body.xs.copyWith(
                  color: colors.mutedForeground,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in note.tags)
                  FBadge(variant: .outline, child: Text(tag)),
                Text(
                  formatDateTimeShort(note.updatedAt),
                  style: context.theme.typography.body.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapses markdown whitespace so a multi-line note reads as one snippet.
String _snippet(String content) =>
    content.replaceAll(RegExp(r'\s+'), ' ').trim();
