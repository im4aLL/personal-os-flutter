import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/project.dart';
import '../../../core/utils/dates.dart';

/// Fixed row height for every Gantt item row (items and separators) so the
/// week columns stay aligned down the grid.
///
/// Tall enough for a two-line work item title (body.xs) plus its one-line
/// person/ticket line (body.xs2), while still reading as a compact list.
const double ganttRowHeight = 52;

/// Height of the week header row. Independent of [ganttRowHeight] because the
/// header only stacks two short lines and the week columns stay aligned
/// horizontally regardless.
const double ganttHeaderHeight = 56;

/// Width of the leading label column.
const double ganttLabelWidth = 176;

/// Width of one week column. Wide enough for the week number on line one and
/// `Mon d` (e.g. `Sep 28`) on line two at [ganttHeaderCellFontSize].
const double ganttCellWidth = 46;

/// Font size for the week header's date line. Small enough that `Sep 28` stays
/// on one line inside the narrow column instead of wrapping to `Sep` / `28`.
const double ganttHeaderCellFontSize = 11;

/// Font size for the bar's `W1-W2` range label. Smaller than the row title so
/// the range sits comfortably inside a one- or two-week bar.
const double ganttBarLabelFontSize = 10;

/// Returns the 1-based current week number within [project], or `null` when
/// today falls outside the project's week range or the start date is
/// malformed.
///
/// Week 1 starts on the project start date: week N covers
/// `startDate + (N - 1) * 7 days`. [now] is injectable so the page reads one
/// shared instant (`projectsNowProvider`) and passes it in instead of every
/// call site stamping its own `DateTime.now()`.
int? currentWeekFor(Project project, {DateTime? now}) {
  final start = _tryParseDate(project.startDate);
  if (start == null) return null;
  final today = dateOnly(now ?? DateTime.now());
  final elapsed = today.difference(start).inDays;
  if (elapsed < 0) return null;
  final week = elapsed ~/ 7 + 1;
  if (week < 1 || week > project.weekCount) return null;
  return week;
}

/// Parses a `YYYY-MM-DD` string, returning `null` when malformed instead of
/// throwing: project rows come from a database shared with other clients, so
/// one bad row must blank the dates, not crash the page.
DateTime? _tryParseDate(String value) {
  try {
    return parseDate(value);
  } catch (_) {
    return null;
  }
}

/// Returns the start date of week [weekNumber] (1-based) in [project], or
/// `null` when the project start date is malformed.
DateTime? weekStartDate(Project project, int weekNumber) {
  final start = _tryParseDate(project.startDate);
  if (start == null) return null;
  return DateTime(start.year, start.month, start.day + (weekNumber - 1) * 7);
}

/// Parses a phase hex color such as `#93C5FD`, falling back to [fallback]
/// when the value is malformed.
Color phaseColor(String hex, Color fallback) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return fallback;
  }
}

/// A dumb week-based Gantt grid for one project.
///
/// Items render flat in position order (matching the desktop Gantt) and
/// separator rows render inline as divider rows at their own position. Columns
/// are weeks 1..[Project.weekCount] mapped to real dates from
/// [Project.startDate] (a count below 1 renders the label column with no week
/// columns or bars); the current-week column is highlighted. Each item paints
/// a bar spanning startWeek..endWeek, colored by the item's phase color so the
/// phase is readable from the bar itself without separate phase header rows.
///
/// This widget never reads providers: [project] and [items] come in as
/// arguments and every interaction reports out through callbacks, so the
/// owning page (which supplies the data) stays in charge of writes. Tapping a
/// row edits via [onEditItem]; long-pressing a work item row lifts it and it
/// can be dropped on any other row, which reports the source and target
/// indices through [onReorder]. Separators are not draggable but still accept
/// a drop so items can be placed on either side of them.
class ProjectGantt extends StatelessWidget {
  /// Creates a [ProjectGantt].
  const ProjectGantt({
    super.key,
    required this.project,
    required this.items,
    this.now,
    this.onEditItem,
    this.onReorder,
  });

  /// The project being rendered (drives the week columns).
  final Project project;

  /// The work items with resolved phases, in position order.
  final List<WorkItemWithPhase> items;

  /// The instant used for the current-week highlight. Defaults to
  /// `DateTime.now()`; the page passes its shared instant so the header meta
  /// line and the grid highlight cannot desync.
  final DateTime? now;

  /// Called when an item row is tapped.
  final ValueChanged<WorkItemWithPhase>? onEditItem;

  /// Called with the dragged item's index and the target row's index when a
  /// work item row is dropped onto another row.
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    // The remote schema has no CHECK on week_count, so out-of-band rows may
    // carry 0 or negative values: render the label column with no week
    // columns or bars instead of throwing in `int.clamp`.
    final weekCount = project.weekCount < 1 ? 0 : project.weekCount;
    final totalWidth = ganttLabelWidth + weekCount * ganttCellWidth;
    final currentWeek = currentWeekFor(project, now: now);

