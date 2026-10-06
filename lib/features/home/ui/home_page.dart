import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Home tab placeholder.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Home')),
      child: FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Your daily overview: due and overdue todos, feature counts, and recent activity.',
          ),
        ),
      ),
    );
  }
}
