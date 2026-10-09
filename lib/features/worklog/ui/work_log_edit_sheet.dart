import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/work_log.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/tag_editor.dart';

/// Opens the add/edit work log sheet.
///
/// When [log] is null a new entry is created; otherwise [log] is updated.
/// Returns `true` when a save happened so the caller can confirm with a toast.
Future<bool> showWorkLogEditSheet({
  required BuildContext context,
  WorkLogWithTags? log,
}) async {
  final saved = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    // The form is taller than the default 9/16 sheet budget on small phones,
    // so the sheet sizes to its scrollable content instead.
    mainAxisMaxRatio: null,
    builder: (_) => _WorkLogEditSheet(log: log),
  );
  return saved ?? false;
}

/// Add/edit work log form hosted in a bottom sheet.
class _WorkLogEditSheet extends ConsumerStatefulWidget {
  const _WorkLogEditSheet({required this.log});

  /// The entry being edited, or null when creating.
  final WorkLogWithTags? log;

  @override
  ConsumerState<_WorkLogEditSheet> createState() => _WorkLogEditSheetState();
}

class _WorkLogEditSheetState extends ConsumerState<_WorkLogEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  DateTime? _start;
  DateTime? _end;
  late List<String> _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final log = widget.log;
    _titleController = TextEditingController(text: log?.title ?? '');
    _descriptionController = TextEditingController(
      text: log?.description ?? '',
    );
    _start = log == null ? null : parseDate(log.startDate);
    _end = log == null ? null : parseDate(log.endDate);
    _tags = List<String>.of(log?.tags ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Whether the form can be saved right now.
  ///
  /// The title and both dates are required; the start <= end ordering is
  /// checked in [_save] so a violation reports a toast instead of silently
  /// disabling the button.
  bool get _canSave =>
      !_saving &&
      _titleController.text.trim().isNotEmpty &&
      _start != null &&
      _end != null;

  Future<void> _save() async {
    if (_saving) return;

    final title = _titleController.text.trim();
    final start = _start;
    final end = _end;
    if (title.isEmpty || start == null || end == null) return;

    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (startDay.isAfter(endDay)) {
      showFToast(
        context: context,
        title: const Text('Start date must be on or before end date'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final description = _descriptionController.text.trim();
      final startDate = formatDate(startDay);
      final endDate = formatDate(endDay);
      final repository = ref.read(workLogRepositoryProvider);
      final existing = widget.log;
      if (existing == null) {
        await repository.create(
          title: title,
          description: description.isEmpty ? null : description,
          startDate: startDate,
          endDate: endDate,
          tags: _tags,
        );
      } else {
        await repository.update(
          existing.workLog.copyWith(
            title: title,
            description: description.isEmpty ? null : description,
            startDate: startDate,
            endDate: endDate,
          ),
        );
        await repository.setTags(existing.id, _tags);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('Could not save work log'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.log;
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
                    existing == null ? 'New work log' : 'Edit work log',
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
              hint: 'What did you work on?',
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
            FDateField.calendar(
              selectionControl: FDateSelectionControl.liftedSingle(
                value: _start,
                onChange: (value) => setState(() => _start = value),
              ),
              label: const Text('Start date'),
              hint: 'Select start date',
              clearable: false,
            ),
            const SizedBox(height: 12),
            FDateField.calendar(
              selectionControl: FDateSelectionControl.liftedSingle(
                value: _end,
                onChange: (value) => setState(() => _end = value),
              ),
              label: const Text('End date'),
              hint: 'Select end date',
              clearable: false,
            ),
            const SizedBox(height: 12),
            TagEditor(
              tags: _tags,
              onChanged: (tags) => setState(() => _tags = tags),
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
