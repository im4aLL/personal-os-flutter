import 'package:material_ui/material_ui.dart';

/// Data for one Home count card.
class CountCardData {
  const CountCardData({
    required this.id,
    required this.label,
    required this.count,
    required this.icon,
    required this.onPress,
  });

  final String id;
  final String label;
  final int count;
  final IconData icon;
  final VoidCallback onPress;
}
