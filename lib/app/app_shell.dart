import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../features/home/ui/home_page.dart';
import '../features/more/ui/more_page.dart';
import '../features/notes/ui/notes_page.dart';
import '../features/settings/ui/settings_page.dart';
import '../features/todo/ui/todo_page.dart';

/// Root navigation shell holding the five bottom tabs.
///
/// The tabs live in an [IndexedStack] so each page keeps its own state while
/// switching between them.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _pages = <Widget>[
    HomePage(),
    TodoPage(),
    NotesPage(),
    MorePage(),
    SettingsPage(),
  ];

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      // Inner page scaffolds own their own padding and keyboard insets, so the
      // shell must not apply either at this level (avoids double padding and a
      // doubled bottom inset under the keyboard). Matches the pushed More routes.
      childPad: false,
      resizeToAvoidBottomInset: false,
      footer: FBottomNavigationBar(
        index: _selectedIndex,
        onChange: (index) => setState(() => _selectedIndex = index),
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
      child: IndexedStack(index: _selectedIndex, children: _pages),
    );
  }
}
