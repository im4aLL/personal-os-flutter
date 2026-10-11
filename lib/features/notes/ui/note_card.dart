import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/models/note.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/padded_card.dart';

/// One note card: display title, tag badges, pinned indicator, and updated-at.
///
/// A tap opens the editor for the note. Pinning is not offered here: a pinned
/// note shows a small pin marker, and pin/unpin happens in the editor, so the
/// list is not a pin control surface.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note});

  final NoteSummary note;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

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
            // The pin rides inline with the title's first line so it stays
            // vertically centered regardless of type scale. It marks state
            // only; pinning is done in the editor.
            Text.rich(
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
                          semanticLabel: 'Pinned',
                        ),
                      ),
                    ),
                  TextSpan(text: noteSummaryDisplayTitle(note)),
                ],
              ),
              style: context.theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
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
