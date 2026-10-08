import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Renders markdown [content] with Forui colors and typography.
///
/// This is the only file that knows about the markdown package, so the
/// renderer can be swapped without touching the editor. When [content] is blank
/// it shows a muted placeholder instead of an empty block.
class MarkdownPreview extends StatelessWidget {
  /// Creates a [MarkdownPreview] for [content].
  const MarkdownPreview({super.key, required this.content});

  /// The markdown source to render.
  final String content;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) {
      return Text(
        'Nothing here yet. Switch to Edit to start writing.',
        style: context.theme.typography.body.sm.copyWith(
          color: context.theme.colors.mutedForeground,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return MarkdownBody(
      data: content,
      styleSheet: _styleSheet(context),
    );
  }
}

/// Builds a [MarkdownStyleSheet] from the ambient Forui theme.
///
/// The markdown package falls back to a Material light theme for any style left
/// unset, which would render dark text on a dark background, so every visible
/// element is themed explicitly from Forui instead.
MarkdownStyleSheet _styleSheet(BuildContext context) {
  final theme = context.theme;
  final colors = theme.colors;
  final display = theme.typography.display;
  final body = theme.typography.body;
  final foreground = colors.foreground;
  // The note body reads one step smaller than the package default so long
  // notes feel lighter; headings keep their relative scale.
  final text = body.sm;

  return MarkdownStyleSheet(
    p: text.copyWith(color: foreground),
    a: text.copyWith(
      color: colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.primary,
    ),
    em: text.copyWith(fontStyle: FontStyle.italic),
    strong: text.copyWith(fontWeight: FontWeight.bold),
    del: text.copyWith(
      color: colors.mutedForeground,
      decoration: TextDecoration.lineThrough,
    ),
    code: text.copyWith(
      fontFamily: 'monospace',
      color: foreground,
      backgroundColor: colors.muted,
    ),
    h1: display.xl2.copyWith(color: foreground, fontWeight: FontWeight.w700),
    h2: display.lg.copyWith(color: foreground, fontWeight: FontWeight.w700),
    h3: display.md.copyWith(color: foreground, fontWeight: FontWeight.w600),
    h4: body.xl.copyWith(color: foreground, fontWeight: FontWeight.w600),
    h5: body.lg.copyWith(color: foreground, fontWeight: FontWeight.w600),
    h6: body.md.copyWith(color: foreground, fontWeight: FontWeight.w600),
    blockquote: text.copyWith(color: colors.mutedForeground),
    blockquoteDecoration: BoxDecoration(
      color: colors.muted,
      border: Border(left: BorderSide(color: colors.border, width: 3)),
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.muted,
      borderRadius: BorderRadius.circular(6),
    ),
    checkbox: text.copyWith(color: colors.primary),
    listBullet: text.copyWith(color: foreground),
    tableHead: text.copyWith(
      color: foreground,
      fontWeight: FontWeight.bold,
    ),
    tableBody: text.copyWith(color: foreground),
    tableBorder: TableBorder.all(color: colors.border),
    tableCellsDecoration: const BoxDecoration(),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.border)),
    ),
    // Keep the renderer in step with the system text-size setting; the
    // package's fallback would otherwise be discarded by the merge.
    textScaler: MediaQuery.textScalerOf(context),
  );
}
