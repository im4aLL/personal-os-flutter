import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/project.dart';
import '../../../core/utils/dates.dart';

/// Week-count presets offered by the project sheet (avoids free-form numeric
/// parsing).
const List<int> projectWeekCountOptions = [4, 6, 8, 12, 16, 20, 26, 52];

/// Opens the add/edit project sheet.
///
/// When [project] is null a new project is created; otherwise [project] is
/// updated. Returns `true` when a save happened so the caller can confirm with
/// a toast.
Future<bool> showProjectEditSheet({
  required BuildContext context,
  Project? project,
}) async {
  final saved = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    // The form is taller than the default 9/16 sheet budget on small phones,
    // so the sheet sizes to its scrollable content instead.
    mainAxisMaxRatio: null,
    builder: (_) => _ProjectEditSheet(project: project),
  );
  return saved ?? false;
}

/// Add/edit project form hosted in a bottom sheet.
class _ProjectEditSheet extends ConsumerStatefulWidget {
  const _ProjectEditSheet({required this.project});

  /// The project being edited, or null when creating.
  final Project? project;

  @override
  ConsumerState<_ProjectEditSheet> createState() => _ProjectEditSheetState();
}

class _ProjectEditSheetState extends ConsumerState<_ProjectEditSheet> {
  late final TextEditingController _nameController;
  DateTime? _startDate;
  late int _weekCount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _nameController = TextEditingController(text: project?.name ?? '');
    // A malformed start date from the shared DB must not crash the sheet:
    // fall back to null and let the required-field guard ask for a date.
    DateTime? startDate;
    if (project == null) {
      startDate = dateOnly(DateTime.now());
    } else {
      try {
        startDate = parseDate(project.startDate);
      } catch (_) {
        startDate = null;
      }
    }
    _startDate = startDate;
    _weekCount = project?.weekCount ?? 12;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Whether the form can be saved right now.
  ///
  /// The name and start date are required. The date is normally preset (today
  /// for new projects) and not clearable, but a malformed stored date loads
  /// as null, in which case the user picks one before saving.
  bool get _canSave =>
      !_saving && _nameController.text.trim().isNotEmpty && _startDate != null;

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final start = _startDate;
    if (name.isEmpty || start == null) return;

    setState(() => _saving = true);
    try {
      final startDate = formatDate(dateOnly(start));
      final repository = ref.read(projectRepositoryProvider);
      final existing = widget.project;
      if (existing == null) {
        await repository.createProject(
          name: name,
          startDate: startDate,
          weekCount: _weekCount,
        );
      } else {
        await repository.updateProject(
          existing.copyWith(
            name: name,
            startDate: startDate,
            weekCount: _weekCount,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('Could not save project'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.project;
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
                    existing == null ? 'New project' : 'Edit project',
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
                controller: _nameController,
                onChange: (_) => setState(() {}),
              ),
              label: const Text('Name'),
              hint: 'Project name',
              autofocus: existing == null,
              textInputAction: .next,
            ),
            const SizedBox(height: 12),
            FDateField.calendar(
              selectionControl: FDateSelectionControl.liftedSingle(
                value: _startDate,
                onChange: (value) => setState(() => _startDate = value),
              ),
              label: const Text('Start date'),
              hint: 'Select start date',
              clearable: false,
            ),
            const SizedBox(height: 12),
            FSelect<int>(
              control: FSelectControl.lifted(
                value: _weekCount,
                onChange: (value) {
                  if (value != null) setState(() => _weekCount = value);
                },
              ),
              items: {
                for (final weeks in projectWeekCountOptions)
                  '$weeks weeks': weeks,
              },
              label: const Text('Week count'),
              hint: 'Number of weeks',
              clearable: false,
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