    final rows = <Widget>[
      _WeekHeaderRow(
        project: project,
        weekCount: weekCount,
        currentWeek: currentWeek,
        totalWidth: totalWidth,
      ),
    ];
    // Flat walk in position order: separators stay exactly where they divide
    // the list.
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      rows.add(
        _ItemRow(
          item: item,
          index: index,
          weekCount: weekCount,
          currentWeek: currentWeek,
          totalWidth: totalWidth,
          onEditItem: onEditItem,
          onReorder: onReorder,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// The Gantt column header: a "Task" corner cell plus one cell per week with
/// the week number and its real start date (omitted when the project start
/// date is malformed).
class _WeekHeaderRow extends StatelessWidget {
  const _WeekHeaderRow({
    required this.project,
    required this.weekCount,
    required this.currentWeek,
    required this.totalWidth,
  });

  final Project project;
  final int weekCount;
  final int? currentWeek;
  final double totalWidth;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SizedBox(
      width: totalWidth,
      height: ganttHeaderHeight,
      child: Row(
        children: [
          SizedBox(
            width: ganttLabelWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Task',
                style: theme.typography.body.sm.copyWith(
                  color: theme.colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          for (var week = 1; week <= weekCount; week++)
            _WeekHeaderCell(
              week: week,
              date: weekStartDate(project, week),
              highlighted: week == currentWeek,
            ),
        ],
      ),
    );
  }
}

/// One week header cell: `W<n>` on the first line and the week's start date
/// (e.g. `Sep 28`) on the second, the date omitted when the project start date
/// is malformed.
class _WeekHeaderCell extends StatelessWidget {
  const _WeekHeaderCell({
    required this.week,
    required this.date,
    required this.highlighted,
  });

  final int week;
  final DateTime? date;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final start = date;
    // Two lines: the week number over the date. The date uses a smaller font
    // and never wraps, so it stays `Sep 28` rather than `Sep` / `28`.
    return Container(
      width: ganttCellWidth,
      height: ganttHeaderHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colors.primary.withValues(alpha: 0.14)
            : null,
        border: Border(left: BorderSide(color: theme.colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'W$week',
            style: theme.typography.body.xs.copyWith(
              color: highlighted
                  ? theme.colors.primary
                  : theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (start != null) ...[
            const SizedBox(height: 2),
            Text(
              formatDateShort(formatDate(start)),
              style: theme.typography.body.xs.copyWith(
                fontSize: ganttHeaderCellFontSize,
                color: theme.colors.mutedForeground,
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// One work item row: label cell (title, person/ticket line) plus week cells
/// with the phase-colored bar.
///
/// Separator rows keep the same two-zone layout (so columns stay aligned) but
/// render no label text and a thin divider line across the grid instead of a
/// week bar.
///
/// When [onReorder] is supplied every row is a drop target and non-separator
/// rows can be long-pressed and dragged; the row under the pointer paints an
/// insertion edge so the drop position is visible. Separators cannot be
/// dragged but still accept a drop, so items can be placed on either side of
/// them.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.index,
    required this.weekCount,
    required this.currentWeek,
    required this.totalWidth,
    required this.onEditItem,
    required this.onReorder,
  });

  final WorkItemWithPhase item;

  /// Position of this row in the flat, position-ordered item list.
  final int index;

  final int weekCount;
  final int? currentWeek;
  final double totalWidth;

  final ValueChanged<WorkItemWithPhase>? onEditItem;

  /// Called with the dragged row's index and this row's index when a drag is
  /// dropped here.
  final void Function(int oldIndex, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) {
    final content = _buildRow(context);
    final reorder = onReorder;
    if (reorder == null) return content;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => reorder(details.data, index),
      builder: (context, candidateData, rejectedData) {
        Widget child = content;
        if (!item.isSeparator) {
          child = LongPressDraggable<int>(
            data: index,
            // Anchor the card's top-left to the pointer (not the full-width
            // row's origin) so a long-press near the row's right edge does not
            // push the card off-screen, then lift it to sit over the finger.
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedbackOffset: const Offset(-16, -ganttRowHeight / 2),
            feedback: _DragFeedback(item: item, totalWidth: totalWidth),
            childWhenDragging: Opacity(opacity: 0.35, child: content),
            child: content,
          );
        }
        if (candidateData.isEmpty) return child;
        final draggedIndex = candidateData.first;
        if (draggedIndex == null) return child;
        // Paint the insertion edge on the side the drop will land: dragging
        // from below this row (a higher source index) inserts above it, and
        // dragging from above inserts below.
        final above = draggedIndex > index;
        final edge = BorderSide(color: context.theme.colors.primary, width: 2);
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: above ? edge : BorderSide.none,
              bottom: above ? BorderSide.none : edge,
            ),
          ),
          child: child,
        );
      },
    );
  }

  /// The static row: tappable label cell plus the week cells and bar.
  Widget _buildRow(BuildContext context) {
    final theme = context.theme;
    final gridWidth = weekCount * ganttCellWidth;
    return FTappable(
      onPress: onEditItem == null ? null : () => onEditItem!(item),
      child: SizedBox(
        width: totalWidth,
        height: ganttRowHeight,
        child: Row(
          children: [
            SizedBox(
              width: ganttLabelWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ItemLabel(item: item),
                ),
              ),
            ),
            SizedBox(
              width: gridWidth,
              height: ganttRowHeight,
              child: Stack(
                children: [
                  Row(
                    children: [
                      for (var week = 1; week <= weekCount; week++)
                        Container(
                          width: ganttCellWidth,
                          height: ganttRowHeight,
                          decoration: BoxDecoration(
                            color: week == currentWeek
                                ? theme.colors.primary.withValues(alpha: 0.10)
                                : null,
                            border: Border(
                              left: BorderSide(color: theme.colors.border),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (item.isSeparator)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: ganttRowHeight / 2,
                      child: Container(
                        height: 1,
                        color: theme.colors.mutedForeground.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    )
                  else if (weekCount >= 1)
                    _Bar(item: item, weekCount: weekCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The label-cell content for one work item.
///
/// Separators are pure dividers: no label text, just the line the row paints
/// across the grid. Work items show the title in the default foreground color,
/// struck through when done, wrapping to at most two lines, and, when present,
/// a muted person/ticket line beneath it.
class _ItemLabel extends StatelessWidget {
  const _ItemLabel({required this.item});

  final WorkItemWithPhase item;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    if (item.isSeparator) {
      return const SizedBox.shrink();
    }
    final details = [
      if ((item.person ?? '').trim().isNotEmpty) item.person!.trim(),
      if ((item.jiraTicket ?? '').trim().isNotEmpty) item.jiraTicket!.trim(),
    ].join('  ');
    // The title always uses the default foreground; only done work carries a
    // decoration, so status reads through the strikethrough rather than color.
    final decoration = item.status == WorkItemStatus.done
        ? TextDecoration.lineThrough
        : TextDecoration.none;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: theme.typography.body.xs.copyWith(
            color: theme.colors.foreground,
            fontWeight: FontWeight.w500,
            decoration: decoration,
            decorationColor: theme.colors.foreground,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            details,
            style: theme.typography.body.xs2.copyWith(
              color: theme.colors.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// The compact card that follows the pointer while a work item row is dragged.
///
/// It echoes the dragged row's phase color and label so the target stays clear
/// once the source row fades to [Opacity]. [totalWidth] bounds the card so a
/// narrow project grid still keeps the card on-screen.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.item, required this.totalWidth});

  final WorkItemWithPhase item;
  final double totalWidth;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final phase = item.phase;
    final fill = phase == null
        ? theme.colors.mutedForeground
        : phaseColor(phase.color, theme.colors.mutedForeground);
    return Material(
      color: theme.colors.background,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: totalWidth,
          minHeight: ganttRowHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _ItemLabel(item: item)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phase-colored bar spanning startWeek..endWeek (clamped into
/// 1..[weekCount] for painting; range validation lives in the edit sheet).
///
/// The fill is the item's phase color so the phase stays readable from the bar
/// now that the grid no longer emits phase header rows; unphased items fall
/// back to the muted foreground. The bar's range label picks black or white by
/// the fill's luminance so it stays legible on both pale preset colors and
/// arbitrary colors set by other clients.
///
/// [weekCount] is always at least 1 here: the row skips the bar otherwise, so
/// the clamp cannot throw. Wide bars carry their `W<start>-W<end>` range;
/// narrow bars stay empty because the label cell already shows the title.
class _Bar extends StatelessWidget {
  const _Bar({required this.item, required this.weekCount});

  final WorkItemWithPhase item;
  final int weekCount;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final start = item.startWeek.clamp(1, weekCount);
    final end = item.endWeek.clamp(1, weekCount);
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    final left = (lo - 1) * ganttCellWidth + 2;
    final width = (hi - lo + 1) * ganttCellWidth - 4;
    const barHeight = 20.0;

    final phase = item.phase;
    final fill = phase == null
        ? theme.colors.mutedForeground
        : phaseColor(phase.color, theme.colors.mutedForeground);
    final foreground = fill.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    final showRange = width >= 60;

    return Positioned(
      left: left,
      top: (ganttRowHeight - barHeight) / 2,
      child: Container(
        width: width,
        height: barHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: showRange
            ? Text(
                lo == hi ? 'W$lo' : 'W$lo-W$hi',
                style: theme.typography.body.xs.copyWith(
                  fontSize: ganttBarLabelFontSize,
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              )
            : null,
      ),
    );
  }
}
