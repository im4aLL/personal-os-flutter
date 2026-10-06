import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// The Forui light theme (touch sizing).
final FThemeData lightTheme = FTheme.neutral.light.touch;

/// The Forui dark theme (touch sizing).
final FThemeData darkTheme = FTheme.neutral.dark.touch;

/// The material approximation of [lightTheme] used by the [MaterialApp] host shell.
final ThemeData lightMaterialTheme = lightTheme.toApproximateMaterialTheme();

/// The material approximation of [darkTheme] used by the [MaterialApp] host shell.
final ThemeData darkMaterialTheme = darkTheme.toApproximateMaterialTheme();

/// The user's selected theme mode.
///
/// The plan describes this as a `StateProvider<ThemeMode>`. In Riverpod 3
/// `StateProvider` moved to the legacy library, so it is expressed here as a
/// [Notifier] while keeping the same single-value, in-memory behavior.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Holds the selected [ThemeMode], defaulting to following the system.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Updates the selected [mode].
  ///
  /// In-memory only; Phase 8 persists the choice via shared_preferences.
  set mode(ThemeMode mode) => state = mode;
}
