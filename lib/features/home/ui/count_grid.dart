import 'package:material_ui/material_ui.dart';

import 'count_card.dart';
import 'count_card_data.dart';

/// Two-column grid of count cards. When the number of cards is odd the last
/// card spans the full width so the grid never ends with an orphan half card.
class CountGrid extends StatelessWidget {
  const CountGrid({super.key, required this.cards});

  final List<CountCardData> cards;

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < cards.length; i++)
              SizedBox(
                width: i == cards.length - 1 && cards.length.isOdd
                    ? constraints.maxWidth
                    : half,
                child: CountCard(data: cards[i]),
              ),
          ],
        );
      },
    );
  }
}
