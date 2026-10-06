import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Notes tab placeholder.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Notes')),
      child: FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Write markdown notes with tags, pinning, search, and a preview toggle.',
          ),
        ),
      ),
    );
  }
}
