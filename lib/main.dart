import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_shell.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/data/remote_write_sink.dart';
import 'core/prefs/shared_preferences_provider.dart';
import 'core/sync/sync_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load preferences before the first frame so hydration is synchronous and a
  // persisted theme is applied without a light/dark flash.
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        // Give the drift repositories the sync layer's stable write sink. The
        // sink depends only on the database, so changing sync configuration
        // never recreates a repository or restarts its watch stream.
        remoteWriteSinkProvider.overrideWith(
          (ref) => ref.watch(syncWriteSinkProvider),
        ),
      ],
      child: const PersonalOsApp(),
    ),
  );
}

/// Root of the Personal OS app.
///
/// Wires the Riverpod scope around a Material host shell, then layers the
/// Forui theme, toaster, and tooltip group on top of every route. The shell
/// theme (light/dark/system) is driven by [themeModeProvider].
///
/// Also owns the app lifecycle listener that runs a silent background sync when
/// the app resumes in configured cloud mode, a periodic sync every minute, and
/// a best-effort sync when the app is backgrounded or detached.
class PersonalOsApp extends ConsumerStatefulWidget {
  const PersonalOsApp({super.key});

  @override
  ConsumerState<PersonalOsApp> createState() => _PersonalOsAppState();
}

class _PersonalOsAppState extends ConsumerState<PersonalOsApp> {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _periodicSync;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: _syncOnResume,
      onPause: _syncOnBackground,
      onHide: _syncOnBackground,
      onDetach: _syncOnBackground,
    );
    // Periodic sync while the app is alive. The engine skips overlapping runs,
    // and [_autoSync] skips while cloud mode is unconfigured.
    _periodicSync = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _autoSync(),
    );
  }

  @override
  void dispose() {
    _periodicSync?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Runs a silent background sync when the app resumes and cloud mode is fully
  /// configured. Silent so a transient failure never surfaces as a manual error.
  /// Gated on actual changes (see [_autoSync]) so an idle resume stays quiet.
  void _syncOnResume() => _autoSync();

  /// Best-effort sync when the app is backgrounded, hidden, or detached
  /// (close). The OS may kill a detaching app before the network run finishes,
  /// so this never blocks teardown; anything unsent stays queued for the next
  /// sync. Overlaps are harmless: [SyncController.syncNow] returns early while
  /// a run is in flight, so hide-then-pause ordering cannot double-sync.
  /// Gated on actual changes (see [_autoSync]).
  void _syncOnBackground() => _autoSync();

  /// One silent sync tick shared by the timer, resume, and background/detach
  /// hooks. Skips the full sync when neither side changed, so an idle device
  /// issues only a few cheap aggregate reads (and nothing at all offline).
  void _autoSync() {
    if (!ref.read(syncControllerProvider).canSync) return;
    ref.read(syncControllerProvider.notifier).syncIfChanged(silent: true);
  }

  @override
  Widget build(BuildContext context) {
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
