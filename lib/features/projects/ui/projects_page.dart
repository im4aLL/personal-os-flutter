import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Projects page, pushed over the shell from the More tab.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Projects')),
      child: FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Week-based Gantt planner with phases and work items.'),
        ),
      ),
    );
  }
}
