import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Todo tab placeholder.
class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Todo')),
      child: FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Create, prioritize, and track todos across Todo, In Progress, and Done.',
          ),
        ),
      ),
    );
  }
}
