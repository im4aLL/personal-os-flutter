import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../features/home/ui/home_page.dart';
import '../features/more/ui/more_page.dart';
import '../features/notes/ui/notes_page.dart';
import '../features/settings/ui/settings_page.dart';
import '../features/todo/ui/todo_page.dart';
import 'router.dart';
import 'shell_state.dart';

/// Root navigation shell holding the five bottom tabs.
///
/// The tabs live in an [IndexedStack] so each page keeps its own state while
/// switching between them. The selected index is shared through
/// [selectedTabProvider] so Home's count cards can switch tabs.
///
/// The tab stack sits inside a nested [Navigator], so pages pushed from More
/// (Links / Work Log / Projects) and Home (todo detail) open over the shell
/// while the bottom navigation bar stays visible. [NavigatorPopHandler] routes
/// the system back gesture to that inner navigator, and switching tabs first
/// returns the inner navigator to its root so a pushed page never hides the
/// newly selected tab.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  /// The inner navigator hosting the tab stack and the pages pushed over it.
  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedTabProvider);

    return FScaffold(
      // Inner page scaffolds own their own padding and keyboard insets, so the
      // shell must not apply either at this level (avoids double padding and a
      // doubled bottom inset under the keyboard). Matches the pushed More routes.
      childPad: false,
      resizeToAvoidBottomInset: false,
      footer: FBottomNavigationBar(
        index: selected.index,
        onChange: (index) {
          // Return to the tab before switching so a pushed page can never hide
          // the newly selected tab.
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
          ref.read(selectedTabProvider.notifier).selectIndex(index);
        },
        children: const [
          FBottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: Text('Home'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: Text('Todo'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.sticky_note_2_outlined),
            label: Text('Notes'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: Text('More'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: Text('Settings'),
          ),
        ],
      ),
      child: NavigatorPopHandler(
        onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
        child: Navigator(
          key: _navigatorKey,
          onGenerateRoute: _onGenerateRoute,
        ),
      ),
    );
  }

  /// Builds the root tab stack for the default route and a More feature page
  /// for its named route.
  Route<void>? _onGenerateRoute(RouteSettings settings) {
    if (settings.name == Navigator.defaultRouteName) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const _TabStack(),
      );
    }
    final builder = AppRoutes.routes[settings.name];
    return builder == null
        ? null
        : MaterialPageRoute<void>(settings: settings, builder: builder);
  }
}

/// The five pages behind the bottom navigation bar.
class _TabStack extends ConsumerWidget {
  const _TabStack();

  static const _pages = <Widget>[
    HomePage(),
    TodoPage(),
    NotesPage(),
    MorePage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedTabProvider);
    return IndexedStack(index: selected.index, children: _pages);
  }
}
