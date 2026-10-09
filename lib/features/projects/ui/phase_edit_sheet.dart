import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/project.dart';
import 'project_gantt.dart';

/// Preset phase color swatches (hex), matching the seeded phases.
const List<String> phaseColorOptions = [
  '#93C5FD',
  '#86EFAC',
  '#FCA5A5',
  '#FCD34D',
  '#C4B5FD',
  '#FDA4AF',
  '#6EE7B7',
  '#7DD3FC',
];

/// Opens the add/edit phase sheet.
///
/// When [phase] is null a new phase is created for [projectId]; otherwise
/// [phase] is updated. Returns `true` when a save happened so the caller can
/// confirm with a toast.
Future<bool> showPhaseEditSheet({
  required BuildContext context,
  required String projectId,
  ProjectPhase? phase,
}) async {
  final saved = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    // The form is taller than the default 9/16 sheet budget on small phones,
    // so the sheet sizes to its scrollable content instead.
    mainAxisMaxRatio: null,
    builder: (_) => _PhaseEditSheet(projectId: projectId, phase: phase),
  );
  return saved ?? false;
}

/// Add/edit phase form hosted in a bottom sheet.
class _PhaseEditSheet extends ConsumerStatefulWidget {
  const _PhaseEditSheet({required this.projectId, required this.phase});

  /// The owning project id.
  final String projectId;

  /// The phase being edited, or null when creating.
  final ProjectPhase? phase;

  @override
  ConsumerState<_PhaseEditSheet> createState() => _PhaseEditSheetState();
}

class _PhaseEditSheetState extends ConsumerState<_PhaseEditSheet> {
  late final TextEditingController _nameController;
  late String _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final phase = widget.phase;
    _nameController = TextEditingController(text: phase?.name ?? '');
    // A phase created elsewhere (e.g. the desktop free color input) may carry
    // a non-preset color: keep it as-is so a name-only edit never rewrites it.
    _color = phase?.color ?? phaseColorOptions[0];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Whether the form can be saved right now (the name is required).
  bool get _canSave => !_saving && _nameController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final repository = ref.read(projectRepositoryProvider);
      final existing = widget.phase;
      if (existing == null) {
        await repository.createPhase(
          widget.projectId,
          name: name,
          color: _color,
        );
      } else {
        await repository.updatePhase(
          existing.copyWith(name: name, color: _color),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(context: context, title: const Text('Could not save phase'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.phase;
    final fallback = context.theme.colors.mutedForeground;
    // The current color leads so a non-preset value kept from another client
    // still renders as the selected swatch instead of silently resetting.
    final swatches = [
      if (!phaseColorOptions.contains(_color)) _color,
      ...phaseColorOptions,
    ];
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
                    existing == null ? 'New phase' : 'Edit phase',
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
              hint: 'Phase name',
              autofocus: existing == null,
              textInputAction: .next,
            ),
            const SizedBox(height: 12),
            Text(
              'Color',
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final hex in swatches)
                  FTappable(
                    onPress: () => setState(() => _color = hex),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: phaseColor(hex, fallback),
                        borderRadius: BorderRadius.circular(10),
                        border: _color == hex
                            ? Border.all(
                                color: context.theme.colors.foreground,
                                width: 2,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
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
