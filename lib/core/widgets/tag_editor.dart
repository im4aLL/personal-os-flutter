import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Editable tag chips for an entity with tags.
///
/// Existing [tags] render as removable badges; the trailing field adds a tag on
/// submit. The whole list is emitted through [onChanged] so the parent owns the
/// state and the repository write. Empty and duplicate (case-insensitive) names
/// are ignored.
class TagEditor extends StatefulWidget {
  /// Creates a [TagEditor].
  const TagEditor({super.key, required this.tags, required this.onChanged});

  /// The current tag names, in display order.
  final List<String> tags;

  /// Called with the full replacement list after an add or remove.
  final ValueChanged<List<String>> onChanged;

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Adds the trimmed field value when it is non-empty and not already present.
  void _add() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    final exists = widget.tags.any(
      (tag) => tag.toLowerCase() == name.toLowerCase(),
    );
    _controller.clear();
    if (exists) {
      setState(() {});
      return;
    }

    widget.onChanged([...widget.tags, name]);
    setState(() {});
  }

  /// Removes [tag], matching case-insensitively like [_add] prevents duplicates.
  void _remove(String tag) => widget.onChanged([
    ...widget.tags.where((name) => name.toLowerCase() != tag.toLowerCase()),
  ]);

  @override
  Widget build(BuildContext context) {
    final canAdd = _controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in widget.tags)
                _TagChip(tag: tag, onRemove: () => _remove(tag)),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: FTextField(
                control: FTextFieldControl.managed(
                  controller: _controller,
                  onChange: (_) => setState(() {}),
                ),
                hint: 'Add tag',
                textInputAction: .done,
                onSubmit: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FButton.icon(
              variant: .outline,
              onPress: canAdd ? _add : null,
              semanticsLabel: 'Add tag',
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

/// A removable tag badge.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.onRemove});

  final String tag;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: onRemove,
      semanticsLabel: 'Remove tag $tag',
      child: FBadge(
        variant: .secondary,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tag),
            const SizedBox(width: 4),
            const Icon(Icons.close, size: 14),
          ],
        ),
      ),
    );
  }
}
