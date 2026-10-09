import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/repository_providers.dart';
import '../../../core/models/link.dart';
import '../../../core/widgets/delete_confirm_dialog.dart';
import '../../../core/widgets/padded_card.dart';
import 'link_edit_sheet.dart';

/// One link card: favicon, title, domain, tag badges, and an actions menu.
///
/// A tap opens the URL in the external browser; the trailing menu edits or
/// deletes the link without leaving the list.
class LinkCard extends ConsumerWidget {
  const LinkCard({super.key, required this.link});

  final LinkWithTags link;

  /// Opens [LinkCard.link] externally.
  ///
  /// Only http(s) URLs are launched, matching the write-path validation; other
  /// schemes are rejected here rather than handed to the OS. Uses [launchUrl]
  /// directly rather than `canLaunchUrl`: the Android `<queries>` manifest edits
  /// needed for capability checks are deferred, and an unlaunchable URL simply
  /// reports a toast here.
  Future<void> _open(BuildContext context) async {
    if (!isHttpUrl(link.url)) {
      showFToast(context: context, title: const Text('Could not open link'));
      return;
    }
    try {
      final launched = await launchUrl(
        Uri.parse(link.url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        showFToast(context: context, title: const Text('Could not open link'));
      }
    } catch (_) {
      if (context.mounted) {
        showFToast(context: context, title: const Text('Could not open link'));
      }
    }
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await showLinkEditSheet(context: context, link: link);
    if (saved && context.mounted) {
      showFToast(context: context, title: const Text('Link saved'));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: 'Delete link?',
      body: '"${link.title}" will be permanently deleted.',
    );
    if (!confirmed) return;

    try {
      await ref.read(linkRepositoryProvider).delete(link.id);
      if (context.mounted) {
        showFToast(context: context, title: const Text('Link deleted'));
      }
    } catch (_) {
      if (context.mounted) {
        showFToast(
          context: context,
          title: const Text('Could not delete link'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    // The popover menu builders below shadow `context` with the overlay's
    // context, which unmounts as the menu closes. Capture the card's context so
    // the menu actions keep a mounted context to show dialogs and toasts from.
    final cardContext = context;

    return FTappable(
      onPress: () => _open(context),
      child: FCard(
        // Tighter than the default 16 so the cards read as compact list items.
        style: const .delta(
          padding: .value(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        builder: paddedCardBuilder,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FaviconBox(url: link.url, faviconUrl: link.faviconUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    style: context.theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    linkDomain(link.url),
                    style: context.theme.typography.body.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (link.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final tag in link.tags)
                          FBadge(variant: .outline, child: Text(tag)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            FPopoverMenu(
              builder: (context, controller, _) => FButton.icon(
                variant: .ghost,
                size: .xs,
                semanticsLabel: 'Link actions',
                onPress: controller.toggle,
                child: const Icon(Icons.more_vert),
              ),
              menuBuilder: (context, controller, _) => [
                FItemGroup(
                  divider: .full,
                  children: [
                    FItem(
                      prefix: const Icon(Icons.edit_outlined),
                      title: const Text('Edit'),
                      onPress: () {
                        controller.hide();
                        _edit(cardContext);
                      },
                    ),
                    FItem(
                      variant: .destructive,
                      prefix: const Icon(Icons.delete_outline),
                      title: const Text('Delete'),
                      onPress: () {
                        controller.hide();
                        _delete(cardContext, ref);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A 32x32 favicon tile that falls back to the domain's first letter while the
/// image loads or when it fails.
class _FaviconBox extends StatelessWidget {
  const _FaviconBox({required this.url, required this.faviconUrl});

  final String url;
  final String? faviconUrl;

  @override
  Widget build(BuildContext context) {
    final domain = linkDomain(url);
    final letter = domain.isEmpty ? '?' : domain[0].toUpperCase();
    final favicon = faviconUrl;

    return Container(
      width: 32,
      height: 32,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.theme.colors.muted,
        borderRadius: context.theme.style.borderRadius.xs2,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            letter,
            style: context.theme.typography.body.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          // The image paints over the letter once loaded; the letter shows
          // through while loading and after an error (the builder returns an
          // empty box).
          if (favicon != null && favicon.isNotEmpty)
            Image.network(
              favicon,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
