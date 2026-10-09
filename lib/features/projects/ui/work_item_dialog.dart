import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/project.dart';
import '../../../core/widgets/delete_confirm_dialog.dart';

/// The "no phase" sentinel for the phase select: phase ids are UUIDs, so the
/// empty string never collides with a real phase.
const String noPhaseId = '';

/// Opens the add/edit work item sheet.
///
/// When [item] is null a new work item is created for [projectId]; otherwise
/// [item] is updated. [weekCount] bounds the start/end week selects. Returns
/// `true` when a save (or delete) happened so the caller can confirm with a
/// toast.
Future<bool> showWorkItemEditSheet({
  required BuildContext context,
  required String projectId,
  required List<ProjectPhase> phases,
  required int weekCount,
  WorkItemWithPhase? item,
}) async {
  final saved = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    // `mainAxisMaxRatio: null` lets the sheet pick up its content height (and
    // stay draggable); the form itself caps that height and scrolls, so it
    // cannot grow past the top of the screen.
    mainAxisMaxRatio: null,
    builder: (_) => _WorkItemEditSheet(
      projectId: projectId,
      phases: phases,
      weekCount: weekCount,
      item: item,
    ),
  );
  return saved ?? false;
}

/// Add/edit work item form hosted in a bottom sheet.
class _WorkItemEditSheet extends ConsumerStatefulWidget {
  const _WorkItemEditSheet({
    required this.projectId,
    required this.phases,
    required this.weekCount,
    required this.item,
  });

  /// The owning project id.
  final String projectId;

  /// The project phases for the phase select, in display order.
  final List<ProjectPhase> phases;

  /// The project week count bounding the start/end week selects.
  final int weekCount;

  /// The item being edited, or null when creating.
  final WorkItemWithPhase? item;

  @override
  ConsumerState<_WorkItemEditSheet> createState() => _WorkItemEditSheetState();
}

