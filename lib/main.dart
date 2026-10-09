import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_shell.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/prefs/shared_preferences_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load preferences before the first frame so hydration is synchronous and a
  // persisted theme is applied without a light/dark flash.
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const PersonalOsApp(),
    ),
  );
}

/// Root of the Personal OS app.
///
/// Wires the Riverpod scope around a Material host shell, then layers the
/// Forui theme, toaster, and tooltip group on top of every route. The shell
/// theme (light/dark/system) is driven by [themeModeProvider].
class PersonalOsApp extends ConsumerWidget {
  const PersonalOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      theme: lightMaterialTheme,
      darkTheme: darkMaterialTheme,
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => FTheme(
        data: Theme.brightnessOf(context) == Brightness.light
            ? lightTheme
            : darkTheme,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      routes: AppRoutes.routes,
      home: const AppShell(),
    );
  }
}
