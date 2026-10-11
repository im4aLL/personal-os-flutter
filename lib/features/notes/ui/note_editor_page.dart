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
  bool _showTags = false;
  bool _loaded = false;
  bool _missing = false;
  bool _error = false;

  /// True while a title/content change is unsaved.
  bool _dirty = false;

  /// The autosave indicator state, held in a notifier so status changes rebuild
  /// only the small floating indicator, never the page or the text fields.
  final ValueNotifier<_SaveStatus> _status = ValueNotifier(_SaveStatus.idle);
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

  /// Monotonic id of the newest optimistic pin write. A failed write only
  /// resyncs when it is still the newest, so an older failure cannot roll back
  /// a newer pin toggle.
  int _pinGeneration = 0;

  /// Monotonic id of the newest optimistic tag write. A failed write only
  /// resyncs when it is still the newest, so an older failure cannot clobber a
  /// newer tag edit.
  int _tagGeneration = 0;

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
    // Passive teardown: the widget is being disposed from under the user (route
    // teardown, hot reload), not an explicit back gesture. Skip the flush once
    // autosave has given up, since retries are exhausted and a failed state
    // must not spawn a further attempt here. A normal dirty edit still flushes.
    // Explicit back navigation is handled by PopScope's _flush below, which
    // intentionally keeps its last-chance attempt after "Not saved".
    if (_dirty && _status.value != _SaveStatus.failed) unawaited(_persist());
    _titleController.dispose();
    _contentController.dispose();
    _status.dispose();
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
    // Only "Saving..." and "Not saved" are visible (success stays silent), so
    // only clear those. Going saved/idle -> idle looks identical and must not
    // rebuild mid-typing. Only the indicator listens to the notifier, so this
    // never rebuilds the text fields or the rest of the page.
    if (_status.value == _SaveStatus.saving ||
        _status.value == _SaveStatus.failed) {
      _status.value = _SaveStatus.idle;
    }
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, () => unawaited(_persist()));
  }

  /// Cancels the debounce and persists any pending edit.
  ///
  /// Called from PopScope's `didPop`, i.e. an explicit user back-navigation.
  /// Unlike the passive dispose path, this intentionally makes one last-chance
  /// attempt even after autosave has reported "Not saved": the user asked to
  /// leave, so a retry is warranted. This asymmetry with [dispose] is intended.
  Future<void> _flush() async {
    _debounce?.cancel();
    _debounce = null;
    if (_dirty) await _persist();
  }

  /// Queues a write of title/content, serialized behind any in-flight write.
  ///
  /// The pin flag is deliberately absent: it is owned solely by [setPinned], so
  /// a queued autosave can never re-assert a pin that a failed [setPinned] has
  /// already rolled back.
  Future<void> _persist() {
    if (_baseNote == null) return Future<void>.value();

    // Cleared before queueing so a second flush (e.g. dispose right after a
    // PopScope flush) cannot write the same edit twice.
    _dirty = false;
    final generation = ++_writeGeneration;
    final title = _titleController.text.trim();
    final content = _contentController.text;

    if (mounted && !_disposed) _status.value = _SaveStatus.saving;

    return _enqueue(
      () => _write(title.isEmpty ? null : title, content, generation),
    );
  }

  /// Runs [action] as the next step of the single-flight write queue and returns
  /// its result to the caller.
  ///
  /// Title/content, pin, and tag writes, plus the failure resync reads, all go
  /// through here, so they land in submission order once the repository is
  /// genuinely asynchronous. The queue tail is advanced on a future that
  /// swallows [action]'s error, so one failed write never poisons later writers;
  /// callers still see the original error.
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _writeChain.then((_) => action());
    _writeChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Performs one queued content write; [generation] identifies it against
  /// newer writes.
  Future<void> _write(String? title, String content, int generation) async {
    try {
      await _repository.updateContent(
        widget.noteId,
        title: title,
        content: content,
      );
      // A successful write proves the repository is healthy again.
      _saveFailures = 0;
      // Only the newest write may claim durability, and never while newer input
      // is still pending: an older completion must not flip the indicator to
      // "Saved" over text the debounce has not persisted yet.
      if (generation == _writeGeneration && !_dirty && mounted && !_disposed) {
        _status.value = _SaveStatus.saved;
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
        _status.value = _SaveStatus.failed;
        return;
      }
      _status.value = _SaveStatus.idle;
      // Retry a transient failure without waiting for another keystroke.
      _debounce?.cancel();
      _debounce = Timer(_autosaveDelay, () => unawaited(_persist()));
    }
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    final generation = ++_pinGeneration;
    setState(() => _pinned = next);
    try {
      await _enqueue(() => _repository.setPinned(widget.noteId, next));
    } catch (_) {
      // Only the newest pin write may converge the UI; a stale failure must not
      // overwrite a newer optimistic toggle.
      if (!mounted || generation != _pinGeneration) return;
      await _resyncPin(generation, fallback: !next);
      if (mounted && generation == _pinGeneration) {
        showFToast(
          context: context,
          title: const Text('Could not update note'),
        );
      }
    }
  }

  Future<void> _setTags(List<String> tags) async {
    final previous = _tags;
    final generation = ++_tagGeneration;
    setState(() => _tags = tags);
    try {
      // Tag-only edits must not advance updated_at; the repository enforces it.
      await _enqueue(() => _repository.setTags(widget.noteId, tags));
    } catch (_) {
      // Only the newest tag write may converge the UI; an older failure must
      // not clobber a newer tag edit that is already queued.
      if (!mounted || generation != _tagGeneration) return;
      await _resyncTags(generation, fallback: previous);
      if (mounted && generation == _tagGeneration) {
        showFToast(
          context: context,
          title: const Text('Could not update tags'),
        );
      }
    }
  }

  /// Re-reads the note after a failed pin write and applies the stored pin,
  /// so a failed optimistic toggle converges on the store.
  ///
  /// The re-read is queued behind any in-flight write, so it observes the store
  /// after earlier writes have settled. Falls back to [fallback] when the
  /// re-read itself fails, and is a no-op once a newer pin write has started.
  Future<void> _resyncPin(int generation, {required bool fallback}) async {
    bool value = fallback;
    try {
      final loaded = await _enqueue(() => _repository.getById(widget.noteId));
      if (loaded != null) value = loaded.pinned;
    } catch (_) {
      // Keep the fallback when the re-read also fails.
    }
    if (!mounted || generation != _pinGeneration) return;
    setState(() => _pinned = value);
  }

  /// Re-reads the note after a failed tag write and applies the stored tags,
  /// so a failed optimistic edit converges on the store.
  ///
  /// The re-read is queued behind any in-flight write, so it observes the store
  /// after earlier writes have settled. Falls back to [fallback] when the
  /// re-read itself fails, and is a no-op once a newer tag write has started.
  Future<void> _resyncTags(
    int generation, {
    required List<String> fallback,
  }) async {
    var value = fallback;
    try {
      final loaded = await _enqueue(() => _repository.getById(widget.noteId));
      if (loaded != null) value = List<String>.of(loaded.tags);
    } catch (_) {
      // Keep the fallback when the re-read also fails.
    }
    if (!mounted || generation != _tagGeneration) return;
    setState(() => _tags = value);
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
            if (!_preview)
              FItem(
                prefix: const Icon(Icons.label_outline),
                title: Text(_showTags ? 'Hide tags' : 'Tags'),
                onPress: () {
                  controller.hide();
                  setState(() => _showTags = !_showTags);
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

    return Stack(
      children: [
        Column(
          // Stretch so the preview's vertical scroll view fills the width. It
          // shrink-wraps to its content otherwise, and MarkdownBody shrink-wraps a
          // multi-block note to its widest block, which would center short notes.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_preview)
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
                    const SizedBox(height: 12),
                    if (_showTags) ...[
                      TagEditor(tags: _tags, onChanged: _setTags),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            Expanded(child: _preview ? _buildPreview() : _buildEditor()),
          ],
        ),
        // Floating status: overlaid so it never takes layout space. No gap
        // when hidden, no shift when shown; success stays silent. A
        // ValueListenableBuilder rebuilds only this small badge when the save
        // status changes, so typing and saving never rebuild the text fields.
        Positioned(
          right: 16,
          bottom: 16,
          child: IgnorePointer(
            child: ValueListenableBuilder<_SaveStatus>(
              valueListenable: _status,
              builder: (context, status, _) => _SaveIndicator(status: status),
            ),
          ),
        ),
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

  /// Read-only preview: title, tags (when present), and rendered content.
  Widget _buildPreview() {
    final title = _titleController.text.trim();
    final colors = context.theme.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Untitled' : title,
            style: context.theme.typography.display.md.copyWith(
              color: title.isEmpty ? colors.mutedForeground : colors.foreground,
              fontStyle: title.isEmpty ? FontStyle.italic : null,
            ),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tags)
                  FBadge(variant: .outline, child: Text(tag)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          MarkdownPreview(content: _contentController.text),
        ],
      ),
    );
  }
}

/// A silent autosave badge: only "Saving..." or "Not saved" ever render, as a
/// floating [FBadge] overlaid by the caller so it takes no layout space.
/// Idle/saved stay silent.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.status});

  final _SaveStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _SaveStatus.saving => FBadge(child: const Text('Saving...')),
      _SaveStatus.failed => FBadge(
        variant: .destructive,
        child: const Text('Not saved'),
      ),
      _SaveStatus.idle || _SaveStatus.saved => const SizedBox.shrink(),
    };
  }
}
