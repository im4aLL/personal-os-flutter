import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/work_log.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/delete_confirm_dialog.dart';
import '../../../core/widgets/padded_card.dart';
import 'work_log_edit_sheet.dart';

/// One work log card: title, date range, description snippet, tag badges, and
/// an actions menu.
class WorkLogCard extends ConsumerWidget {
  /// Creates a [WorkLogCard] for [log].
  const WorkLogCard({super.key, required this.log});

  /// The work log entry to display.
  final WorkLogWithTags log;

  Future<void> _edit(BuildContext context) async {
    final saved = await showWorkLogEditSheet(context: context, log: log);
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Work log saved'));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete work log?',
      body: '"${log.title}" will be permanently deleted.',
    );
    if (!confirmed) return;

    try {
      await ref.read(workLogRepositoryProvider).delete(log.id);
      if (context.mounted) {
        showFToast(context: context, title: const Text('Work log deleted'));
      }
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete work log'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    // The popover menu builders below shadow `context` with the overlay's
    // context, which unmounts as the menu closes. Capture the card's context so
    // the menu actions keep a mounted context to show dialogs and toasts from.
    final cardContext = context;
    final range = formatDateRange(log.startDate, log.endDate);
    final description = log.description?.trim();

    return FCard(
      // Tighter than the default 16 so the cards read as compact list items.
      style: const .delta(
        padding: .value(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      ),
      builder: paddedCardBuilder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.title,
                  style: context.theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  range,
                  style: context.theme.typography.body.xs.copyWith(
                    color: colors.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: context.theme.typography.body.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (log.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in log.tags)
                        FBadge(variant: .outline, child: Text(tag)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          FPopoverMenu(
            builder: (context, controller, _) => FButton.icon(
              variant: .ghost,
              size: .xs,
              semanticsLabel: 'Work log actions',
              onPress: controller.toggle,
              child: const Icon(Icons.more_vert),
            ),
            menuBuilder: (context, controller, _) => [
              FItemGroup(
                divider: .full,
                children: [
                  FItem(
                    prefix: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onPress: () {
                      controller.hide();
                      _edit(cardContext);
                    },
                  ),
                  FItem(
                    variant: .destructive,
                    prefix: const Icon(Icons.delete_outline),
                    title: const Text('Delete'),
                    onPress: () {
                      controller.hide();
                      _delete(cardContext, ref);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
