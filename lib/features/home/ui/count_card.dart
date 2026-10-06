import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'count_card_data.dart';

/// One tappable count card.
class CountCard extends StatelessWidget {
  const CountCard({super.key, required this.data});

  final CountCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: data.onPress,
      child: FCard(
        builder: (context, style, child) =>
            Padding(padding: style.padding, child: child),
        child: Row(
          // Top-align so the icon sits on the count's first line rather than
          // floating in the middle of the taller count + label column.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, size: 20, color: colors.mutedForeground),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${data.count}',
                    key: ValueKey('home-count-${data.id}'),
                    style: context.theme.typography.display.lg.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.typography.body.xs.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.mutedForeground),
          ],
        ),
      ),
    );
  }
}
