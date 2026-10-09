import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/work_log.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/centered_message.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/work_log_providers.dart';
import 'work_log_card.dart';
import 'work_log_edit_sheet.dart';

/// Work Log page, pushed over the shell from the More tab.
///
/// Entries group under ISO week headers ([weekLabel]) and narrow by a date
/// preset plus search text. The search query, its visibility, and the preset
/// live in [workLogFilterProvider], which is auto-disposed, so the filter
/// resets when this pushed page closes. List data is stream-based, so
/// add/edit/delete (including entries created from todos) update the list
/// instantly.
class WorkLogPage extends ConsumerStatefulWidget {
  /// Creates a [WorkLogPage].
  const WorkLogPage({super.key});

  @override
  ConsumerState<WorkLogPage> createState() => _WorkLogPageState();
}

class _WorkLogPageState extends ConsumerState<WorkLogPage> {
  /// Owns the search field's text so it can be cleared whenever the shared
  /// filter clears the query (hiding search).
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Toggles the search field.
  ///
  /// Hiding also clears the field's text; the shared query is cleared by
  /// [WorkLogNotifier.setShowSearch] at the same time.
  void _toggleSearch() {
    final showSearch = !ref.read(workLogFilterProvider).showSearch;
    ref.read(workLogFilterProvider.notifier).setShowSearch(showSearch);
    if (!showSearch) _searchController.clear();
  }

  /// Opens the add-entry sheet and confirms a successful save.
  Future<void> _createLog() async {
    final saved = await showWorkLogEditSheet(context: context);
    if (saved && mounted) {
      showFToast(context: context, title: const Text('Work log saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(filteredWorkLogsProvider);
    final filter = ref.watch(workLogFilterProvider);
    // The single instant shared with preset filtering and counts, so the
    // week headers below cannot desync from the filter at a day/week
    // boundary. Grouping keys stay on weekKey(startDate) with no now.
    final pageNow = ref.watch(workLogNowProvider);

    return FScaffold(
      // The column owns the content padding, so the scaffold must not add its
      // own page padding on top (which would double the horizontal inset).
      childPad: false,
      header: FHeader.nested(
        titleAlignment: AlignmentDirectional.centerStart,
        title: const Text('Work Log'),
        suffixes: [
          FHeaderAction(
            // The icon doubles as the toggle: an open field shows a close icon
            // so tapping it again reads as "dismiss search".
            icon: Icon(filter.showSearch ? Icons.close : Icons.search),
            semanticsLabel: filter.showSearch
                ? 'Hide search'
                : 'Search work logs',
            onPress: _toggleSearch,
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              if (filter.showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: _searchController,
                      // Ignore notifications whose text already matches the
                      // filter (programmatic clears, caret/focus changes).
                      onChange: (value) {
                        if (value.text !=
                            ref.read(workLogFilterProvider).query) {
                          ref
                              .read(workLogFilterProvider.notifier)
                              .setQuery(value.text);
                        }
                      },
                    ),
                    hint: 'Search work logs',
                    autofocus: true,
                    // Forui paints its own clear button when the predicate
                    // holds; clearing routes back through [onChange], so the
                    // filter resets.
                    clearable: (value) => value.text.isNotEmpty,
                    prefixBuilder: (context, style, variants) =>
                        FTextField.prefixIconBuilder(
                          context,
                          style,
                          variants,
                          const Icon(Icons.search),
                        ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _PresetTabs(),
              ),
              Expanded(
                child: logs.when(
                  skipLoadingOnReload: true,
                  loading: () => const Center(child: FCircularProgress()),
                  error: (_, _) =>
                      const CenteredMessage('Could not load work logs.'),
                  data: (items) => ListView(
                    // Extra bottom padding clears the floating add button.
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    children: [
                      if (items.isEmpty)
                        AppEmptyState(_emptyMessage(filter))
                      else
                        ..._groupedItems(context, items, pageNow),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FButton.icon(
              variant: .primary,
              size: .lg,
              onPress: _createLog,
              semanticsLabel: 'New work log',
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  /// Groups [logs] under ISO week headers, preserving the repository order
  /// (newest start date first) so headers stay chronological.
  ///
  /// [now] is the shared instant from [workLogNowProvider] so headers use the
  /// same instant as preset filtering and counts.
  List<Widget> _groupedItems(
    BuildContext context,
    List<WorkLogWithTags> logs,
    DateTime now,
  ) {
    final theme = context.theme;
    final widgets = <Widget>[];
    String? currentKey;
    for (final log in logs) {
      final key = weekKey(log.startDate);
      if (key != currentKey) {
        currentKey = key;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 4 : 16, bottom: 8),
            child: Text(
              weekLabel(log.startDate, now: now),
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WorkLogCard(log: log),
        ),
      );
    }
    return widgets;
  }

  /// The empty message for the list, distinguishing a filtered result from an
  /// empty list.
  String _emptyMessage(WorkLogFilter filter) {
    final needle = filter.query.trim();
    if (needle.isNotEmpty) return 'No work logs match "$needle".';
    return switch (filter.preset) {
      WorkLogPreset.all => 'No work logs yet. Tap + to add one.',
      WorkLogPreset.thisWeek => 'No work logs this week.',
      WorkLogPreset.lastWeek => 'No work logs last week.',
      WorkLogPreset.thisMonth => 'No work logs this month.',
    };
  }
}

/// The four date preset tabs: All / This week / Last week / This month.
///
/// Each label carries the live count for its preset (respecting the shared
/// search query, like the Todo status counts). The filter is the single
/// source of truth via lifted control: the selected tab follows
/// [workLogFilterProvider]'s preset and taps write back to it, so the
/// highlight cannot desync from the filter when the layout above the tabs
/// changes.
class _PresetTabs extends ConsumerWidget {
  const _PresetTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(workLogPresetCountsProvider).value;
    final preset = ref.watch(workLogFilterProvider.select((f) => f.preset));
    return FTabs(
      control: FTabControl.lifted(
        index: preset.index,
        onChange: (index) => ref
            .read(workLogFilterProvider.notifier)
            .setPreset(WorkLogPreset.values[index]),
      ),
      scrollable: true,
      children: [
        for (final preset in WorkLogPreset.values)
          FTabEntry(
            label: _PresetLabel(
              _presetName(preset),
              count: counts?[preset.index],
            ),
            // The grouped list below reads the filtered provider, so the tabs
            // act as a pure selector bar with no per-tab content of their own.
            child: const SizedBox.shrink(),
          ),
      ],
    );
  }

  /// The short tab label for [preset].
  String _presetName(WorkLogPreset preset) => switch (preset) {
    WorkLogPreset.all => 'All',
    WorkLogPreset.thisWeek => 'This week',
    WorkLogPreset.lastWeek => 'Last week',
    WorkLogPreset.thisMonth => 'This month',
  };
}

/// A preset tab label with a trailing count.
///
/// The count is omitted while the list is still loading ([count] is null), and
/// the label scales down if a long name plus a large count would otherwise
/// overflow the tab slot.
class _PresetLabel extends StatelessWidget {
  const _PresetLabel(this.label, {required this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: context.theme.typography.body.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ],
      ],
    ),
  );
}