class _WorkItemEditSheetState extends ConsumerState<_WorkItemEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _personController;
  late final TextEditingController _jiraController;
  late final TextEditingController _commentController;
  late bool _isSeparator;
  late String _phaseId;
  late WorkItemStatus _status;
  late int _startWeek;
  late int _endWeek;
  bool _saving = false;

  int get _weeks => widget.weekCount < 1 ? 1 : widget.weekCount;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleController = TextEditingController(text: item?.title ?? '');
    _personController = TextEditingController(text: item?.person ?? '');
    _jiraController = TextEditingController(text: item?.jiraTicket ?? '');
    _commentController = TextEditingController(text: item?.comment ?? '');
    _isSeparator = item?.isSeparator ?? false;
    _phaseId = item?.phaseId ?? noPhaseId;
    if (_phaseId != noPhaseId &&
        widget.phases.every((phase) => phase.id != _phaseId)) {
      // The phase is gone (dangling after a delete); treat as unphased.
      _phaseId = noPhaseId;
    }
    _status = item?.status ?? WorkItemStatus.pending;
    _startWeek = (item?.startWeek ?? 1).clamp(1, _weeks);
    _endWeek = (item?.endWeek ?? _startWeek).clamp(1, _weeks);
    if (_startWeek > _endWeek) _endWeek = _startWeek;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _personController.dispose();
    _jiraController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  /// Whether the form can be saved right now.
  ///
  /// The title is required for a normal work item; a separator row needs no
  /// fields at all. The start <= end ordering is checked in [_save] so a
  /// violation reports a toast instead of silently disabling the button.
  bool get _canSave =>
      !_saving && (_isSeparator || _titleController.text.trim().isNotEmpty);

  /// Select items for weeks 1..[_weeks].
  Map<String, int> get _weekItems => {
    for (var week = 1; week <= _weeks; week++) 'Week $week': week,
  };

  /// Select items for phases, with a leading "No phase" entry.
  ///
  /// Labels are de-duplicated so two same-named phases stay selectable (the
  /// map keys must be unique).
  Map<String, String> get _phaseItems {
    final items = <String, String>{'No phase': noPhaseId};
    final used = <String>{'No phase'};
    for (final phase in widget.phases) {
      var label = phase.name;
      var suffix = 2;
      while (used.contains(label)) {
        label = '${phase.name} ($suffix)';
        suffix++;
      }
      used.add(label);
      items[label] = phase.id;
    }
    return items;
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    // A separator row may be created empty; a normal item needs a title.
    if (!_isSeparator && title.isEmpty) return;
    if (_startWeek > _endWeek) {
      showFToast(
        context: context,
        title: const Text('Start week must be on or before end week'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = ref.read(projectRepositoryProvider);
      final existing = widget.item;
      // Separators are section dividers: only the title (and phase clearing)
      // is kept; status and weeks are forced to the desktop defaults.
      final status = _isSeparator ? WorkItemStatus.pending : _status;
      final startWeek = _isSeparator ? 1 : _startWeek;
      final endWeek = _isSeparator ? 1 : _endWeek;
      if (existing == null) {
        await repository.createWorkItem(
          widget.projectId,
          phaseId: _isSeparator || _phaseId == noPhaseId ? null : _phaseId,
          title: title,
          person: _isSeparator ? null : _nullIfEmpty(_personController),
          comment: _isSeparator ? null : _nullIfEmpty(_commentController),
          jiraTicket: _isSeparator ? null : _nullIfEmpty(_jiraController),
          status: status,
          startWeek: startWeek,
          endWeek: endWeek,
          isSeparator: _isSeparator,
        );
      } else {
        await repository.updateWorkItem(
          existing.item.copyWith(
            phaseId: _isSeparator || _phaseId == noPhaseId ? null : _phaseId,
            title: title,
            person: _isSeparator ? null : _nullIfEmpty(_personController),
            comment: _isSeparator ? null : _nullIfEmpty(_commentController),
            jiraTicket: _isSeparator ? null : _nullIfEmpty(_jiraController),
            status: status,
            startWeek: startWeek,
            endWeek: endWeek,
            isSeparator: _isSeparator,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('Could not save work item'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.item;
    if (existing == null || _saving) return;
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete work item?',
      body: '"${existing.title}" will be permanently deleted.',
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await ref.read(projectRepositoryProvider).deleteWorkItem(existing.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete work item'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The trimmed controller text, or `null` when blank (the remote columns are
  /// nullable and the other clients use null, not empty strings).
  String? _nullIfEmpty(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.item;
    // Cap the sheet to a fraction of the space above the keyboard and let the
    // form scroll inside: the form is tall, and without a bound it would grow
    // past the top of the screen on small phones.
    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height - media.viewInsets.bottom) * 0.85;
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
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
                      existing == null ? 'New work item' : 'Edit work item',
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
              if (!_isSeparator) ...[
                FTextFormField(
                  control: FTextFieldControl.managed(
                    controller: _titleController,
                    onChange: (_) => setState(() {}),
                  ),
                  label: const Text('Title'),
                  hint: 'What is the work?',
                  autofocus: existing == null,
                  textInputAction: .next,
                ),
                const SizedBox(height: 12),
              ],
              FSwitch(
                value: _isSeparator,
                onChange: (value) => setState(() => _isSeparator = value),
                label: const Text('Separator row'),
                description: const Text(
                  'Separators are section dividers: only a divider line is shown.',
                ),
              ),
              if (!_isSeparator) ...[
                const SizedBox(height: 12),
                FSelect<String>(
                  control: FSelectControl.lifted(
                    value: _phaseId,
                    onChange: (value) {
                      if (value != null) setState(() => _phaseId = value);
                    },
                  ),
                  items: _phaseItems,
                  label: const Text('Phase'),
                  hint: 'No phase',
                  clearable: false,
                ),
                const SizedBox(height: 12),
                FSelect<WorkItemStatus>(
                  control: FSelectControl.lifted(
                    value: _status,
                    onChange: (value) {
                      if (value != null) setState(() => _status = value);
                    },
                  ),
                  items: const {
                    'Pending': WorkItemStatus.pending,
                    'In progress': WorkItemStatus.inProgress,
                    'Done': WorkItemStatus.done,
                  },
                  label: const Text('Status'),
                  hint: 'Select status',
                  clearable: false,
                ),
                const SizedBox(height: 12),
                FTextFormField(
                  control: FTextFieldControl.managed(
                    controller: _personController,
                  ),
                  label: const Text('Person'),
                  hint: 'Optional assignee',
                  textInputAction: .next,
                ),
                const SizedBox(height: 12),
                FTextFormField(
                  control: FTextFieldControl.managed(
                    controller: _jiraController,
                  ),
                  label: const Text('Jira ticket'),
                  hint: 'e.g. POS-12',
                  textInputAction: .next,
                ),
                const SizedBox(height: 12),
                FTextFormField(
                  control: FTextFieldControl.managed(
                    controller: _commentController,
                  ),
                  label: const Text('Comment'),
                  hint: 'Optional details',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FSelect<int>(
                        control: FSelectControl.lifted(
                          value: _startWeek,
                          onChange: (value) {
                            if (value != null) {
                              setState(() => _startWeek = value);
                            }
                          },
                        ),
                        items: _weekItems,
                        label: const Text('Start week'),
                        hint: 'Start',
                        clearable: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FSelect<int>(
                        control: FSelectControl.lifted(
                          value: _endWeek,
                          onChange: (value) {
                            if (value != null) {
                              setState(() => _endWeek = value);
                            }
                          },
                        ),
                        items: _weekItems,
                        label: const Text('End week'),
                        hint: 'End',
                        clearable: false,
                      ),
                    ),
                  ],
                ),
              ],
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
              if (existing != null) ...[
                const SizedBox(height: 12),
                FButton(
                  variant: .destructive,
                  onPress: _saving ? null : _delete,
                  child: const Text('Delete work item'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
