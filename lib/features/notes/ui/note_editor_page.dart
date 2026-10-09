import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/repositories.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/models/note.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/delete_confirm_dialog.dart';
import '../../../core/widgets/tag_editor.dart';
import 'markdown_preview.dart';

/// Full-screen editor for the note with id [noteId].
///
/// Seeds its local state from the repository exactly once, then treats that
/// local state as the source of truth so store re-emits can never clobber
/// typing. Title and content save after a short debounce; tags, pin, and delete
/// write immediately. Any pending title/content edit is flushed on the way out,
/// so leaving and reopening keeps the edit.
class NoteEditorPage extends ConsumerStatefulWidget {
  /// Creates a [NoteEditorPage] for [noteId].
  const NoteEditorPage({required this.noteId, super.key});

  /// The id of the note to edit.
  final String noteId;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

/// How long to wait after the last keystroke before persisting title/content.
const _autosaveDelay = Duration(milliseconds: 500);

/// How many times one edit burst's title/content write may be attempted before
/// autosave gives up and shows a persistent "Not saved" state.
const _maxSaveAttempts = 3;

/// The autosave indicator state.
enum _SaveStatus { idle, saving, saved, failed }

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  /// Captured once so pending writes can still land after disposal.
  late final NoteRepository _repository;

  /// The row this editor is based on; its id/createdAt anchor every write.
  Note? _baseNote;

  List<String> _tags = const [];
  bool _pinned = false;
  bool _preview = false;
  bool _loaded = false;
  bool _missing = false;
  bool _error = false;

  /// True while a title/content change is unsaved.
  bool _dirty = false;
  _SaveStatus _status = _SaveStatus.idle;
  Timer? _debounce;

  /// Monotonic id of the newest queued write. Only the newest write may mark
  /// the editor saved or reschedule after a failure, so a stale completion
  /// cannot flip the indicator back to "Saved" over newer, unsaved input.
  int _writeGeneration = 0;

  /// Consecutive failed attempts in the current edit burst. Reset by a new edit
  /// or a successful write, and bounds the autosave retry so a persistent
  /// failure cannot loop forever.
  int _saveFailures = 0;

  /// Tail of the single-flight write queue. Each write starts only after the
  /// previous one settles, so an older write can never land after a newer one
  /// once the repository is genuinely asynchronous (the Phase 9 drift swap).
  Future<void> _writeChain = Future<void>.value();

