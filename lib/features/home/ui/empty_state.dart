import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// An empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          side: BorderSide(color: colors.border),
          borderRadius: context.theme.style.borderRadius.lg,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Text(
          label,
          style: context.theme.typography.body.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
