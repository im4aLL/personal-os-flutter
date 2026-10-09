import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/prefs/shared_preferences_provider.dart';

/// The shared_preferences key holding the selected [ThemeMode] name.
const String themeModeKey = 'theme_mode';

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
/// [Notifier] while keeping the same single-value behavior.
///
/// `StateProvider` is still available via the legacy import
/// (`package:flutter_riverpod/legacy.dart`), so using a [Notifier] here is a
/// deliberate preference rather than a forced migration.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Holds the selected [ThemeMode], defaulting to following the system.
///
/// The choice is device-local: it is persisted to shared_preferences under
/// [themeModeKey] and intentionally never written to `app_settings`, so it does
/// not sync across clients.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// Tail of the shared_preferences write queue.
  ///
  /// [select] is fire-and-forget, so writes are chained here to guarantee the
  /// last selection is the last write even if an earlier write is still
  /// settling. Errors are swallowed by the chain and never surface.
  Future<void> _writeChain = Future<void>.value();

  @override
  ThemeMode build() => _parseThemeMode(
    ref.watch(sharedPreferencesProvider).getString(themeModeKey),
  );

  /// Updates the selected [mode] and persists it.
  ///
  /// The UI flips immediately; a failed write only costs the choice surviving
  /// the next restart.
  void select(ThemeMode mode) {
    state = mode;
    final preferences = ref.read(sharedPreferencesProvider);
    _writeChain = _writeChain
        .then((_) => preferences.setString(themeModeKey, mode.name))
        .then<void>((_) {}, onError: (_) {});
  }
}

/// Parses a stored [ThemeMode] name, defaulting to [ThemeMode.system] when the
/// value is absent or unrecognized.
ThemeMode _parseThemeMode(String? value) {
  for (final mode in ThemeMode.values) {
    if (mode.name == value) return mode;
  }
  return ThemeMode.system;
}
