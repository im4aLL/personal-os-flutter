import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// A centered, muted placeholder message for empty or missing content.
class CenteredMessage extends StatelessWidget {
  /// Creates a [CenteredMessage] showing [message].
  const CenteredMessage(this.message, {super.key});

  /// The message to display.
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.theme.typography.body.sm.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
    ),
  );
}
