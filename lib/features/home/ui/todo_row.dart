import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/todo.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/padded_card.dart';
import '../../todo/ui/todo_presentation.dart';

/// One tappable todo row that opens the single-todo detail page.
///
/// Completion is deliberately not offered here: a tap only navigates, so the
/// dashboard cannot change a todo's status by accident.
class TodoRow extends StatelessWidget {
  const TodoRow({
    super.key,
    required this.todo,
    required this.overdue,
    required this.onOpen,
  });

  final Todo todo;
  final bool overdue;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final priority = todo.priority;

    return FTappable(
      onPress: onOpen,
      child: FCard(
        // Tighter than the default 16 so the rows read as compact list items.
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
                    todo.title,
                    style: context.theme.typography.body.sm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (priority != null || todo.dueDate != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (priority != null)
                          FBadge(
                            variant: priorityVariant(priority),
                            child: Text(priorityLabel(priority)),
                          ),
                        if (todo.dueDate != null)
                          Text(
                            formatDateShort(todo.dueDate!),
                            style: context.theme.typography.body.xs.copyWith(
                              color: overdue
                                  ? colors.error
                                  : colors.mutedForeground,
                              fontWeight: overdue ? FontWeight.w600 : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Nudge the chevron down so it optically aligns with the title.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
