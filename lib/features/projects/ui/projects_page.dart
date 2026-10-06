import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Projects page, pushed full-screen from the More tab.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: FHeader.nested(
        prefixes: [
          FHeaderAction(
            icon: const Icon(Icons.arrow_back),
            onPress: () => Navigator.maybePop(context),
          ),
        ],
        title: const Text('Projects'),
      ),
      child: const FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Week-based Gantt planner with phases and work items.'),
        ),
      ),
    );
  }
}
