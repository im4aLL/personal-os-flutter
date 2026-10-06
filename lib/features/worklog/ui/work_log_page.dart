import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Work Log page, pushed over the shell from the More tab.
class WorkLogPage extends StatelessWidget {
  const WorkLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Work Log')),
      child: FCard(
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
