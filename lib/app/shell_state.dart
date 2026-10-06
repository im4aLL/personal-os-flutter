import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The five bottom tabs, in display order.
enum AppTab {
  /// Home dashboard.
  home,

  /// Todo list.
  todo,

  /// Notes list.
  notes,

  /// More (Links / Work Log / Projects).
  more,

  /// Settings.
  settings,
}

/// The currently selected bottom tab.
///
/// Shared so Home's count cards can switch tabs programmatically. The plan
/// describes a `StateProvider`; Riverpod 3 moved that to the legacy library, so
/// this is a [Notifier] with the same single-value, in-memory behavior.
final selectedTabProvider = NotifierProvider<SelectedTabNotifier, AppTab>(
  SelectedTabNotifier.new,
);

/// Holds the selected [AppTab], defaulting to Home.
class SelectedTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  /// Selects [tab].
  void select(AppTab tab) => state = tab;

  /// Selects the tab at [index] in [AppTab.values].
  void selectIndex(int index) => state = AppTab.values[index];
}
