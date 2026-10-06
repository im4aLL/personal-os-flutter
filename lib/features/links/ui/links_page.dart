import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Links page, pushed over the shell from the More tab.
class LinksPage extends StatelessWidget {
  const LinksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(title: Text('Links')),
      child: FCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Saved links with favicons, tags, search, and external opening.',
          ),
        ),
      ),
    );
  }
}
