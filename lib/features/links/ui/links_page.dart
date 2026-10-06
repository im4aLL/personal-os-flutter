import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Links page, pushed full-screen from the More tab.
class LinksPage extends StatelessWidget {
  const LinksPage({super.key});

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
        title: const Text('Links'),
      ),
      child: const FCard(
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
