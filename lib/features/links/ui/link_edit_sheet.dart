import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/page_title_fetcher.dart';
import '../../../core/data/repository_providers.dart';
import '../../../core/models/link.dart';
import '../../../core/widgets/tag_editor.dart';

/// Opens the add/edit link sheet.
///
/// When [link] is null a new link is created; otherwise [link] is updated.
/// Returns `true` when a save happened so the caller can confirm with a toast.
Future<bool> showLinkEditSheet({
  required BuildContext context,
  LinkWithTags? link,
}) async {
  final saved = await showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    // The form is taller than the default 9/16 sheet budget on small phones,
    // so the sheet sizes to its scrollable content instead.
    mainAxisMaxRatio: null,
    builder: (_) => _LinkEditSheet(link: link),
  );
  return saved ?? false;
}

/// Add/edit link form hosted in a bottom sheet.
class _LinkEditSheet extends ConsumerStatefulWidget {
  const _LinkEditSheet({required this.link});

  /// The link being edited, or null when creating.
  final LinkWithTags? link;

  @override
  ConsumerState<_LinkEditSheet> createState() => _LinkEditSheetState();
}

class _LinkEditSheetState extends ConsumerState<_LinkEditSheet> {
  /// How long to wait after the last URL keystroke before fetching the title.
  static const Duration _titleFetchDebounce = Duration(milliseconds: 450);

  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  late List<String> _tags;
  bool _saving = false;

  /// Watches the URL field so leaving it can trigger a title fetch.
  ///
  /// Only attached in the add flow; an edit keeps the stored title untouched.
  final FocusNode _urlFocus = FocusNode();

  /// The last URL text seen.
  ///
  /// Forui's managed control notifies on every controller change, including
  /// caret and selection moves, so this lets [_onUrlChanged] ignore non-edits.
  late String _lastUrl;

  /// Pending debounce for a URL-change-triggered fetch.
  Timer? _fetchDebounce;

  /// The URL [_cachedTitleFetch] belongs to, or null before the first fetch.
  String? _cachedTitleUrl;

  /// The in-flight or completed title fetch for [_cachedTitleUrl].
  ///
  /// Reusing the future means the several triggers for one URL (URL change,
  /// focus loss, submit, save) issue a single HTTP request.
  Future<String?>? _cachedTitleFetch;

  /// The title most recently written by [_fetchAndApplyTitle], or null.
  ///
  /// Lets an auto-filled title be told apart from one the user authored:
  /// clearing an auto-fill must stick, while the same value stays refreshable.
  String? _autoFilledTitle;

  /// Whether the current URL has auto-filled the title this session.
  ///
  /// Set when [_fetchAndApplyTitle] fills the field and reset only when the URL
  /// changes, so it stays true after the user replaces the filled text (which
  /// drops [_autoFilledTitle] on the first edit). This lets an emptied field
  /// still be recorded as a user clear.
  bool _titleWasAutoFilled = false;

  /// URLs whose auto-filled title the user explicitly cleared.
  ///
  /// Prevents a reverted URL from silently re-applying a title the user already
  /// removed.
  final Set<String> _clearedTitleUrls = {};

  /// Number of title fetches currently awaited, driving the Title hint.
  int _activeTitleFetches = 0;

  /// Whether a page-title fetch is in flight.
  bool get _fetchingTitle => _activeTitleFetches > 0;

  /// The trimmed title field text.
  String get _titleText => _titleController.text.trim();

  /// Whether the title was authored by the user (non-empty and not our fill).
  bool get _hasUserTitle =>
      _titleText.isNotEmpty && _titleText != _autoFilledTitle;

