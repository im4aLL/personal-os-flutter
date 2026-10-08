import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'padded_card.dart';

/// A shared empty-state placeholder: a muted message inside a bordered [FCard].
///
/// Forui's card decoration is the single source of the border/radius/background
/// treatment, so this replaces the per-feature bespoke bordered containers that
/// used to duplicate it.
class AppEmptyState extends StatelessWidget {
  /// Creates an [AppEmptyState] showing [label].
  const AppEmptyState(this.label, {super.key});

  /// The message to display.
  final String label;

  @override
  Widget build(BuildContext context) {
    return FCard(
      builder: paddedCardBuilder,
      child: Text(
        label,
        style: context.theme.typography.body.sm.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    );
  }
}
