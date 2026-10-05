import 'package:flutter/material.dart';
import 'package:personal_os_flutter/theme/catppuccin_palette.dart';

class AppTheme {
  AppTheme._();

  /// Light theme, built from the Catppuccin Latte flavor.
  static final ThemeData light = _build(
    CatppuccinPalette.latte,
    Brightness.light,
  );

  /// Dark theme, built from the Catppuccin Mocha flavor.
  static final ThemeData dark = _build(
    CatppuccinPalette.mocha,
    Brightness.dark,
  );

  static ThemeData _build(CatppuccinPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: p.mauve,
      onPrimary: p.base,
      primaryContainer: p.surface0,
      onPrimaryContainer: p.text,
      secondary: p.blue,
      onSecondary: p.base,
      secondaryContainer: p.surface1,
      onSecondaryContainer: p.text,
      tertiary: p.pink,
      onTertiary: p.base,
      tertiaryContainer: p.surface1,
      onTertiaryContainer: p.text,
      error: p.red,
      onError: p.base,
      errorContainer: p.maroon,
      onErrorContainer: p.base,
      surface: p.base,
      onSurface: p.text,
      onSurfaceVariant: p.subtext1,
      // Elevated surfaces grow lighter in dark mode and darker in light mode.
      surfaceContainerLowest: isDark ? p.crust : p.base,
      surfaceContainerLow: p.mantle,
      surfaceContainer: isDark ? p.base : p.crust,
      surfaceContainerHigh: p.surface0,
      surfaceContainerHighest: p.surface1,
      outline: p.overlay1,
      outlineVariant: p.surface2,
      shadow: p.crust,
      scrim: p.crust,
      inverseSurface: p.text,
      onInverseSurface: p.base,
      inversePrimary: p.lavender,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.base,
      appBarTheme: AppBarTheme(backgroundColor: p.mantle, elevation: 0),
    );
  }
}