  @override
  void initState() {
    super.initState();
    final link = widget.link;
    _urlController = TextEditingController(text: link?.url ?? '');
    _titleController = TextEditingController(text: link?.title ?? '');
    _lastUrl = _urlController.text.trim();
    _tags = List<String>.of(link?.tags ?? const []);
    if (link == null) _urlFocus.addListener(_onUrlFocusChange);
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _urlFocus.removeListener(_onUrlFocusChange);
    _urlFocus.dispose();
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// Handles a URL edit: drops the previous URL's auto-fill, then debounces a
  /// title fetch.
  ///
  /// Fetching needs no focus transition, so pasting a URL and tapping Save
  /// still resolves a title (the save path awaits the same fetch).
  void _onUrlChanged() {
    if (widget.link != null) return;
    final url = _urlController.text.trim();
    // Forui's managed control notifies on caret/selection changes too; ignore
    // anything that leaves the URL text unchanged (and keep the pending
    // debounce alive in that case).
    if (url == _lastUrl) return;
    _lastUrl = url;

    _fetchDebounce?.cancel();
    // An auto-filled title belongs to the previous URL: clear it while it is
    // still the whole title so it cannot mismatch the new URL, and drop the
    // marker and flag either way. A title the user typed is never touched. The
    // marker and flag are cleared before the controller so the title field's
    // onChange does not record this programmatic clear as a user clear.
    final autoFilled = _autoFilledTitle;
    _autoFilledTitle = null;
    _titleWasAutoFilled = false;
    if (autoFilled != null && _titleText == autoFilled) {
      setState(() => _titleController.clear());
    }

    _fetchDebounce = Timer(_titleFetchDebounce, _requestTitleFetch);
  }

  /// Records user edits to the title field.
  ///
  /// A cleared auto-fill is remembered per URL so it is not silently re-applied
  /// when the user returns to that URL; a typed title drops the auto-fill
  /// marker so it is treated as user-authored.
  void _onTitleChanged() {
    final title = _titleText;
    // Record a user clear whenever the field is emptied after an auto-fill,
    // including deleting it down character by character (which already dropped
    // [_autoFilledTitle]).
    if (title.isEmpty && _titleWasAutoFilled) {
      final url = _urlController.text.trim();
      if (url.isNotEmpty) _clearedTitleUrls.add(url);
      return;
    }
    if (title.isNotEmpty && title != _autoFilledTitle) {
      _autoFilledTitle = null;
    }
  }

  /// Requests a fetch when the URL field loses focus, skipping the debounce.
  void _onUrlFocusChange() {
    if (_urlFocus.hasFocus) return;
    _requestTitleFetch();
  }

  /// Starts a title fetch when the URL is valid and the title is not the user's.
  void _requestTitleFetch() {
    _fetchDebounce?.cancel();
    if (widget.link != null) return;
    final url = _urlController.text.trim();
    if (!isHttpUrl(url) || _hasUserTitle) return;
    // A cleared auto-fill must stick, so do not refetch for the same URL. A URL
    // change already nulls the marker, so a new URL still fetches.
    if (_clearedTitleUrls.contains(url)) return;
    if (_autoFilledTitle != null && _titleText.isEmpty) return;
    unawaited(_fetchAndApplyTitle(url));
  }

  /// The title fetch for [url], reused while one is already in flight.
  ///
  /// A failed (null) result is dropped from the cache so a later trigger can
  /// retry the same URL; a successful result stays cached.
  Future<String?> _titleFetchFor(String url) {
    final cached = _cachedTitleFetch;
    if (_cachedTitleUrl == url && cached != null) return cached;
    final fetch = ref.read(pageTitleFetcherProvider).fetchTitle(url);
    _cachedTitleUrl = url;
    _cachedTitleFetch = fetch;
    unawaited(
      fetch.then<void>((title) {
        // Clear only while this is still the cached future, so a newer request
        // is never clobbered.
        if (title == null && identical(_cachedTitleFetch, fetch)) {
          _cachedTitleFetch = null;
          _cachedTitleUrl = null;
        }
      }, onError: (_) {}),
    );
    return fetch;
  }

  /// Fetches [url]'s title and applies it while the field is still fillable.
  ///
  /// Silent by design: a failure leaves manual entry (and the domain fallback
  /// applied on save) untouched. A result is only applied when the URL still
  /// matches and the field has no user-authored title, so text the user typed
  /// is never overwritten.
  Future<void> _fetchAndApplyTitle(String url) async {
    setState(() => _activeTitleFetches++);
    try {
      final title = (await _titleFetchFor(url))?.trim();
      if (!mounted || title == null || title.isEmpty) return;
      if (_urlController.text.trim() != url) return;
      if (_hasUserTitle) return;
      // A cleared auto-fill must stick; a URL change nulls the marker first, so
      // a fresh URL still fills.
      if (_clearedTitleUrls.contains(url)) return;
      if (_autoFilledTitle != null && _titleText.isEmpty) return;
      setState(() {
        // Set the marker and flag before the text so the field's onChange does
        // not record this programmatic fill as a user edit.
        _autoFilledTitle = title;
        _titleWasAutoFilled = true;
        _titleController.text = title;
      });
    } finally {
      if (mounted) setState(() => _activeTitleFetches--);
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final url = _urlController.text.trim();
    if (!isHttpUrl(url)) {
      showFToast(context: context, title: const Text('Enter a valid URL'));
      return;
    }

    // Barrier taps and drag-downs pop the route directly (bypassing PopScope),
    // and `mounted` stays true through the exit animation, so a plain mounted
    // check can still write and then pop the page underneath. Requiring this
    // route to still be current closes that window.
    final route = ModalRoute.of(context);
    bool isCurrent() => mounted && (route?.isCurrent ?? true);

    final domain = linkDomain(url);
    final faviconUrl =
        'https://www.google.com/s2/favicons?domain=$domain&sz=32';
    final repository = ref.read(linkRepositoryProvider);
    final existing = widget.link;
    // Snapshot the tags so the persisted set cannot change mid-save.
    final tags = List<String>.of(_tags);

    // Hide the keyboard before the form freezes, so an IME submit cannot race
    // the save.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      if (existing == null) {
        // Duplicate check first so it reports immediately, before any title
        // fetch can add latency.
        if (await repository.urlExists(url)) {
          if (mounted && isCurrent()) {
            showFToast(
              context: context,
              title: const Text('This link is already saved'),
            );
          }
          return;
        }
        if (!isCurrent()) return;
        // Resolve the title before writing: when adding with an empty title
        // this awaits the (possibly just-started) fetch, so a reachable page
        // title is saved instead of the domain fallback.
        final title = await _titleForSave(url, domain);
        if (!isCurrent()) return;
        await repository.create(
          url: url,
          title: title,
          faviconUrl: faviconUrl,
          tags: tags,
        );
      } else {
        if (url != existing.link.url && await repository.urlExists(url)) {
          if (mounted && isCurrent()) {
            showFToast(
              context: context,
              title: const Text('This link is already saved'),
            );
          }
          return;
        }
        if (!isCurrent()) return;
        final title = await _titleForSave(url, domain);
        if (!isCurrent()) return;
        await repository.update(
          existing.link.copyWith(
            url: url,
            title: title,
            faviconUrl: faviconUrl,
          ),
        );
        // The write has started; let the tag replacement complete with it so
        // the pair is never split.
        await repository.setTags(existing.id, tags);
      }
      if (mounted && isCurrent()) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && isCurrent()) {
        showFToast(context: context, title: const Text('Could not save link'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The title to persist: the user's text, the fetched page title, or [domain].
  ///
  /// Only the add flow fetches; an edit uses its typed/stored title. A title the
  /// user authored is always used. An empty field with no prior auto-fill waits
  /// for the fetch (bounded by the fetcher's own timeout) and falls back to
  /// [domain]. An auto-fill the user cleared also falls back to [domain], so
  /// clearing it sticks instead of re-applying the cached fetch.
  Future<String> _titleForSave(String url, String domain) async {
    if (widget.link != null) {
      return _titleText.isEmpty ? domain : _titleText;
    }
    if (_hasUserTitle) return _titleText;
    if (_clearedTitleUrls.contains(url)) return domain;
    if (_autoFilledTitle != null && _titleText.isEmpty) return domain;

    setState(() => _activeTitleFetches++);
    try {
      final fetched = (await _titleFetchFor(url))?.trim();
      if (!mounted) return domain;
      if (_hasUserTitle) return _titleText;
      return (fetched == null || fetched.isEmpty) ? domain : fetched;
    } finally {
      if (mounted) setState(() => _activeTitleFetches--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.link;
    // showFSheet does not paint any background behind the builder content,
    // so the sheet paints the theme surface itself (with the usual top
    // rounded corners) to stay opaque in light and dark themes.
    //
    // PopScope blocks only the system back gesture while a save is in flight;
    // a barrier tap or drag-down can still dismiss the sheet. The route-is-
    // current guards in _save prevent a write during the title-fetch window and
    // prevent popping the wrong route on the way out.
    final content = DecoratedBox(
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
                    existing == null ? 'New link' : 'Edit link',
                    style: context.theme.typography.body.lg.copyWith(
                      color: context.theme.colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FButton.icon(
                  variant: .ghost,
                  onPress: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _urlController,
                onChange: (_) => _onUrlChanged(),
              ),
              label: const Text('URL'),
              hint: 'https://example.com',
              autofocus: existing == null,
              focusNode: _urlFocus,
              enabled: !_saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: .next,
              onSubmit: (_) => _requestTitleFetch(),
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(
                controller: _titleController,
                onChange: (_) => _onTitleChanged(),
              ),
              label: const Text('Title'),
              // The hint doubles as the fetch affordance; the field stays
              // editable throughout.
              hint: _fetchingTitle
                  ? 'Fetching title...'
                  : 'Defaults to the domain',
              enabled: !_saving,
              textInputAction: .done,
            ),
            const SizedBox(height: 12),
            TagEditor(
              tags: _tags,
              enabled: !_saving,
              onChanged: (tags) => setState(() => _tags = tags),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    variant: .outline,
                    onPress: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FButton(
                    onPress: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return PopScope(canPop: !_saving, child: content);
  }
}
