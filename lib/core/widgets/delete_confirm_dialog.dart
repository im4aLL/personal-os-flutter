import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Shows a destructive-confirm [FDialog] and returns whether the user confirmed.
///
/// The dialog always offers Cancel and a destructive Delete; callers supply the
/// feature-specific [title] and [body] strings.
Future<bool> showDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
}) async {
  final result = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: style.titleTextStyle),
            const SizedBox(height: 8),
            Text(body, style: style.bodyTextStyle),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: .outline,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    variant: .destructive,
                    onPress: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
