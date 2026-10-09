import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's [SharedPreferences] instance.
///
/// Overridden in `main()` with the instance loaded before the first frame, so
/// persisted values (such as the theme mode) can be read synchronously during
/// the first build and the UI never flashes the wrong theme. Accessing this
/// without the override is a programming error and throws.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a loaded '
    'SharedPreferences instance.',
  );
});
