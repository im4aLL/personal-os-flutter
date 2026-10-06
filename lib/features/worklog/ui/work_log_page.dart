import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Work Log page, pushed full-screen from the More tab.
class WorkLogPage extends StatelessWidget {
  const WorkLogPage({super.key});

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
        title: const Text('Work Log'),
      ),
      child: const FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Date-ranged work entries grouped by ISO week, with filters and presets.',
          ),
        ),
      ),
    );
  }
}
