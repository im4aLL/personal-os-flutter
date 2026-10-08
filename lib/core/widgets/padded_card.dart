import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// The [FCard] builder that applies the card's own [FCardStyle.padding] to its
/// child.
///
/// Forui's [FCard.defaultBuilder] returns the child unchanged, so every card
/// must pad its content explicitly with the style padding. This is the single
/// shared implementation of that builder.
Widget paddedCardBuilder(
  BuildContext context,
  FCardStyle style,
  Widget? child,
) => Padding(padding: style.padding, child: child);