  /// Set in [dispose] so the teardown flush never touches widget state.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(noteRepositoryProvider);
    unawaited(_seed());
  }

  @override
  void dispose() {
    // Flush any edit the debounce has not fired yet; the repository outlives
    // this widget, so the write still lands. State updates are suppressed from
    // here on (the widget is going away).
    _disposed = true;
    _debounce?.cancel();
    // Skip the flush once autosave has given up: retries are exhausted, and
    // although the repository outlives this widget, a failed state must not
    // spawn a further attempt. A normal dirty edit still flushes here.
    if (_dirty && _status != _SaveStatus.failed) unawaited(_persist());
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _seed() async {
    try {
      final loaded = await _repository.getById(widget.noteId);
      if (!mounted) return;
      if (loaded == null) {
        setState(() => _missing = true);
        return;
      }
      _baseNote = loaded.note;
      _titleController.text = loaded.title ?? '';
      _contentController.text = loaded.content;
      _tags = List<String>.of(loaded.tags);
      _pinned = loaded.pinned;
      setState(() => _loaded = true);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  /// Marks the note dirty and (re)starts the autosave debounce.
  void _onEdit() {
    if (!_loaded) return;
    _dirty = true;
    // New input starts a fresh burst, so any previous failure budget resets.
    _saveFailures = 0;
    // Clear a stale "Saved" as soon as new input arrives, so the indicator
    // never claims the current text is persisted while the debounce is ticking.
    if (_status != _SaveStatus.idle) {
      setState(() => _status = _SaveStatus.idle);
    }
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, () => unawaited(_persist()));
  }

  /// Cancels the debounce and persists any pending edit.
  Future<void> _flush() async {
    _debounce?.cancel();
    _debounce = null;
    if (_dirty) await _persist();
  }

  /// Queues a write of title/content/pin, serialized behind any in-flight write.
  Future<void> _persist() {
    final base = _baseNote;
    if (base == null) return Future<void>.value();

    // Cleared before queueing so a second flush (e.g. dispose right after a
    // PopScope flush) cannot write the same edit twice.
    _dirty = false;
    final generation = ++_writeGeneration;
    final title = _titleController.text.trim();
    final note = base.copyWith(
      title: title.isEmpty ? null : title,
      content: _contentController.text,
      pinned: _pinned,
    );

    if (mounted && !_disposed) setState(() => _status = _SaveStatus.saving);

    return _enqueue(() => _write(note, generation));
  }

  /// Runs [action] as the next step of the single-flight write queue and returns
  /// its result to the caller.
  ///
  /// Title/content, pin, and tag writes all go through here, so they land in
  /// submission order once the repository is genuinely asynchronous. The queue
  /// tail is advanced on a future that swallows [action]'s error, so one failed
  /// write never poisons later writers; callers still see the original error.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _writeChain.then((_) => action());
    _writeChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Performs one queued write; [generation] identifies it against newer writes.
  Future<void> _write(Note note, int generation) async {
    try {
      await _repository.update(note);
      // A successful write proves the repository is healthy again.
      _saveFailures = 0;
      // Only the newest write may claim durability, and never while newer input
      // is still pending: an older completion must not flip the indicator to
      // "Saved" over text the debounce has not persisted yet.
      if (generation == _writeGeneration && !_dirty && mounted && !_disposed) {
        setState(() => _status = _SaveStatus.saved);
      }
    } catch (_) {
      // A stale failure is superseded by a newer write; only the current one
      // re-dirties and decides whether to retry or give up.
      if (generation != _writeGeneration) return;
      if (!mounted || _disposed) return;

      _dirty = true;
      final attempt = ++_saveFailures;
      // Toast once per burst; a repeated failure stays quiet.
      if (attempt == 1) {
        showFToast(context: context, title: const Text('Could not save note'));
      }
      if (attempt >= _maxSaveAttempts) {
        // Retries exhausted: stop rescheduling and show a persistent unsaved
        // state instead of looping and toasting forever.
        setState(() => _status = _SaveStatus.failed);
        return;
      }
      setState(() => _status = _SaveStatus.idle);
      // Retry a transient failure without waiting for another keystroke.
      _debounce?.cancel();
      _debounce = Timer(_autosaveDelay, () => unawaited(_persist()));
    }
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    setState(() => _pinned = next);
    try {
      await _enqueue(() => _repository.setPinned(widget.noteId, next));
    } catch (_) {
      if (mounted) {
        setState(() => _pinned = !next);
        showFToast(
          context: context,
          title: const Text('Could not update note'),
        );
      }
    }
  }

  Future<void> _setTags(List<String> tags) async {
    final previous = _tags;
    setState(() => _tags = tags);
    try {
      // Tag-only edits must not advance updated_at; the repository enforces it.
      await _enqueue(() => _repository.setTags(widget.noteId, tags));
    } catch (_) {
      if (mounted) {
        setState(() => _tags = previous);
        showFToast(
          context: context,
          title: const Text('Could not update tags'),
        );
      }
    }
  }

  Future<void> _delete() async {
    final base = _baseNote;
    if (base == null) return;

    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete note?',
      body: '"${noteDisplayTitle(base)}" will be permanently deleted.',
    );
    if (!confirmed || !mounted) return;

    // Drop pending edits first so the delete is not undone by a flush on the
    // way out.
    _debounce?.cancel();
    _dirty = false;
    try {
      await _repository.delete(widget.noteId);
      if (!mounted) return;
      showFToast(context: context, title: const Text('Note deleted'));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete note'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_flush());
      },
      child: FScaffold(
        header: FHeader.nested(
          prefixes: [
            FHeaderAction(
              icon: const Icon(Icons.arrow_back),
              semanticsLabel: 'Back to notes',
              onPress: () => Navigator.maybePop(context),
            ),
          ],
          title: const Text('Note'),
          suffixes: _loaded ? [_actionsMenu()] : const [],
        ),
        child: _body(),
      ),
    );
  }

  /// The header overflow menu: preview/edit, pin, and delete.
  ///
  /// Each item hides the menu on press, since tapping inside a popover menu
  /// does not dismiss it.
  Widget _actionsMenu() {
    return FPopoverMenu(
      builder: (context, controller, _) => FHeaderAction(
        icon: const Icon(Icons.more_vert),
        semanticsLabel: 'Note actions',
        onPress: controller.toggle,
      ),
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          divider: .full,
          children: [
            FItem(
              prefix: Icon(
                _preview ? Icons.edit_outlined : Icons.visibility_outlined,
              ),
              title: Text(_preview ? 'Edit' : 'Preview'),
              onPress: () {
                controller.hide();
                setState(() => _preview = !_preview);
              },
            ),
            FItem(
              prefix: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(_pinned ? 'Unpin' : 'Pin'),
              onPress: () {
                controller.hide();
                _togglePin();
              },
            ),
            FItem(
              variant: .destructive,
              prefix: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onPress: () {
                controller.hide();
                _delete();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _body() {
    if (_missing) return const CenteredMessage('This note no longer exists.');
    if (_error) return const CenteredMessage('Could not load this note.');
    if (!_loaded) return const Center(child: FCircularProgress());

    return Column(
      // Stretch so the preview's vertical scroll view fills the width. It
      // shrink-wraps to its content otherwise, and MarkdownBody shrink-wraps a
      // multi-block note to its widest block, which would center short notes.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FTextField(
                control: FTextFieldControl.managed(
                  controller: _titleController,
                  onChange: (_) => _onEdit(),
                ),
                hint: 'Title',
                textInputAction: .next,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: _SaveIndicator(status: _status),
              ),
              const SizedBox(height: 8),
              TagEditor(tags: _tags, onChanged: _setTags),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Expanded(child: _preview ? _buildPreview() : _buildEditor()),
      ],
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FTextField(
        control: FTextFieldControl.managed(
          controller: _contentController,
          onChange: (_) => _onEdit(),
        ),
        hint: 'Write in markdown...',
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        // Monospace body so markdown structure (indentation, tables) reads in
        // the editor. The generated text-field style delta needs the field's
        // content TextStyle supplied as a variants operation. Sized down from
        // the field's default body.sm so the note body reads lighter.
        style: .delta(
          contentTextStyle: .delta([
            .all(
              .delta(
                fontFamily: 'monospace',
                fontSize: context.theme.typography.body.xs.fontSize,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: MarkdownPreview(content: _contentController.text),
    );
  }
}

/// A small autosave indicator: hidden when idle, otherwise "Saving...",
/// "Saved", or a muted "Not saved" once retries are exhausted.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.status});

  final _SaveStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      _SaveStatus.idle => null,
      _SaveStatus.saving => 'Saving...',
      _SaveStatus.saved => 'Saved',
      _SaveStatus.failed => 'Not saved',
    };
    if (label == null) return const SizedBox.shrink();

    return Text(
      label,
      style: context.theme.typography.body.xs.copyWith(
        color: context.theme.colors.mutedForeground,
      ),
    );
  }
}
