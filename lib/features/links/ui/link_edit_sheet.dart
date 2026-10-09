import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

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
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  late List<String> _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final link = widget.link;
    _urlController = TextEditingController(text: link?.url ?? '');
    _titleController = TextEditingController(text: link?.title ?? '');
    _tags = List<String>.of(link?.tags ?? const []);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final url = _urlController.text.trim();
    if (!isHttpUrl(url)) {
      showFToast(context: context, title: const Text('Enter a valid URL'));
      return;
    }

    final domain = linkDomain(url);
    final typedTitle = _titleController.text.trim();
    final title = typedTitle.isEmpty ? domain : typedTitle;
    final faviconUrl =
        'https://www.google.com/s2/favicons?domain=$domain&sz=32';
    final repository = ref.read(linkRepositoryProvider);
    final existing = widget.link;

    setState(() => _saving = true);
    try {
      if (existing == null) {
        if (await repository.urlExists(url)) {
          if (mounted) {
            showFToast(
              context: context,
              title: const Text('This link is already saved'),
            );
          }
          return;
        }
        await repository.create(
          url: url,
          title: title,
          faviconUrl: faviconUrl,
          tags: _tags,
        );
      } else {
        if (url != existing.link.url && await repository.urlExists(url)) {
          if (mounted) {
            showFToast(
              context: context,
              title: const Text('This link is already saved'),
            );
          }
          return;
        }
        await repository.update(
          existing.link.copyWith(
            url: url,
            title: title,
            faviconUrl: faviconUrl,
          ),
        );
        await repository.setTags(existing.id, _tags);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showFToast(context: context, title: const Text('Could not save link'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.link;
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
                    existing == null ? 'New link' : 'Edit link',
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
              control: FTextFieldControl.managed(controller: _urlController),
              label: const Text('URL'),
              hint: 'https://example.com',
              autofocus: existing == null,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: .next,
            ),
            const SizedBox(height: 12),
            FTextFormField(
              control: FTextFieldControl.managed(controller: _titleController),
              label: const Text('Title'),
              hint: 'Defaults to the domain',
              textInputAction: .done,
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
  }
}
