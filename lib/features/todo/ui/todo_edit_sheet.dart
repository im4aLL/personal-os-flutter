import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/todo.dart';
import '../../../core/utils/dates.dart';

/// Opens the add/edit todo sheet.
///
/// When [todo] is null a new todo is created with [initialStatus] (the status
/// of the tab the sheet was opened from); otherwise [todo] is updated and
/// [initialStatus] is ignored. Returns `true` when a save happened so the
/// caller can confirm with a toast.
Future<bool> showTodoEditSheet({
  required BuildContext context,
  Todo? todo,
  required TodoStatus initialStatus,
}) async {
  final saved = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    // The form is taller than the default 9/16 sheet budget on small phones,
    // so the sheet sizes to its scrollable content instead.
    mainAxisMaxRatio: null,
    builder: (_) => _TodoEditSheet(todo: todo, initialStatus: initialStatus),
  );
  return saved ?? false;
}

/// Add/edit todo form hosted in a bottom sheet.
class _TodoEditSheet extends ConsumerStatefulWidget {
  const _TodoEditSheet({required this.todo, required this.initialStatus});

  /// The todo being edited, or null when creating.
  final Todo? todo;

  /// The status a new todo is created with.
  final TodoStatus initialStatus;

  @override
  ConsumerState<_TodoEditSheet> createState() => _TodoEditSheetState();
}

class _TodoEditSheetState extends ConsumerState<_TodoEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  TodoPriority? _priority;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final todo = widget.todo;
    _titleController = TextEditingController(text: todo?.title ?? '');
    _descriptionController = TextEditingController(
      text: todo?.description ?? '',
    );
    _priority = todo?.priority;
    final dueDate = todo?.dueDate;
    _dueDate = dueDate == null ? null : parseDate(dueDate);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Whether the form can be saved right now.
  bool get _canSave => !_saving && _titleController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final description = _descriptionController.text.trim();
      final due = _dueDate;
      final dueDate = due == null
          ? null
          : formatDate(DateTime(due.year, due.month, due.day));
      final repository = ref.read(todoRepositoryProvider);
      final existing = widget.todo;
      if (existing == null) {
        await repository.create(
          title: title,
          description: description.isEmpty ? null : description,
          status: widget.initialStatus,
          priority: _priority,
          dueDate: dueDate,
        );
      } else {
        await repository.update(
          existing.copyWith(
            title: title,
            description: description.isEmpty ? null : description,
            priority: _priority,
            dueDate: dueDate,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(context: context, title: const Text('Could not save todo'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.todo;
    // showFSheet does not paint any background behind the builder content,
    // so the sheet paints the theme surface itself (with the usual top
    // rounded corners) to stay opaque in light and dark themes.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        borderRadius: context.theme.style.borderRadius.lg.copyWith(
          bottomLeft: Radius.zero,
          bottomRight: Radius.zero,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    existing == null ? 'New todo' : 'Edit todo',
                    style: context.theme.typography.body.lg.copyWith(
                      color: context.theme.colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FButton.icon(
                  variant: .ghost,
                  onPress: () => Navigator.of(context).pop(false),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _titleController,
                onChange: (_) => setState(() {}),
              ),
              label: const Text('Title'),
              hint: 'What needs doing?',
              autofocus: existing == null,
              textInputAction: .next,
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _descriptionController,
              ),
              label: const Text('Description'),
              hint: 'Optional details',
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            FSelect<TodoPriority>(
              control: FSelectControl.lifted(
                value: _priority,
                onChange: (value) => setState(() => _priority = value),
              ),
              items: const {
                'Low': TodoPriority.low,
                'Medium': TodoPriority.medium,
                'High': TodoPriority.high,
              },
              label: const Text('Priority'),
              hint: 'No priority',
              clearable: true,
            ),
            const SizedBox(height: 12),
            FDateField.calendar(
              selectionControl: FDateSelectionControl.liftedSingle(
                value: _dueDate,
                onChange: (value) => setState(() => _dueDate = value),
              ),
              label: const Text('Due date'),
              hint: 'No due date',
              clearable: true,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: .outline,
                    onPress: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FButton(
                    onPress: _canSave ? _save : null,
                    child: Text(_saving ? 'Saving...' : 'Save'),
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
