import 'package:forui/forui.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// The date plus a compact overdue/due-today summary under the header.
class SummaryLine extends StatelessWidget {
  const SummaryLine({super.key, required this.overdue, required this.dueToday});

  final int overdue;
  final int dueToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final date = DateFormat('EEEE, MMMM d').format(DateTime.now());
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          date,
          style: context.theme.typography.body.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
        if (overdue > 0)
          FBadge(variant: .destructive, child: Text('$overdue overdue')),
        if (dueToday > 0)
          FBadge(variant: .primary, child: Text('$dueToday due today')),
      ],
    );
  }
}
