import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const ProviderScope(child: PersonalOsApp()));
}

/// Root of the Personal OS app.
///
/// Wires the Riverpod scope around a Material host shell, then layers the
/// Forui theme, toaster, and tooltip group on top of every route.
class PersonalOsApp extends StatelessWidget {
  const PersonalOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      theme: FTheme.neutral.light.touch.toApproximateMaterialTheme(),
      darkTheme: FTheme.neutral.dark.touch.toApproximateMaterialTheme(),
      // Default behavior; Phase 1 drives this from a Riverpod provider.
      themeMode: ThemeMode.system,
      builder: (context, child) => FTheme(
        data: Theme.brightnessOf(context) == Brightness.light
            ? FTheme.neutral.light.touch
            : FTheme.neutral.dark.touch,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: const _HomePage(),
    );
  }
}

/// Phase 0 placeholder home screen.
class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      child: Center(
        child: FButton(
          mainAxisSize: MainAxisSize.min,
          onPress: () {},
          child: const Text('Personal OS'),
        ),
      ),
    );
  }
}
